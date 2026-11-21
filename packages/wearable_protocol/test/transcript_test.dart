import 'package:test/test.dart';
import 'package:thrivnme_wearable_protocol/wearable_protocol.dart';

import 'support/synthetic_packets.dart';
import 'support/transcript.dart';

void main() {
  const mode = StoredPpgMode.mode1;
  const start = DeviceUnixTime(0x12345678);
  final request = storedPpgRead(mode, start);
  final data = ppgRecord();
  final first = notification(ppgFragment(1, 2, data.sublist(0, 301)));
  final last = notification(ppgFragment(2, 2, data.sublist(301)));
  final stale = notification(ppgFragment(2, 2, [0xff]));
  final ack = BlePacket(
    characteristic: gBandWrite,
    kind: BlePacketKind.write,
    bytes: const [0xeb, 2, 4, 1],
  );

  test('reconnect drops an incomplete block and ignores late notifications',
      () {
    final blocks = replayStoredPpg([
      const ReplayConnect('first'),
      ReplayWrite('first', request),
      ReplayNotification('first', notification(ppgHeader(2))),
      ReplayNotification('first', first),
      const ReplayDisconnect('first'),
      const ReplayConnect('second'),
      ReplayWrite('second', request),
      ReplayNotification('second', notification(ppgHeader(2))),
      ReplayNotification('first', stale),
      ReplayNotification('second', last),
      ReplayNotification('second', first),
      ReplayWrite('second', ack),
      const ReplayDisconnect('second'),
    ], mode: mode, start: start);
    expect(blocks, hasLength(1));
    expect(blocks.single.records.single.ppg.samples.first, 0xf23456);
  });

  test('a completed block requires the recorded acknowledgment', () {
    expect(
      () => replayStoredPpg([
        const ReplayConnect('first'),
        ReplayWrite('first', request),
        ReplayNotification('first', notification(ppgHeader(2))),
        ReplayNotification('first', first),
        ReplayNotification('first', last),
      ], mode: mode, start: start),
      throwsA(isA<TestFailure>()),
    );
  });
}
