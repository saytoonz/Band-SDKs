import 'package:test/test.dart';
import 'package:thrivnme_wearable_protocol/wearable_protocol.dart';

import 'support/synthetic_packets.dart';

const startTime = DeviceUnixTime(0x12345678);
const mode = StoredPpgMode.mode1;

final class TransferFixture {
  TransferFixture({
    Duration writeTimeout = const Duration(seconds: 5),
    Duration receiveTimeout = const Duration(seconds: 5),
  }) : manager = StoredPpgTransfer(
            writeTimeout: writeTimeout, receiveTimeout: receiveTimeout) {
    manager.events.listen(events.add);
    connection = manager.openConnection();
    addTearDown(manager.dispose);
  }

  final StoredPpgTransfer manager;
  final events = <StoredPpgTransferEvent>[];
  late StoredPpgConnection connection;
  final payload = ppgRecord();

  Iterable<StoredPpgWrite> get writes => events.whereType<StoredPpgWrite>();
  Iterable<StoredPpgProgress> get progress =>
      events.whereType<StoredPpgProgress>();
  Iterable<StoredPpgFinished> get finished =>
      events.whereType<StoredPpgFinished>();

  void send(List<int> bytes) =>
      manager.notification(connection, notification(bytes));
  void count(int count) => send([0xeb, 2, 0, count]);
  void header(int index) => send(ppgHeader(2)..[7] = index);
  void first() => send(ppgFragment(1, 2, payload.sublist(0, 301)));
  void last() => send(ppgFragment(2, 2, payload.sublist(301)));

  Future<void> start() async {
    manager.start(connection, mode, startTime);
    await flushEvents();
  }

  void confirmLatest() => manager.writeResult(writes.last, succeeded: true);
  void block(int index) {
    header(index);
    first();
    last();
  }
}

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

