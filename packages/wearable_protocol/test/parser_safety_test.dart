import 'package:test/test.dart';
import 'package:thrivnme_wearable_protocol/wearable_protocol.dart';

import 'support/synthetic_packets.dart';

void main() {
  test('PPG carries signed 32-bit block timestamps', () {
    final assembler = StoredPpgAssembler();
    final record = ppgRecord();
    final header = ppgHeader(2)..setRange(8, 12, [0, 0, 0, 0x80]);
    expect(assembler.add(notification(header)), isNull);
    expect(
        assembler.add(notification(ppgFragment(1, 2, record.sublist(0, 301)))),
        isNull);
    final result =
        assembler.add(notification(ppgFragment(2, 2, record.sublist(301))))
            as StoredPpgBlock;
    expect(result.time.seconds, -0x80000000);
  });

  test('PPG bounds fragment counts and cumulative retained packet bytes', () {
    final assembler = StoredPpgAssembler();
    final oversizedHeader = ppgHeader(0)..[6] = 16;
    expect(() => assembler.add(notification(oversizedHeader)),
        throwsFormatException);
    assembler.reset();

    final header = ppgHeader(0)..[6] = 9;
    expect(assembler.add(notification(header)), isNull);
    final payload = List.filled(505, 0);
    BlePacket fragment(int index) =>
        notification([0xeb, 2, 1, index & 255, index >> 8, 0, 9, ...payload]);
    for (var index = 1; index < 2048; index++) {
      expect(assembler.add(fragment(index)), isNull);
    }
    expect(() => assembler.add(fragment(2048)), throwsFormatException);
    assembler.reset();
    expect(assembler.add(notification(ppgHeader(2))), isNull);
  });

  test('RR accepts leap day and rejects invalid Gregorian calendar fields', () {
    final assembler = RrAssembler();
    final leapDay = rrHeader()..setRange(8, 11, [24, 2, 29]);
    expect(assembler.add(notification(leapDay)), isNull);
    final result = assembler.add(notification(rrContinuation())) as RrBlock;
    expect([
      result.time.year,
      result.time.month,
      result.time.day,
      result.time.utcOffset
    ], [
      2024,
      2,
      29,
      null
    ]);

    for (final fields in [
      [100, 2, 29, 13, 14, 15],
      [26, 0, 20, 13, 14, 15],
      [26, 11, 0, 13, 14, 15],
      [26, 11, 20, 24, 14, 15],
      [26, 11, 20, 13, 60, 15],
      [26, 11, 20, 13, 14, 60],
    ]) {
      assembler.reset();
      expect(assembler.add(notification(rrHeader()..setRange(8, 14, fields))),
          isNull);
      expect(() => assembler.add(notification(rrContinuation())),
          throwsFormatException);
    }
  });
}
