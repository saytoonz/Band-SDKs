import 'ble_packet.dart';
import 'measurements.dart';

const _suffix = '-0451-4000-b000-000000000000';
const gBandNotify = 'f0080002$_suffix';
const gBandWrite = 'f0080003$_suffix';
const gBandLivePpgNotify = 'f0020002$_suffix';

enum StoredPpgMode {
  mode1(1),
  mode2(2);

  const StoredPpgMode(this.code);
  final int code;
}

enum HistoryDay { today, yesterday, beforeYesterday }

/// Builders return inert values. The caller owns transport and authorization.
BlePacket storedPpgRead(StoredPpgMode mode, DeviceUnixTime start) {
  RangeError.checkValueInInterval(start.seconds, -0x80000000, 0x7fffffff);
  return _command([0xeb, 2, mode.code, ..._littleEndian(start.seconds, 4)]);
}

BlePacket storedPpgBlockAcknowledgment() => _command([0xeb, 2, 4, 1]);

BlePacket rrHistoryRead(HistoryDay day, int firstBlock) {
  RangeError.checkValueInInterval(firstBlock, 1, 0xffff);
  return _command([
    0x70,
    day.index,
    ..._littleEndian(firstBlock, 2),
    ...List.filled(16, 0)
  ]);
}

BlePacket _command(List<int> bytes) => BlePacket(
    characteristic: gBandWrite, kind: BlePacketKind.write, bytes: bytes);

Iterable<int> _littleEndian(int value, int width) =>
    List.generate(width, (offset) => (value >> (offset * 8)) & 255);

int _u16(List<int> bytes, int i) => bytes[i] | bytes[i + 1] << 8;

int _signed(int value, int width) =>
    value >= (1 << (width - 1)) ? value - (1 << width) : value;

List<int> _notification(BlePacket packet, int opcode, int minLength) {
  final bytes = packet.bytes;
  if (packet.kind != BlePacketKind.notification ||
      packet.characteristic != gBandNotify ||
      bytes.length < minLength ||
      bytes[0] != opcode) {
    throw const FormatException('Unexpected characteristic, opcode or length');
  }
  return bytes;
}

final class _FragmentSet {
  final _fragments = <int, List<int>>{};
  int? _last;
  int _bufferedBytes = 0;

  bool add(int index, int last, List<int> bytes) {
    if (index > last || (_last != null && _last != last)) {
      throw const FormatException('Inconsistent fragment indices');
    }
    final previous = _fragments[index];
    if (previous != null) {
      if (previous.length != bytes.length ||
          Iterable<int>.generate(bytes.length)
              .any((i) => previous[i] != bytes[i])) {
        throw const FormatException('Conflicting duplicate fragment');
      }
      return false;
    }
    // Local resource ceilings, independent of the wearable's fragment fields.
    if (last >= 4096 || _bufferedBytes + bytes.length > 1024 * 1024) {
      throw const FormatException('Block exceeds decoder resource limits');
    }
    _last = last;
    _bufferedBytes += bytes.length;
    _fragments[index] = bytes;
    return _fragments.length == last + 1;
  }

  List<int> operator [](int index) => _fragments[index]!;
  int get last => _last!;

  void clear() {
    _last = null;
    _bufferedBytes = 0;
    _fragments.clear();
  }
}

final class StoredPpgRecord {
  StoredPpgRecord._(
      this.declaredLength, this.ppg, List<AccelerometerSample> acceleration)
      : acceleration = List.unmodifiable(acceleration);

  final int declaredLength;
  final RawPpgMeasurement ppg;
  final List<AccelerometerSample> acceleration;
}

sealed class StoredPpgEvent {
  const StoredPpgEvent();
}

final class StoredPpgStarted extends StoredPpgEvent {
  const StoredPpgStarted(this.blockCount);
  final int blockCount;
}

final class StoredPpgStopped extends StoredPpgEvent {
  const StoredPpgStopped();
}

final class StoredPpgBlock extends StoredPpgEvent {
  StoredPpgBlock._({
    required this.wireIndex,
    required this.mode,
    required this.time,
    required this.reportedCrc,
    required this.reportedCount,
    required List<StoredPpgRecord> records,
  }) : records = List.unmodifiable(records);

  final int wireIndex;
  final StoredPpgMode mode;
  final DeviceUnixTime time;

  /// The inspected APK records this field without validating it.
  final int reportedCrc;
  final int reportedCount;
  final List<StoredPpgRecord> records;
}

/// One in-flight block. Continuations have no block ID. The caller must
/// isolate notifications by transfer and reset at each block boundary.
final class StoredPpgAssembler {
  final _fragments = _FragmentSet();
  int? _mode;
  bool _failed = false;

  void reset() {
    _fragments.clear();
    _mode = null;
    _failed = false;
  }

