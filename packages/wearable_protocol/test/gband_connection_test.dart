import 'dart:async';

import 'package:test/test.dart';
import 'package:thrivnme_wearable_protocol/wearable_protocol.dart';

import 'support/synthetic_peripheral.dart';

const device = 'synthetic-gband';
const start = DeviceUnixTime(0x12345678);

/// Explicit test authorization. Performs no wearable binding.
final class TestAuthorizer implements GBandAuthorizer {
  TestAuthorizer([this.run]);
  final Future<void> Function(GBandBindingChannel)? run;
  int calls = 0;

  @override
  Future<void> authorize(GBandBindingChannel channel) async {
    calls++;
    await run?.call(channel);
  }
}

GBandCoordinator coordinator(
  SyntheticPeripheral peripheral, {
  TestAuthorizer? authorizer,
  GBandTimeouts? timeouts,
}) {
  final result = GBandCoordinator(peripheral, authorizer ?? TestAuthorizer(),
      timeouts: timeouts);
  addTearDown(result.dispose);
  return result;
}

Matcher end(StoredPpgEnd reason) => isA<GBandTransferException>()
    .having((error) => error.result.reason, 'terminal reason', reason);

void main() {
  test('scans, verifies, subscribes, authorizes and reads one block', () async {
    final peripheral = SyntheticPeripheral();
    final authorizer = TestAuthorizer((_) async {
      final link = peripheral.links.single;
      expect(link.trace, ['discover', 'subscribe', 'subscribed']);
      expect(link.writes, isEmpty);
    });
    final adapter = coordinator(peripheral, authorizer: authorizer);
    final advertisement = await adapter.discover().first;
    expect(advertisement.deviceId, device);
    expect(advertisement.services, contains(gBandService));
    expect(advertisement.manufacturerData[0xf8f8], [0]);
    expect(peripheral.activeScans, 0);

    final session = await adapter.connect(advertisement.deviceId);
    expect(session.isAuthorized, isTrue);
    final results =
        await session.readStoredPpg(StoredPpgMode.mode1, start).toList();
    expect(results.single.block.records.single.ppg.samples.first, 0xf23456);
    expect(results.single.acknowledged, 1);
    final link = peripheral.links.single;
    expect(link.writes, [
      [0xeb, 2, 1, 0x78, 0x56, 0x34, 0x12],
      [0xeb, 2, 4, 1],
    ]);
    await session.closed;
    expect(session.isAuthorized, isFalse);
    expect(link.isClosed, isTrue);
    expect(link.notifications!.isClosed, isTrue);
  });

  test('reads multiple blocks with gated delivery and duplicate fragments',
      () async {
    final gate = Completer<void>();
    final peripheral = SyntheticPeripheral(
        blocks: 3, duplicateFragment: true, blockDelivery: gate.future);
    final session = await coordinator(peripheral).connect(device);
    final results = session.readStoredPpg(StoredPpgMode.mode2, start).toList();
    await Future<void>.delayed(Duration.zero);
    expect(peripheral.links.single.writes, hasLength(1));
    gate.complete();
    final progress = await results;
    expect(progress.map((event) => event.acknowledged), [1, 2, 3]);
    expect(progress.map((event) => event.block.wireIndex), [0, 1, 2]);
    expect(peripheral.links.single.writes.skip(1),
        List.generate(3, (_) => [0xeb, 2, 4, 1]));
    await session.closed;
  });

  for (final missing in ['service', 'notify', 'write']) {
    test('rejects missing or unsuitable $missing before authorization',
        () async {
      final peripheral = SyntheticPeripheral(
        includeService: missing != 'service',
        canNotify: missing != 'notify',
        canWrite: missing != 'write',
      );
      final authorizer = TestAuthorizer();
      final adapter = coordinator(peripheral, authorizer: authorizer);
      await expectLater(
          adapter.connect(device), throwsA(isA<GBandConnectionException>()));
      expect(authorizer.calls, 0);
      expect(peripheral.links.single.writes, isEmpty);
      expect(peripheral.links.single.isClosed, isTrue);
    });
  }

  test('authorization failure closes the link without PPG commands', () async {
    final peripheral = SyntheticPeripheral();
    final error = StateError('Synthetic binding rejected');
    final adapter = coordinator(peripheral,
        authorizer: TestAuthorizer((_) async => throw error));
    await expectLater(adapter.connect(device), throwsA(same(error)));
    expect(peripheral.links.single.writes, isEmpty);
    expect(peripheral.links.single.isClosed, isTrue);
  });

  test('serializes binding writes and revokes the binding channel', () async {
    final peripheral = SyntheticPeripheral();
    late GBandBindingChannel binding;
    final adapter =
        coordinator(peripheral, authorizer: TestAuthorizer((channel) async {
      binding = channel;
      // Opaque synthetic test values. These have no binding protocol meaning.
      await Future.wait([
        channel.write([0]),
        channel.write([1])
      ]);
    }));
    final session = await adapter.connect(device);
    expect(peripheral.links.single.writes, [
      [0],
      [1]
    ]);
    await expectLater(
        binding.write([2]), throwsA(isA<GBandConnectionException>()));
    await session.disconnect();
  });

  test('a swallowed transport error still prevents authorization', () async {
    final peripheral = SyntheticPeripheral(failWriteNumber: 1);
    final adapter =
        coordinator(peripheral, authorizer: TestAuthorizer((channel) async {
      try {
        await channel.write([0]);
      } on StateError {
        // A binding implementation must still never unlock a failed link.
      }
    }));
    await expectLater(adapter.connect(device), throwsStateError);
    expect(peripheral.links.single.isClosed, isTrue);
    expect(peripheral.links.single.writes, [
      [0]
    ]);
  });

  test('scan uses an absolute deadline and releases its subscription',
      () async {
    final peripheral = SyntheticPeripheral();
    final adapter = coordinator(peripheral,
        timeouts: GBandTimeouts(scan: const Duration(milliseconds: 50)));
    final advertisements = await adapter.discover().toList();
    expect(advertisements.single.deviceId, device);
    expect(peripheral.activeScans, 0);
  });

  test('authorization times out and later success cannot revive the link',
      () async {
    final gate = Completer<void>();
    final peripheral = SyntheticPeripheral();
    final adapter = coordinator(peripheral,
        authorizer: TestAuthorizer((_) => gate.future),
        timeouts: GBandTimeouts(authorize: const Duration(milliseconds: 50)));
    await expectLater(
        adapter.connect(device), throwsA(isA<TimeoutException>()));
    gate.complete();
    expect(peripheral.links.single.isClosed, isTrue);
    expect(peripheral.links.single.writes, isEmpty);
  });

  test('an outstanding driver write is cancelled after its deadline', () async {
    final gate = Completer<void>();
    final peripheral = SyntheticPeripheral(writeGate: gate.future);
    final session = await coordinator(peripheral,
            timeouts: GBandTimeouts(write: const Duration(milliseconds: 60)))
        .connect(device);
    await expectLater(
        session.readStoredPpg(StoredPpgMode.mode1, start).toList(),
        throwsA(end(StoredPpgEnd.timedOut)));
    await session.closed;
    gate.complete();
    expect(peripheral.links.single.writes, hasLength(1));
    expect(peripheral.links.single.isClosed, isTrue);
  });

  test('a dropped fragment times out the read without a retry or ack',
      () async {
    final peripheral = SyntheticPeripheral(dropFragment: true);
    final session = await coordinator(peripheral,
            timeouts: GBandTimeouts(receive: const Duration(milliseconds: 60)))
        .connect(device);
    await expectLater(
        session.readStoredPpg(StoredPpgMode.mode1, start).toList(),
        throwsA(end(StoredPpgEnd.timedOut)));
    await session.closed;
    expect(peripheral.links.single.writes, hasLength(1));
  });

  test('malformed notifications terminate the read and clean up', () async {
    final peripheral = SyntheticPeripheral(malformedFragment: true);
    final session = await coordinator(peripheral).connect(device);
    await expectLater(
        session.readStoredPpg(StoredPpgMode.mode1, start).toList(),
        throwsA(end(StoredPpgEnd.malformed)));
    await session.closed;
    expect(peripheral.links.single.isClosed, isTrue);
  });

  for (final writeNumber in [1, 2]) {
    test('transport write failure $writeNumber is observable', () async {
      final peripheral = SyntheticPeripheral(failWriteNumber: writeNumber);
      final session = await coordinator(peripheral).connect(device);
      await expectLater(
          session.readStoredPpg(StoredPpgMode.mode1, start).toList(),
          throwsA(end(StoredPpgEnd.writeFailed)));
      await session.closed;
      expect(peripheral.links.single.writes, hasLength(writeNumber));
    });
  }

  test('connection deadline closes pending link', () async {
    final peripheral =
        SyntheticPeripheral(connectionGate: Completer<void>().future);
    final adapter = coordinator(peripheral,
        timeouts: GBandTimeouts(connect: const Duration(milliseconds: 50)));
    await expectLater(
        adapter.connect(device), throwsA(isA<TimeoutException>()));
    expect(peripheral.links.single.isClosed, isTrue);
  });

  test('subscription deadline never enters binding', () async {
    final peripheral =
        SyntheticPeripheral(subscriptionGate: Completer<void>().future);
    final authorizer = TestAuthorizer();
    final adapter = coordinator(peripheral,
        authorizer: authorizer,
        timeouts: GBandTimeouts(subscribe: const Duration(milliseconds: 50)));
    await expectLater(
        adapter.connect(device), throwsA(isA<TimeoutException>()));
    expect(authorizer.calls, 0);
    expect(peripheral.links.single.notifications!.isClosed, isTrue);
  });

  test('transport disconnect surfaces a failure and permits a fresh session',
      () async {
    final peripheral = SyntheticPeripheral(disconnectDuringBlock: true);
    final adapter = coordinator(peripheral);
    final first = await adapter.connect(device);
    await expectLater(first.readStoredPpg(StoredPpgMode.mode1, start).toList(),
        throwsA(end(StoredPpgEnd.disconnected)));
    await first.closed;

    final second = await adapter.connect(device);
    expect(second, isNot(same(first)));
    expect(second.isAuthorized, isTrue);
    expect(peripheral.links, hasLength(2));
    expect(peripheral.links.last.writes, isEmpty);
    await first.disconnect();
    expect(second.isAuthorized, isTrue);
    await second.disconnect();
  });

  test(
      'cancelling a read closes old link and gated notifications cannot cross reconnect',
      () async {
    final gate = Completer<void>();
    final peripheral = SyntheticPeripheral(blockDelivery: gate.future);
    final adapter = coordinator(peripheral);
    final first = await adapter.connect(device);
    final listener =
        first.readStoredPpg(StoredPpgMode.mode1, start).listen((_) {
      fail('Cancelled read produced progress');
    });
    await Future<void>.delayed(Duration.zero);
    await listener.cancel();
    expect(first.isAuthorized, isFalse);
    expect(peripheral.links.first.isClosed, isTrue);

    final second = await adapter.connect(device);
    final results = second.readStoredPpg(StoredPpgMode.mode1, start).toList();
    gate.complete();
    expect(await results, hasLength(1));
    await second.closed;
    expect(peripheral.links.first.writes, hasLength(1));
    expect(peripheral.links.last.writes, hasLength(2));
  });

  test('disposing stops scans and cancels a pending connection', () async {
    final peripheral =
        SyntheticPeripheral(connectionGate: Completer<void>().future);
    final adapter = coordinator(peripheral);
    final scanClosed = adapter.discover().drain<void>();
    final connecting = expectLater(
        adapter.connect(device), throwsA(isA<GBandConnectionException>()));
    await adapter.dispose();
    await connecting;
    await scanClosed;
    expect(peripheral.activeScans, 0);
    expect(peripheral.links.single.isClosed, isTrue);
    await expectLater(adapter.connect(device), throwsStateError);
  });
}
