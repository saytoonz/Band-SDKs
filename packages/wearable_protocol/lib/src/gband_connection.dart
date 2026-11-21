import 'dart:async';

import 'ble_packet.dart';
import 'ble_transport.dart';
import 'gband.dart';
import 'measurements.dart';
import 'stored_ppg_transfer.dart';

const gBandService = 'f0080001-0451-4000-b000-000000000000';

/// Implement the authorized binding procedure using user-supplied credentials.
/// Return only after verifying the wearable's application-level success reply.
abstract interface class GBandAuthorizer {
  Future<void> authorize(GBandBindingChannel channel);
}

abstract interface class GBandBindingChannel {
  Stream<BlePacket> get notifications;
  Future<void> write(List<int> value);
}

final class GBandTimeouts {
  GBandTimeouts({
    this.scan = const Duration(seconds: 15),
    this.connect = const Duration(seconds: 10),
    this.discovery = const Duration(seconds: 5),
    this.subscribe = const Duration(seconds: 5),
    this.authorize = const Duration(seconds: 30),
    this.write = const Duration(seconds: 10),
    this.receive = const Duration(seconds: 30),
    this.cleanup = const Duration(seconds: 5),
  }) {
    if ([
      scan,
      connect,
      discovery,
      subscribe,
      authorize,
      write,
      receive,
      cleanup
    ].any((value) => value <= Duration.zero)) {
      throw ArgumentError('BLE timeouts must be positive');
    }
  }

  final Duration scan;
  final Duration connect;
  final Duration discovery;
  final Duration subscribe;
  final Duration authorize;
  final Duration write;
  final Duration receive;
  final Duration cleanup;
}

final class GBandConnectionException implements Exception {
  const GBandConnectionException(this.message);
  final String message;

  @override
  String toString() => 'GBand connection: $message';
}

final class GBandTransferException implements Exception {
  const GBandTransferException(this.result);
  final StoredPpgFinished result;

  @override
  String toString() => 'GBand stored PPG: ${result.reason.name}';
}

/// Coordinates one active GBand link. Owns link resources, not the transport.
final class GBandCoordinator {
  GBandCoordinator(this.transport, this.authorizer, {GBandTimeouts? timeouts})
      : timeouts = timeouts ?? GBandTimeouts();

  final BleTransport transport;
  final GBandAuthorizer authorizer;
  final GBandTimeouts timeouts;
  GBandSession? _current;
  bool _disposed = false;
  final _scans = <Future<void> Function()>{};

  /// An advertised service is a hint. Always verify capabilities after connect.
  Stream<BleAdvertisement> discover() {
    StreamSubscription<BleAdvertisement>? source;
    Timer? timer;
    late StreamController<BleAdvertisement> output;

    final stopped = Completer<void>();
    var stopping = false;
    Future<void> stop() async {
      if (stopping) return stopped.future;
      stopping = true;
      timer?.cancel();
      try {
        await Future<void>.microtask(() async {
          await source?.cancel().timeout(timeouts.cleanup);
        });
      } catch (error, stack) {
        output.addError(error, stack);
      } finally {
        _scans.remove(stop);
        stopped.complete();
        unawaited(output.close());
      }
    }

    output = StreamController(
      onListen: () {
        if (_disposed) {
          output.addError(StateError('Coordinator is disposed'));
          unawaited(output.close());
          return;
        }
        _scans.add(stop);
        timer = Timer(timeouts.scan, () => unawaited(stop()));
        try {
          source = transport.scan().listen((advertisement) {
            if (!stopping) output.add(advertisement);
          }, onError: (Object error, StackTrace stack) {
            if (!stopping) output.addError(error, stack);
          }, onDone: () => unawaited(stop()));
        } catch (error, stack) {
          output.addError(error, stack);
          unawaited(stop());
        }
      },
      onCancel: stop,
    );
    return output.stream;
  }

