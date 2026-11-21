import 'package:test/test.dart';
import 'package:thrivnme_wearable_protocol/wearable_protocol.dart';

import 'support/synthetic_packets.dart';

void main() {
  test('GATT payload bytes are immutable and range checked', () {
    final bytes = [0xeb, 2];
    final packet = notification(bytes);
    bytes[0] = 0;
    expect(packet.bytes, [0xeb, 2]);
    expect(() => notification([256]), throwsFormatException);
    expect(() => notification(List.filled(513, 0)), throwsFormatException);
  });

  test('command builders match the statically observed payloads', () {
    expect(
        storedPpgRead(StoredPpgMode.mode2, const DeviceUnixTime(0x12345678))
            .bytes,
        [0xeb, 2, 2, 0x78, 0x56, 0x34, 0x12]);
    expect(storedPpgRead(StoredPpgMode.mode1, const DeviceUnixTime(-1)).bytes,
        [0xeb, 2, 1, 255, 255, 255, 255]);
    expect(rrHistoryRead(HistoryDay.beforeYesterday, 0x1234).bytes,
        [0x70, 2, 0x34, 0x12, ...List.filled(16, 0)]);
    expect(storedPpgBlockAcknowledgment().bytes, [0xeb, 2, 4, 1]);
    expect(() => rrHistoryRead(HistoryDay.today, 0), throwsRangeError);
  });

  test('PPG decodes only after every fragment, regardless of arrival order',
      () {
    final assembler = StoredPpgAssembler();
    final start =
        assembler.add(notification([0xeb, 2, 0, 4])) as StoredPpgStarted;
    expect(start.blockCount, 4);
    final data = ppgRecord();
    final first = notification(ppgFragment(1, 2, data.sublist(0, 301)));
    final last = notification(ppgFragment(2, 2, data.sublist(301)));
    expect(assembler.add(last), isNull);
    expect(assembler.add(last), isNull);
    expect(assembler.add(notification(ppgHeader(2))), isNull);
    final block = assembler.add(first) as StoredPpgBlock;
    expect(assembler.add(first), isNull);
    expect(block.wireIndex, 3);
    expect(block.time.seconds, 0x12345678);
    expect(block.reportedCrc, 0xbeef);
    expect(block.reportedCount, 1);
    final record = block.records.single;
    expect(record.declaredLength, 600);
    expect(record.ppg.samples.take(3), [0xf23456, null, 0]);
    expect(record.ppg.samples, hasLength(100));
    expect(record.ppg.sampling.rateHz, isNull);
    expect(record.ppg.metadata.time, isNull);
    expect(record.acceleration, hasLength(50));
    final sample = record.acceleration.first;
    expect([sample.x, sample.y, sample.z], [-1, -32768, 32767]);
    expect(sample.unit, isNull);
    expect(assembler.add(notification([0xeb, 2, 5])), isA<StoredPpgStopped>());
    expect(assembler.add(notification(ppgHeader(2))), isNull);
  });

  test('PPG decodes successive records and resets at a new block boundary', () {
    final assembler = StoredPpgAssembler();
    final record = ppgRecord();
    final payload = [...record, ...record];
    expect(assembler.add(notification(ppgHeader(3))), isNull);
    expect(
        assembler.add(notification(ppgFragment(1, 3, payload.sublist(0, 450)))),
        isNull);
    expect(assembler.add(notification(ppgFragment(3, 3, payload.sublist(900)))),
        isNull);
    final completed = assembler
            .add(notification(ppgFragment(2, 3, payload.sublist(450, 900))))
        as StoredPpgBlock;
    expect(completed.records, hasLength(2));
    assembler.reset();
    final nextHeader = ppgHeader(2)..[7] = 4;
    expect(assembler.add(notification(nextHeader)), isNull);
    expect(
        assembler.add(notification(ppgFragment(1, 2, record.sublist(0, 400)))),
        isNull);
    final next =
        assembler.add(notification(ppgFragment(2, 2, record.sublist(400))))
            as StoredPpgBlock;
    expect(next.wireIndex, 4);
    expect(next.records, hasLength(1));
  });

  test('PPG validates routing, fragment metadata and TLV bounds', () {
    final assembler = StoredPpgAssembler();
    expect(
        () => assembler.add(
            notification(ppgHeader(1), characteristic: gBandLivePpgNotify)),
        throwsFormatException);
    expect(() => assembler.add(notification(ppgHeader(1).sublist(0, 15))),
        throwsFormatException);
    expect(() => assembler.add(notification(ppgHeader(1))), throwsStateError);
    assembler.reset();
    expect(assembler.add(notification(ppgHeader(1))), isNull);
    expect(() => assembler.add(notification(ppgFragment(2, 1, [0xa0]))),
        throwsFormatException);
    assembler.reset();
    expect(assembler.add(notification(ppgHeader(1))), isNull);
    expect(
        () => assembler
            .add(notification(ppgFragment(1, 1, [0xa0, 1, 0, 0xa1, 0x2c, 1]))),
        throwsFormatException);
  });

  test(
      'RR sorts by fragment index and preserves unsigned payload and wall clock',
      () {
    final assembler = RrAssembler();
    final end = notification(rrContinuation());
    expect(assembler.add(end), isNull);
    expect(assembler.add(end), isNull);
    final block = assembler.add(notification(rrHeader())) as RrBlock;
    expect(block.data, [255, 128, 64, 1, 2, 3, 4]);
    expect(block.index, 2);
    expect(block.totalBlocks, 5);
    expect(block.daySelector, 1);
    final time = block.time;
    expect([
      time.year,
      time.month,
      time.day,
      time.hour,
      time.minute,
      time.second,
      time.utcOffset
    ], [
      2026,
      11,
      20,
      13,
      14,
      15,
      null
    ]);
    expect(assembler.add(end), isNull);
    assembler.reset();
    expect(assembler.add(notification([0x70, ...List.filled(19, 0)])),
        isA<RrZeroBlockResponse>());
  });

  test('RR rejects conflicting repeats, block changes and short data', () {
    final assembler = RrAssembler();
    expect(assembler.add(notification(rrHeader())), isNull);
    expect(() => assembler.add(notification(rrHeader(count: 8))),
        throwsFormatException);
    assembler.reset();
    expect(assembler.add(notification(rrHeader())), isNull);
    final otherBlock = rrContinuation()..[1] = 3;
    expect(
        () => assembler.add(notification(otherBlock)), throwsFormatException);
    assembler.reset();
    expect(assembler.add(notification(rrHeader(count: 20))), isNull);
    expect(() => assembler.add(notification(rrContinuation())),
        throwsFormatException);
    expect(
        () => RrAssembler().add(notification(rrContinuation().sublist(0, 19))),
        throwsFormatException);
  });
}
