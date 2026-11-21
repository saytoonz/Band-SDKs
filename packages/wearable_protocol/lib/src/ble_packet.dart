import 'measurements.dart';

enum BlePacketKind { notification, write }

/// One characteristic value. Pass the GATT payload without ATT headers.
final class BlePacket {
  BlePacket({
    required String characteristic,
    required this.kind,
    required Iterable<int> bytes,
    this.hostReceiptTime,
  })  : characteristic = characteristic.toLowerCase(),
        bytes = List.unmodifiable(bytes.take(513)) {
    if (this.bytes.length > 512 ||
        this.bytes.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Invalid GATT characteristic value');
    }
  }

  final String characteristic;
  final BlePacketKind kind;
  final List<int> bytes;
  final HostReceiptTime? hostReceiptTime;
}