  Future<GBandSession> connect(String deviceId) async {
    if (_disposed || _current != null) {
      throw StateError('Coordinator is disposed or already owns a link');
    }
    final session = GBandSession._(transport.connect(deviceId), timeouts);
    _current = session;
    unawaited(session.closed.then((_) {
      if (identical(_current, session)) _current = null;
    }));

    try {
      await session._setup(authorizer);
      return session;
    } catch (_) {
      await session.disconnect();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _current?.disconnect();
  }

  Future<void> dispose() async {
    _disposed = true;
    await Future.wait<void>(
        [disconnect(), for (final stop in _scans.toList()) stop()]);
  }
}

/// An authorized session and its unique connection identity.
final class GBandSession {
  GBandSession._(this._link, this._timeouts)
      : _transfer = StoredPpgTransfer(
          writeTimeout: _timeouts.write,
          receiveTimeout: _timeouts.receive,
        );

  final BleLink _link;
  final GBandTimeouts _timeouts;
  final StoredPpgTransfer _transfer;
  final _closing = Completer<void>();
  final _closed = Completer<void>();
  Future<void> get closed => _closed.future;
  bool get isAuthorized => _authorized && !_closing.isCompleted;

  final _bindingNotifications = StreamController<BlePacket>.broadcast();
  final _cleanupErrors = StreamController<Object>.broadcast();
  Stream<Object> get cleanupErrors => _cleanupErrors.stream;
  StreamSubscription<BleConnectionState>? _stateListener;
  StreamSubscription<List<int>>? _notifyListener;
  StreamSubscription<StoredPpgTransferEvent>? _protocolListener;
  BleNotifications? _notifications;
  BleCharacteristic? _writer;
  bool _binding = false;
  bool _acceptBindingWrites = false;
  (Object, StackTrace)? _bindingFailure;
  bool _authorized = false;
  bool _transferUsed = false;
  StoredPpgConnection? _token;
  Future<void> _writeQueue = Future.value();

  Future<T> _step<T>(Future<T> operation, Duration timeout, String label) =>
      Future.any<T>([
        operation,
        _closing.future.then<T>(
            (_) => throw const GBandConnectionException('Link closed')),
      ]).timeout(timeout,
          onTimeout: () => throw TimeoutException(label, timeout));

  Future<void> _setup(GBandAuthorizer authorizer) async {
    void linkEnded() => unawaited(disconnect());
    _stateListener = _link.states.listen((state) {
      if (state == BleConnectionState.disconnected) linkEnded();
    }, onError: (Object _) => linkEnded(), onDone: linkEnded);

    await _step(_link.ready, _timeouts.connect, 'Connect');
    final services = await _step(
        _link.discoverServices(), _timeouts.discovery, 'Service discovery');
    final candidates =
        services.where((service) => service.uuid == gBandService);
    if (candidates.length != 1) {
      throw const GBandConnectionException('Expected one Veepoo GATT service');
    }
    final characteristics = candidates.single.characteristics;
    final notify = characteristics
        .where((characteristic) => characteristic.uuid == gBandNotify);
    final write = characteristics
        .where((characteristic) => characteristic.uuid == gBandWrite);
    if (notify.length != 1 ||
        !notify.single.canNotify ||
        write.length != 1 ||
        !write.single.canWriteWithResponse) {
      throw const GBandConnectionException(
          'Missing or ambiguous notify/write characteristics');
    }
    _writer = write.single;
    final notifications = _notifications = _link.subscribe(notify.single);
    _notifyListener = notifications.values.listen(_onValue,
        onError: (Object _) => linkEnded(), onDone: linkEnded);
    await _step(
        notifications.ready, _timeouts.subscribe, 'Notification subscription');
    _binding = true;
    _acceptBindingWrites = true;
    try {
      await _step(authorizer.authorize(_BindingChannel(this)),
          _timeouts.authorize, 'GBand authorization');
      _acceptBindingWrites = false;
      await _step(_writeQueue, _timeouts.write, 'Drain binding writes');
      if (_bindingFailure case (final error, final stack)) {
        Error.throwWithStackTrace(error, stack);
      }
      if (_closing.isCompleted)
        throw const GBandConnectionException('Link closed');
      _authorized = true;
    } finally {
      _acceptBindingWrites = false;
      _binding = false;
      unawaited(_bindingNotifications.close());
    }
  }

  void _onValue(List<int> value) {
    if (_closing.isCompleted || (!_binding && !isAuthorized)) return;
    try {
      final packet = BlePacket(
          characteristic: gBandNotify,
          kind: BlePacketKind.notification,
          bytes: value);
      if (_binding) {
        _bindingNotifications.add(packet);
      } else if (_token case final token?) {
        _transfer.notification(token, packet);
      }
    } on FormatException catch (error, stack) {
      if (_binding) {
        _bindingFailure ??= (error, stack);
        _bindingNotifications.addError(error, stack);
      } else {
        final output = _readOutput;
        _readOutput = null;
        output?.addError(error, stack);
        unawaited(output?.close());
        unawaited(disconnect());
      }
    }
  }

