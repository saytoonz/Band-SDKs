/// A missing timestamp is represented by null. Calendar fields deliberately
/// carry no time zone. Unix seconds and host receipt have distinct provenance.
sealed class MeasurementTime {
  const MeasurementTime();
}

final class DeviceUnixTime extends MeasurementTime {
  const DeviceUnixTime(this.seconds);

  final int seconds;
}

final class DeviceCalendarTime extends MeasurementTime {
  const DeviceCalendarTime({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
    this.utcOffset,
  });

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;
  final Duration? utcOffset;
}

final class HostReceiptTime extends MeasurementTime {
  const HostReceiptTime(this.instant);

  final DateTime instant;
}

enum OpticalChannel { green, red, infrared }

enum IntervalKind { pulseToPulse, electrocardiographicRr }

enum AccelerationUnit { metresPerSecondSquared, standardGravity }

enum TemperatureUnit { celsius, fahrenheit, kelvin }

enum SignalQuality { usable, degraded, unusable }

final class MeasurementMetadata {
  const MeasurementMetadata({
    this.time,
    this.quality,
    this.onBody,
    this.hostReceipt,
  });

  final MeasurementTime? time;
  final SignalQuality? quality;
  final bool? onBody;
  final HostReceiptTime? hostReceipt;
}

final class SamplingMetadata {
  const SamplingMetadata({
    this.rateHz,
    this.nominalSampleCount,
    this.channel,
    this.amplitudeUnit,
  });

  final double? rateHz;
  final int? nominalSampleCount;
  final OpticalChannel? channel;
  final String? amplitudeUnit;
}

final class RawPpgMeasurement {
  RawPpgMeasurement({
    required Iterable<num?> samples,
    required this.sampling,
    this.metadata = const MeasurementMetadata(),
  }) : samples = List.unmodifiable(samples);

  /// Null preserves the position of an unavailable sample.
  final List<num?> samples;
  final SamplingMetadata sampling;
  final MeasurementMetadata metadata;
}

final class BeatInterval {
  const BeatInterval({
    required this.duration,
    this.kind,
    this.metadata = const MeasurementMetadata(),
  });

  final Duration duration;
  final IntervalKind? kind;
  final MeasurementMetadata metadata;
}

final class HeartRate {
  const HeartRate(this.beatsPerMinute,
      {this.metadata = const MeasurementMetadata()});

  final num beatsPerMinute;
  final MeasurementMetadata metadata;
}

final class OxygenSaturation {
  const OxygenSaturation(this.percent,
      {this.metadata = const MeasurementMetadata()});

  final num percent;
  final MeasurementMetadata metadata;
}

final class SkinTemperature {
  const SkinTemperature(this.value,
      {this.unit, this.site, this.metadata = const MeasurementMetadata()});

  final num value;
  final TemperatureUnit? unit;
  final String? site;
  final MeasurementMetadata metadata;
}

final class AccelerometerSample {
  const AccelerometerSample(this.x, this.y, this.z,
      {this.unit, this.metadata = const MeasurementMetadata()});

  final num x;
  final num y;
  final num z;
  final AccelerationUnit? unit;
  final MeasurementMetadata metadata;
}