  /// Returns null for an incomplete block or a byte-identical duplicate.
  StoredPpgEvent? add(BlePacket packet) {
    final bytes = _notification(packet, 0xeb, 3);
    if (bytes[1] != 2) throw const FormatException('Expected EB history');
    final code = bytes[2];
    if (code == 0 || code == 5) {
      if (code == 0 && bytes.length < 4) {
        throw const FormatException('Missing PPG block count');
      }
      reset();
      return code == 0 ? StoredPpgStarted(bytes[3]) : const StoredPpgStopped();
    }
    if (_failed) throw StateError('Reset the failed PPG block before reuse');
    try {
      if (code < 1 ||
          code > 2 ||
          bytes.length < 7 ||
          (_mode != null && code != _mode)) {
        throw const FormatException('Invalid PPG mode or header');
      }
      final index = _u16(bytes, 3);
      final last = _u16(bytes, 5);
      if (index == 0 && (bytes.length < 16 || last == 0)) {
        throw const FormatException('Invalid PPG block header');
      }
      if (index != 0 && bytes.length == 7) {
        throw const FormatException('Empty PPG continuation');
      }
      final complete = _fragments.add(index, last, bytes);
      _mode = code;
      if (!complete) return null;
      final header = _fragments[0];
      final payload = <int>[
        for (var i = 1; i <= _fragments.last; i++) ..._fragments[i].skip(7),
      ];
      final seconds = _u16(header, 8) | _u16(header, 10) << 16;
      return StoredPpgBlock._(
        wireIndex: header[7],
        mode: StoredPpgMode.values[code - 1],
        time: DeviceUnixTime(_signed(seconds, 32)),
        reportedCrc: _u16(header, 12),
        reportedCount: _u16(header, 14),
        records: _decodePpgRecords(payload),
      );
    } on FormatException {
      reset();
      _failed = true;
      rethrow;
    }
  }
}

List<StoredPpgRecord> _decodePpgRecords(List<int> bytes) {
  var offset = 0;
  void expectTag(int tag) {
    if (offset + 3 > bytes.length || bytes[offset] != tag) {
      throw const FormatException('Truncated or unsupported PPG record tag');
    }
    offset++;
  }

  List<int> readLane(int tag) {
    expectTag(tag);
    final length = _u16(bytes, offset);
    offset += 2;
    if (length != 300 || offset + length > bytes.length) {
      throw const FormatException('Unsupported or truncated PPG lane');
    }
    final lane = bytes.sublist(offset, offset + length);
    offset += length;
    return lane;
  }

  final records = <StoredPpgRecord>[];
  while (offset < bytes.length) {
    expectTag(0xa0);
    final declaredLength = _u16(bytes, offset);
    offset += 2;
    final green = readLane(0xa1);
    final acceleration = readLane(0xa2);
    records.add(StoredPpgRecord._(
      declaredLength,
      RawPpgMeasurement(
        samples: [
          for (var i = 0; i < green.length; i += 3) _greenSample(green, i),
        ],
        sampling: const SamplingMetadata(
          nominalSampleCount: 100,
          channel: OpticalChannel.green,
        ),
      ),
      [
        for (var i = 0; i < acceleration.length; i += 6)
          AccelerometerSample(
            _signed(_u16(acceleration, i), 16),
            _signed(_u16(acceleration, i + 2), 16),
            _signed(_u16(acceleration, i + 4), 16),
          ),
      ],
    ));
  }
  return records;
}

int? _greenSample(List<int> bytes, int offset) {
  final value = _u16(bytes, offset) | bytes[offset + 2] << 16;
  return value == 0x808080 ? null : value;
}

sealed class RrHistoryEvent {
  const RrHistoryEvent();
}

/// The APK exits on this marker. Firmware may distinguish empty and unsupported.
final class RrZeroBlockResponse extends RrHistoryEvent {
  const RrZeroBlockResponse();
}

final class RrBlock extends RrHistoryEvent {
  RrBlock._(
      this.index, this.totalBlocks, this.daySelector, this.time, List<int> data)
      : data = List.unmodifiable(data);

  final int index;
  final int totalBlocks;
  final int daySelector;
  final DeviceCalendarTime time;

  /// Preserved unsigned octets. Individual intervals and units are unknown.
  final List<int> data;
}

/// One indexed RR block. Reset between blocks and after malformed input.
final class RrAssembler {
  final _fragments = _FragmentSet();
  int? _index;
  int? _total;
  bool _failed = false;

  void reset() {
    _fragments.clear();
    _index = null;
    _total = null;
    _failed = false;
  }

  RrHistoryEvent? add(BlePacket packet) {
    final bytes = _notification(packet, 0x70, 20);
    if (_failed) throw StateError('Reset the failed RR block before reuse');
    final index = _u16(bytes, 1);
    if (index == 0) {
      reset();
      return const RrZeroBlockResponse();
    }
    try {
      final total = _u16(bytes, 3);
      if (index > total ||
          (_index != null && (_index != index || _total != total))) {
        throw const FormatException('Inconsistent RR block indices');
      }
      final complete = _fragments.add(bytes[5], bytes[6], bytes);
      _index = index;
      _total = total;
      if (!complete) return null;
      final header = _fragments[0];
      final count = _u16(header, 14);
      final time = _rrCalendar(header);
      final data = _rrOctets(header, _fragments).take(count).toList();
      if (data.length < count) throw const FormatException('Truncated RR data');
      return RrBlock._(
        index,
        total,
        header[7],
        time,
        data,
      );
    } on FormatException {
      reset();
      _failed = true;
      rethrow;
    }
  }
}

Iterable<int> _rrOctets(List<int> header, _FragmentSet fragments) sync* {
  yield* header.skip(16);
  for (var i = 1; i <= fragments.last; i++) {
    yield* fragments[i].skip(7);
  }
}

DeviceCalendarTime _rrCalendar(List<int> header) {
  final year = 2000 + header[8];
  final month = header[9];
  final day = header[10];
  final hour = header[11];
  final minute = header[12];
  final second = header[13];
  final date = DateTime.utc(year, month, day, hour, minute, second);
  if (date.year != year ||
      date.month != month ||
      date.day != day ||
      date.hour != hour ||
      date.minute != minute ||
      date.second != second) {
    throw const FormatException('Invalid RR device calendar fields');
  }
  // UTC is only used for calendar validation, not as a device time zone.
  return DeviceCalendarTime(
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute,
    second: second,
  );
}