  Future<void> _enqueue(BlePacket packet,
      {required bool Function() allowed, bool bindingWrite = false}) {
    final result = _writeQueue.then((_) {
      if (_closing.isCompleted || !allowed()) {
        throw const GBandConnectionException('Write scope ended');
      }
      return _step(
        _link.write(_writer!, packet.bytes, BleWriteMode.withResponse),
        _timeouts.write,
        'Characteristic write',
      );
    });
    _writeQueue =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      if (bindingWrite) _bindingFailure ??= (error, stack);
    });
    return result;
  }

  StreamController<StoredPpgProgress>? _readOutput;

  /// One stored PPG operation per link. Broken or cancelled reads end the link.
  /// Listen for acknowledged blocks; terminal protocol failures are stream errors.
  Stream<StoredPpgProgress> readStoredPpg(
      StoredPpgMode mode, DeviceUnixTime from) {
    if (!isAuthorized || _transferUsed)
      throw StateError('An unused authorized link is required');
    // Validate before reserving the session.
    storedPpgRead(mode, from);
    _transferUsed = true;
    late StreamController<StoredPpgProgress> output;
    output = StreamController(
      onListen: () {
        if (!isAuthorized) {
          output.addError(const GBandConnectionException('Link closed'));
          unawaited(output.close());
          return;
        }
        _readOutput = output;
        final token = _token = _transfer.openConnection();
        _protocolListener = _transfer.events.listen((event) {
          if (event.connection != token || output.isClosed) return;
          switch (event) {
            case final StoredPpgWrite write:
              if (!_transfer.isPending(write)) return;
              unawaited(_enqueue(write.packet,
                      allowed: () => isAuthorized && _transfer.isPending(write))
                  .then<void>(
                      (_) => _transfer.writeResult(write, succeeded: true),
                      onError: (Object error) => _transfer.writeResult(write,
                          succeeded: false, error: error)));
            case final StoredPpgProgress progress:
              output.add(progress);
            case final StoredPpgFinished finished:
              if (finished.reason != StoredPpgEnd.completed) {
                output.addError(GBandTransferException(finished));
              }
              _readOutput = null;
              unawaited(output.close());
              unawaited(disconnect());
          }
        });
        _transfer.start(token, mode, from);
      },
      onCancel: disconnect,
    );
    return output.stream;
  }

  Future<void> disconnect() {
    if (_closing.isCompleted) return closed;
    _closing.complete();
    _binding = false;
    _authorized = false;
    if (_token case final token?) _transfer.disconnect(token);
    unawaited(_cleanup());
    return closed;
  }

  Future<void> _cleanup() async {
    // Run close even if a driver error prevents a preceding cleanup from finishing.
    Future<void> release(Future<void> Function() action) async {
      try {
        await action().timeout(_timeouts.cleanup);
      } catch (error) {
        _cleanupErrors.add(error);
      }
    }

    await Future.wait([
      release(() => _link.close()),
      release(() async => _notifications?.close()),
      release(() async => _notifyListener?.cancel()),
      release(() async => _stateListener?.cancel()),
      release(_transfer.dispose),
    ]);
    await release(() async => _protocolListener?.cancel());
    unawaited(_bindingNotifications.close());
    unawaited(_readOutput?.close());
    unawaited(_cleanupErrors.close());
    _closed.complete();
  }
}

final class _BindingChannel implements GBandBindingChannel {
  const _BindingChannel(this._session);
  final GBandSession _session;

  @override
  Stream<BlePacket> get notifications => _session._bindingNotifications.stream;

  @override
  Future<void> write(List<int> value) {
    if (!_session._acceptBindingWrites || _session._closing.isCompleted) {
      return Future.error(
          const GBandConnectionException('Binding scope ended'));
    }
    final packet = BlePacket(
        characteristic: gBandWrite, kind: BlePacketKind.write, bytes: value);
    return _session._enqueue(packet,
        allowed: () => _session._binding && _session._bindingFailure == null,
        bindingWrite: true);
  }
}
