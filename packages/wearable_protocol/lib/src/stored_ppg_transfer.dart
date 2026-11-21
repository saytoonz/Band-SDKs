import 'dart:async';

import 'ble_packet.dart';
import 'gband.dart';
import 'measurements.dart';

/// Use the token captured when registering callbacks for a connected GATT link.
final class StoredPpgConnection {
  StoredPpgConnection._();
}

enum StoredPpgEnd {
  completed,
  cancelled,
  disconnected,
  deviceStopped,
  timedOut,
  writeFailed,
  malformed,
}

sealed class StoredPpgTransferEvent {
  const StoredPpgTransferEvent(this.connection);
  final StoredPpgConnection connection;
}

enum StoredPpgWriteKind { request, acknowledgment }

/// The transport must report the result using this exact object.
final class StoredPpgWrite extends StoredPpgTransferEvent {
  StoredPpgWrite._(super.connection, this.kind, this.packet);

  final StoredPpgWriteKind kind;
  final BlePacket packet;
}

final class StoredPpgProgress extends StoredPpgTransferEvent {
  const StoredPpgProgress._(
      super.connection, this.acknowledged, this.total, this.block);

  final int acknowledged;
  final int total;
  final StoredPpgBlock block;
}

final class StoredPpgFinished extends StoredPpgTransferEvent {
  const StoredPpgFinished._(
      super.connection, this.reason, this.acknowledged, this.total, this.error);

  final StoredPpgEnd reason;
  final int acknowledged;
  final int? total;
  final Object? error;
}

