import 'dart:async';

import 'package:thrivnme_wearable_protocol/wearable_protocol.dart';

import 'synthetic_packets.dart';

/// A scripted test double. None of its behavior is a firmware claim.
final class SyntheticPeripheral implements BleTransport {
  SyntheticPeripheral({
    this.blocks = 1,
    this.includeService = true,
    this.canNotify = true,
    this.canWrite = true,
    this.dropFragment = false,
    this.duplicateFragment = false,
    this.malformedFragment = false,
    this.disconnectDuringBlock = false,
    this.failWriteNumber,
    this.blockDelivery,
    this.connectionGate,
    this.subscriptionGate,
    this.writeGate,
  });

  final int blocks;
  final bool includeService;
  final bool canNotify;
  final bool canWrite;
  final bool dropFragment;
  final bool duplicateFragment;
  final bool malformedFragment;
  final bool disconnectDuringBlock;
  final int? failWriteNumber;
  final Future<void>? blockDelivery;
  final Future<void>? connectionGate;
  final Future<void>? subscriptionGate;
  final Future<void>? writeGate;

  final links = <SyntheticLink>[];
  int activeScans = 0;

  @override
  Stream<BleAdvertisement> scan() {
    late StreamController<BleAdvertisement> scan;
    scan = StreamController(
      onListen: () {
        activeScans++;
        scan.add(BleAdvertisement(
          deviceId: 'synthetic-gband',
          localName: 'Synthetic GBand fixture',
          services: includeService ? [gBandService] : [],
          manufacturerData: const {
            0xf8f8: [0]
          },
          rssi: -55,
        ));
      },
      onCancel: () {
        activeScans--;
        unawaited(scan.close());
      },
    );
    return scan.stream;
  }

  @override
  SyntheticLink connect(String deviceId) {
    if (deviceId != 'synthetic-gband') throw ArgumentError.value(deviceId);
    final link = SyntheticLink(this);
    links.add(link);
    return link;
  }
}

final class SyntheticLink implements BleLink {
  SyntheticLink(this.peripheral) {
    ready = _wait(peripheral.connectionGate).then((_) {
      _states.add(BleConnectionState.connected);
    });
  }

  final SyntheticPeripheral peripheral;
  final _states = StreamController<BleConnectionState>.broadcast();
  final _ended = Completer<void>();
  final trace = <String>[];
  final writes = <List<int>>[];
  SyntheticNotifications? notifications;
  BleCharacteristic? _notify;
  BleCharacteristic? _writer;
  int _block = 0;
  int _mode = 1;
  bool _readStarted = false;
  bool _writing = false;

  bool get isClosed => _ended.isCompleted;

  @override
  late final Future<void> ready;

  @override
  Stream<BleConnectionState> get states => _states.stream;

  Future<void> _wait(Future<void>? gate) async {
    await Future.any<void>([gate ?? Future.value(), _ended.future]);
    if (isClosed) throw StateError('Synthetic link closed');
  }

  @override
  Future<List<BleService>> discoverServices() async {
    await _wait(null);
    trace.add('discover');
    if (!peripheral.includeService) return [];
    _notify =
        BleCharacteristic(uuid: gBandNotify, canNotify: peripheral.canNotify);
    _writer = BleCharacteristic(
        uuid: gBandWrite, canWriteWithResponse: peripheral.canWrite);
    return [
      BleService(uuid: gBandService, characteristics: [_notify!, _writer!])
    ];
  }

  @override
  SyntheticNotifications subscribe(BleCharacteristic characteristic) {
    if (!identical(characteristic, _notify) ||
        !_notify!.canNotify ||
        notifications != null) {
      throw StateError('Invalid synthetic subscription');
    }
    trace.add('subscribe');
    return notifications = SyntheticNotifications(this);
  }

  @override
  Future<void> write(BleCharacteristic characteristic, List<int> value,
      BleWriteMode mode) async {
    if (_writing ||
        isClosed ||
        !identical(characteristic, _writer) ||
        notifications?.enabled != true ||
        mode != BleWriteMode.withResponse) {
      throw StateError('Invalid synthetic write lifecycle');
    }
    _writing = true;
    trace.add('write');
    writes.add(List.unmodifiable(value));
    try {
      await _wait(peripheral.writeGate);
      if (writes.length == peripheral.failWriteNumber) {
        throw StateError('Synthetic transport write failure');
      }
      // Non-EB traffic is opaque. The simulator provides no binding behavior.
      if (value.isEmpty || value.first != 0xeb) return;
      if (value.length == 7 && value[1] == 2 && !_readStarted) {
        _readStarted = true;
        _mode = value[2];
        notifications!.emit([0xeb, 2, 0, peripheral.blocks]);
        unawaited(_sendBlock());
      } else if (value.length == 4 &&
          value[1] == 2 &&
          value[2] == 4 &&
          value[3] == 1 &&
          _readStarted &&
          _block < peripheral.blocks) {
        _block++;
        unawaited(_sendBlock());
      } else {
        throw StateError('Unexpected synthetic PPG write');
      }
    } finally {
      _writing = false;
    }
  }

  Future<void> _sendBlock() async {
    if (_block >= peripheral.blocks) return;
    try {
      await _wait(peripheral.blockDelivery);
    } on StateError {
      return;
    }
    final notify = notifications!;
    final payload = ppgRecord();
    notify.emit(ppgHeader(2)
      ..[2] = _mode
      ..[7] = _block);
    final first = ppgFragment(1, 2, payload.sublist(0, 301))..[2] = _mode;
    notify.emit(first);
    if (peripheral.duplicateFragment) notify.emit(first);
    if (peripheral.disconnectDuringBlock) {
      await close();
      return;
    }
    if (!peripheral.dropFragment) {
      final finalBytes = peripheral.malformedFragment
          ? [0xeb, 2, _mode]
          : (ppgFragment(2, 2, payload.sublist(301))..[2] = _mode);
      notify.emit(finalBytes);
    }
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    _ended.complete();
    _states.add(BleConnectionState.disconnected);
    unawaited(_states.close());
    await notifications?.close();
  }
}

final class SyntheticNotifications implements BleNotifications {
  SyntheticNotifications(SyntheticLink link) {
    ready = link._wait(link.peripheral.subscriptionGate).then((_) {
      if (_values.isClosed) throw StateError('Synthetic subscription closed');
      enabled = true;
      link.trace.add('subscribed');
    });
  }

  final _values = StreamController<List<int>>.broadcast();
  bool enabled = false;
  bool get isClosed => _values.isClosed;

  @override
  late final Future<void> ready;

  @override
  Stream<List<int>> get values => _values.stream;

  void emit(List<int> value) {
    if (enabled) _values.add(List.unmodifiable(value));
  }

  @override
  Future<void> close() async {
    enabled = false;
    unawaited(_values.close());
  }
}