void main() {
  test('completes two blocks only after their transport acknowledgments',
      () async {
    final f = TransferFixture();
    await f.start();
    expect(f.writes.single.kind, StoredPpgWriteKind.request);
    expect(f.writes.single.packet.bytes, [0xeb, 2, 1, 0x78, 0x56, 0x34, 0x12]);

    // Notifications can reach Dart before the transport write result.
    f.count(2);
    f.count(2);
    f.header(0);
    f.last();
    f.last();
    f.first();
    f.confirmLatest();
    await flushEvents();
    expect(f.writes.last.kind, StoredPpgWriteKind.acknowledgment);
    expect(f.writes.last.packet.bytes, [0xeb, 2, 4, 1]);
    expect(f.progress, isEmpty);
    expect(f.finished, isEmpty);

    // A duplicate from the first block and an early second block.
    f.last();
    f.header(0);
    f.block(1);
    f.confirmLatest();
    await flushEvents();
    expect(f.progress.single.block.wireIndex, 0);
    expect(f.finished, isEmpty);
    expect(f.writes, hasLength(3));

    f.confirmLatest();
    await flushEvents();
    expect(f.progress.map((p) => p.acknowledged), [1, 2]);
    expect(f.finished.single.reason, StoredPpgEnd.completed);
    expect(f.finished.single.total, 2);
    expect(f.finished.single.acknowledged, 2);
  });

  test(
      'times out a dropped fragment without sending an acknowledgment or retry',
      () async {
    final f = TransferFixture(receiveTimeout: const Duration(milliseconds: 50));
    final terminal = f.manager.events
        .firstWhere((event) => event is StoredPpgFinished)
        .then((event) => event as StoredPpgFinished);
    await f.start();
    f.confirmLatest();
    f.count(1);
    f.header(0);
    f.last();
    f.last();
    final result = await terminal;
    expect(result.reason, StoredPpgEnd.timedOut);
    expect(result.acknowledged, 0);
    expect(f.writes, hasLength(1));
  });

  test('times out a pending acknowledgment and ignores its late receipt',
      () async {
    final f = TransferFixture(writeTimeout: const Duration(milliseconds: 80));
    final terminal = f.manager.events
        .firstWhere((event) => event is StoredPpgFinished)
        .then((event) => event as StoredPpgFinished);
    await f.start();
    f.confirmLatest();
    f.count(1);
    f.block(0);
    await flushEvents();
    final ack = f.writes.last;
    expect(f.manager.isPending(ack), isTrue);
    expect((await terminal).reason, StoredPpgEnd.timedOut);
    expect(f.manager.isPending(ack), isFalse);
    f.manager.writeResult(ack, succeeded: true);
    await flushEvents();
    expect(f.finished, hasLength(1));
    expect(f.progress, isEmpty);
  });

  test('cancellation invalidates a queued write and reconnect starts cleanly',
      () async {
    final f = TransferFixture();
    await f.start();
    final old = f.connection;
    final request = f.writes.single;
    f.count(2);
    f.header(0);
    f.manager.cancel(old);
    f.manager.cancel(old);
    expect(f.manager.isPending(request), isFalse);
    expect(() => f.manager.start(old, mode, startTime), throwsStateError);

    f.connection = f.manager.openConnection();
    await f.start();
    f.manager.disconnect(old);
    f.manager.writeResult(request, succeeded: false);
    f.manager.notification(old, notification([0xeb, 2, 5]));
    f.confirmLatest();
    f.count(1);
    f.block(0);
    await flushEvents();
    f.confirmLatest();
    await flushEvents();
    expect(f.finished.map((e) => e.reason),
        [StoredPpgEnd.cancelled, StoredPpgEnd.completed]);
    expect(f.progress.single.block.wireIndex, 0);
  });

  test(
      'disconnect discards unfinished fragments and replaces old connection identity',
      () async {
    final f = TransferFixture();
    await f.start();
    f.confirmLatest();
    f.count(1);
    f.header(0);
    f.first();
    final old = f.connection;
    f.connection = f.manager.openConnection();
    await f.start();
    f.manager.notification(old, notification([0xeb, 2, 0, 10]));
    f.confirmLatest();
    f.count(0);
    await flushEvents();
    expect(f.finished.map((e) => e.reason),
        [StoredPpgEnd.disconnected, StoredPpgEnd.completed]);
    expect(f.finished.last.total, 0);
    expect(f.writes, hasLength(2));
  });

  test('reports a failed acknowledgment without marking its block delivered',
      () async {
    final f = TransferFixture();
    await f.start();
    f.confirmLatest();
    f.count(1);
    f.block(0);
    await flushEvents();
    final error = StateError('synthetic transport error');
    f.manager.writeResult(f.writes.last, succeeded: false, error: error);
    await flushEvents();
    expect(f.finished.single.reason, StoredPpgEnd.writeFailed);
    expect(f.finished.single.error, same(error));
    expect(f.progress, isEmpty);
  });

  test('honors device stop independently of a pending write', () async {
    final f = TransferFixture();
    await f.start();
    f.send([0xeb, 2, 5]);
    await flushEvents();
    expect(f.finished.single.reason, StoredPpgEnd.deviceStopped);
    expect(f.manager.isPending(f.writes.single), isFalse);
  });

  test('times out a missing request write result', () async {
    final f = TransferFixture(writeTimeout: const Duration(milliseconds: 80));
    final terminal =
        f.manager.events.firstWhere((event) => event is StoredPpgFinished);
    await f.start();
    f.count(1);
    f.block(0);
    expect((await terminal as StoredPpgFinished).reason, StoredPpgEnd.timedOut);
    expect(f.writes, hasLength(1));
    expect(f.progress, isEmpty);
  });

  test('bounds notifications received before a transport write result',
      () async {
    final f = TransferFixture();
    await f.start();
    for (var index = 1; index <= 257; index++) {
      f.send([0xeb, 2, 1, index & 255, index >> 8, 1, 1, 0]);
    }
    await flushEvents();
    expect(f.finished.single.reason, StoredPpgEnd.malformed);
    expect(f.manager.isPending(f.writes.single), isFalse);
  });

  final malformed = <String, void Function(TransferFixture)>{
    'short EB frame': (f) => f.send([0xeb, 2]),
    'out-of-range block count': (f) => f.count(128),
    'conflicting start': (f) {
      f.count(1);
      f.count(2);
    },
    'unexpected block index': (f) {
      f.count(2);
      f.header(1);
    },
    'truncated block header': (f) {
      f.count(1);
      f.send(ppgHeader(2).sublist(0, 12));
    },
    'conflicting duplicate fragment': (f) {
      f.count(1);
      f.header(0);
      f.first();
      f.send(ppgFragment(1, 2, [1]));
    },
    'invalid record contents': (f) {
      f.count(1);
      f.send(ppgHeader(1)..[7] = 0);
      f.send(ppgFragment(1, 1, [0xa0, 0, 0]));
    },
  };
  for (final scenario in malformed.entries) {
    test('rejects ${scenario.key} and frees the transfer state', () async {
      final f = TransferFixture();
      await f.start();
      f.confirmLatest();
      scenario.value(f);
      await flushEvents();
      expect(f.finished.single.reason, StoredPpgEnd.malformed);
      expect(f.finished.single.error, isA<FormatException>());
      expect(f.writes, hasLength(1));
      f.connection = f.manager.openConnection();
      await f.start();
      f.confirmLatest();
      f.count(0);
      await flushEvents();
      expect(f.finished.last.reason, StoredPpgEnd.completed);
    });
  }
}
