import 'package:thrivnme_wearable_protocol/wearable_protocol.dart';

BlePacket notification(List<int> bytes,
        {String characteristic = gBandNotify}) =>
    BlePacket(
        characteristic: characteristic,
        kind: BlePacketKind.notification,
        bytes: bytes);

List<int> ppgHeader(int last) => [
      0xeb,
      2,
      1,
      0,
      0,
      last,
      0,
      3,
      0x78,
      0x56,
      0x34,
      0x12,
      0xef,
      0xbe,
      1,
      0,
    ];

List<int> ppgFragment(int index, int last, List<int> data) =>
    [0xeb, 2, 1, index, 0, last, 0, ...data];

List<int> ppgRecord() => [
      0xa0,
      0x58,
      0x02,
      0xa1,
      0x2c,
      0x01,
      0x56,
      0x34,
      0xf2,
      0x80,
      0x80,
      0x80,
      ...List.filled(294, 0),
      0xa2,
      0x2c,
      0x01,
      0xff,
      0xff,
      0x00,
      0x80,
      0xff,
      0x7f,
      ...List.filled(294, 0),
    ];

List<int> rrHeader({int count = 7}) => [
      0x70,
      2,
      0,
      5,
      0,
      0,
      1,
      1,
      26,
      11,
      20,
      13,
      14,
      15,
      count,
      0,
      0xff,
      0x80,
      0x40,
      1
    ];

List<int> rrContinuation() =>
    [0x70, 2, 0, 5, 0, 1, 1, 2, 3, 4, ...List.filled(10, 0)];