/// Owns one stored PPG transfer on an already authorized connection.
///
/// Subscribe to [events] before starting. Dispatch each write once and report
/// its transport result. The manager emits no retries or cancellation writes.
/// Each transfer uses a new connection token because notifications carry no
/// transaction ID. This class never opens or closes a physical GATT connection.
final class StoredPpgTransfer {
  StoredPpgTransfer({
    this.writeTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 30),
  }) {
    if (writeTimeout <= Duration.zero || receiveTimeout <= Duration.zero) {
      throw ArgumentError('Transfer timeouts must be positive');
    }
  }

  final Duration writeTimeout;
  final Duration receiveTimeout;
  final _events = StreamController<StoredPpgTransferEvent>.broadcast();
  final _assembler = StoredPpgAssembler();
  // Bound early notifications that race the transport write callback.
  static const _maxDeferredPackets = 256;
  final _deferred = <BlePacket>[];
  StoredPpgConnection? _connection;
  StoredPpgMode? _mode;
  StoredPpgWrite? _pendingWrite;
  StoredPpgBlock? _pendingBlock;
  Timer? _timer;
  int? _total;
  int _acknowledged = 0;
  bool _used = false;
  bool _hasHeader = false;
  bool _disposed = false;

  Stream<StoredPpgTransferEvent> get events => _events.stream;

  StoredPpgConnection openConnection() {
    if (_disposed) throw StateError('Transfer manager is disposed');
    _finish(StoredPpgEnd.disconnected);
    _used = false;
    return _connection = StoredPpgConnection._();
  }

  void start(
      StoredPpgConnection connection, StoredPpgMode mode, DeviceUnixTime from) {
    if (_disposed ||
        _connection != connection ||
        _used ||
        !_events.hasListener) {
      throw StateError(
          'Start requires an unused connection and an event listener');
    }
    final request = storedPpgRead(mode, from);
    _used = true;
    _mode = mode;
    _write(StoredPpgWriteKind.request, request);
  }

  void disconnect(StoredPpgConnection connection) {
    if (_connection != connection) return;
    _finish(StoredPpgEnd.disconnected);
    _connection = null;
  }

  void cancel(StoredPpgConnection connection) {
    if (_connection == connection) _finish(StoredPpgEnd.cancelled);
  }

  /// Check just before dispatching a queued write event to your transport.
  bool isPending(StoredPpgWrite write) => identical(_pendingWrite, write);

  void writeResult(StoredPpgWrite write,
      {required bool succeeded, Object? error}) {
    if (!isPending(write)) return;
    if (!succeeded) {
      _finish(StoredPpgEnd.writeFailed, error);
      return;
    }

    _pendingWrite = null;
    final block = _pendingBlock;
    if (block != null) {
      _pendingBlock = null;
      _acknowledged++;
      _events.add(
          StoredPpgProgress._(_connection!, _acknowledged, _total!, block));
      if (_acknowledged == _total) {
        _finish(StoredPpgEnd.completed);
        return;
      }
      _hasHeader = false;
    }

    _arm(receiveTimeout);
    // Reprocess in order. A block can generate another outstanding write.
    final deferred = List<BlePacket>.of(_deferred);
    _deferred.clear();
    for (final packet in deferred) {
      notification(write.connection, packet);
    }
  }

  void notification(StoredPpgConnection connection, BlePacket packet) {
    final bytes = packet.bytes;
    if (connection != _connection ||
        _mode == null ||
        packet.kind != BlePacketKind.notification ||
        packet.characteristic != gBandNotify ||
        bytes.isEmpty ||
        bytes[0] != 0xeb ||
        (bytes.length >= 2 && bytes[1] != 2)) {
      return;
    }

    try {
      if (bytes.length < 3) throw const FormatException('Truncated EB header');
      if (bytes[2] == 5) {
        _finish(StoredPpgEnd.deviceStopped);
        return;
      }
      if (_pendingWrite != null) {
        if (_deferred.length == _maxDeferredPackets) {
          throw const FormatException(
              'Too many notifications before write result');
        }
        _deferred.add(packet);
        return;
      }
      _receive(packet);
    } on FormatException catch (error) {
      _finish(StoredPpgEnd.malformed, error);
    }
  }

  void _receive(BlePacket packet) {
    final bytes = packet.bytes;
    if (bytes[2] == 0) {
      if (bytes.length < 4 ||
          bytes[3] > 127 ||
          (_total != null && _total != bytes[3])) {
        throw const FormatException('Invalid stored PPG block count');
      }
      if (_total != null) return; // Duplicate start.
      _total = bytes[3];
      if (_total == 0) {
        _finish(StoredPpgEnd.completed);
      } else {
        _arm(receiveTimeout);
      }
      return;
    }

    if (_total == null || bytes[2] != _mode!.code || bytes.length < 7) {
      throw const FormatException('Unexpected stored PPG fragment');
    }
    final isHeader = bytes[3] == 0 && bytes[4] == 0;
    if (isHeader) {
      if (bytes.length < 16)
        throw const FormatException('Truncated block header');
      final index = bytes[7];
      if (index < _acknowledged) return; // Header for an acknowledged block.
      if (index != _acknowledged) {
        throw const FormatException('Unexpected stored PPG block index');
      }
      _hasHeader = true;
    }
    // An unlabelled continuation cannot be assigned before its block header.
    if (!_hasHeader) return;

    final block = _assembler.add(packet);
    if (block is StoredPpgBlock) {
      _assembler.reset();
      _pendingBlock = block;
      _write(StoredPpgWriteKind.acknowledgment, storedPpgBlockAcknowledgment());
    }
  }

  void _write(StoredPpgWriteKind kind, BlePacket packet) {
    final write = StoredPpgWrite._(_connection!, kind, packet);
    _pendingWrite = write;
    _arm(writeTimeout);
    _events.add(write);
  }

  void _arm(Duration timeout) {
    _timer?.cancel();
    _timer = Timer(timeout, () => _finish(StoredPpgEnd.timedOut));
  }

  void _finish(StoredPpgEnd reason, [Object? error]) {
    if (_mode == null) return;
    _timer?.cancel();
    _timer = null;
    _events.add(StoredPpgFinished._(
        _connection!, reason, _acknowledged, _total, error));
    _pendingWrite = null;
    _pendingBlock = null;
    _mode = null;
    _total = null;
    _acknowledged = 0;
    _hasHeader = false;
    _deferred.clear();
    _assembler.reset();
  }

  Future<void> dispose() {
    if (!_disposed) {
      _finish(StoredPpgEnd.cancelled);
      _connection = null;
      _disposed = true;
    }
    return _events.close();
  }
}
