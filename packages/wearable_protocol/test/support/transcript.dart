import 'package:test/test.dart';
import 'package:thrivnme_wearable_protocol/wearable_protocol.dart';

sealed class ReplayStep {
  const ReplayStep(this.connection);
  final String connection;
}

final class ReplayConnect extends ReplayStep {
  const ReplayConnect(super.connection);
}

final class ReplayDisconnect extends ReplayStep {
  const ReplayDisconnect(super.connection);
}

final class ReplayWrite extends ReplayStep {
  const ReplayWrite(super.connection, this.packet);
  final BlePacket packet;
}

final class ReplayNotification extends ReplayStep {
  const ReplayNotification(super.connection, this.packet);
  final BlePacket packet;
}

/// Checks a single stored PPG read per connection in an offline transcript.
/// Each reconnect uses a new label. Late packets from older connections are
/// ignored. A complete block must be followed by the observed SDK write.
List<StoredPpgBlock> replayStoredPpg(
  Iterable<ReplayStep> transcript, {
  required StoredPpgMode mode,
  required DeviceUnixTime start,
}) {
  final request = storedPpgRead(mode, start);
  final assembler = StoredPpgAssembler();
  final blocks = <StoredPpgBlock>[];
  final seenConnections = <String>{};
  String? activeConnection;
  BlePacket? expectedWrite;

  for (final step in transcript) {
    if (step is ReplayConnect) {
      expect(activeConnection, isNull, reason: 'Connection already open');
      expect(seenConnections.add(step.connection), isTrue,
          reason: 'Use a fresh label for each connection');
      activeConnection = step.connection;
      expectedWrite = request;
      assembler.reset();
      continue;
    }
    if (step is ReplayNotification && step.connection != activeConnection) {
      expect(seenConnections, contains(step.connection));
      continue;
    }
    expect(step.connection, activeConnection, reason: 'Wrong connection');
    switch (step) {
      case ReplayConnect():
        throw StateError('Connect step already handled');
      case ReplayDisconnect():
        activeConnection = null;
        expectedWrite = null;
        assembler.reset();
      case ReplayWrite(:final packet):
        final expected = expectedWrite;
        expect(expected, isNotNull, reason: 'Unexpected write');
        expect(packet.kind, expected!.kind);
        expect(packet.characteristic, expected.characteristic);
        expect(packet.bytes, expected.bytes);
        if (!identical(expected, request)) assembler.reset();
        expectedWrite = null;
      case ReplayNotification(:final packet):
        expect(expectedWrite, isNull, reason: 'Expected write before notify');
        final result = assembler.add(packet);
        if (result is StoredPpgBlock) {
          blocks.add(result);
          expectedWrite = storedPpgBlockAcknowledgment();
        }
    }
  }
  expect(expectedWrite, isNull,
      reason: 'Transcript ends before expected write');
  return List.unmodifiable(blocks);
}
