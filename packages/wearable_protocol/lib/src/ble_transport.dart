/// A scan result. The service list may be absent or incomplete.
final class BleAdvertisement {
  BleAdvertisement({
    required this.deviceId,
    this.localName,
    this.rssi,
    Iterable<String> services = const [],
    Map<int, List<int>> manufacturerData = const {},
    Map<String, List<int>> serviceData = const {},
  })  : services = Set.unmodifiable(services.map((uuid) => uuid.toLowerCase())),
        manufacturerData = Map.unmodifiable(
          manufacturerData
              .map((id, value) => MapEntry(id, List<int>.unmodifiable(value))),
        ),
        serviceData = Map.unmodifiable(
          serviceData.map((uuid, value) =>
              MapEntry(uuid.toLowerCase(), List<int>.unmodifiable(value))),
        );

  final String deviceId;
  final String? localName;
  final int? rssi;
  final Set<String> services;
  final Map<int, List<int>> manufacturerData;
  final Map<String, List<int>> serviceData;
}

enum BleConnectionState { connecting, connected, disconnected }

enum BleWriteMode { withResponse, withoutResponse }

final class BleCharacteristic {
  BleCharacteristic({
    required String uuid,
    this.canNotify = false,
    this.canWriteWithResponse = false,
    this.canWriteWithoutResponse = false,
  }) : uuid = uuid.toLowerCase();

  final String uuid;
  final bool canNotify;
  final bool canWriteWithResponse;
  final bool canWriteWithoutResponse;
}

final class BleService {
  BleService(
      {required String uuid,
      required Iterable<BleCharacteristic> characteristics})
      : uuid = uuid.toLowerCase(),
        characteristics = List.unmodifiable(characteristics);

  final String uuid;
  final List<BleCharacteristic> characteristics;
}

/// Each scan subscription owns a scan that ends upon cancellation.
abstract interface class BleTransport {
  Stream<BleAdvertisement> scan();

  /// Returns a new link immediately, including while connection is pending.
  BleLink connect(String deviceId);
}

abstract interface class BleLink {
  Future<void> get ready;

  /// Emits link-local state changes and closes when the link ends.
  Stream<BleConnectionState> get states;

  Future<List<BleService>> discoverServices();

  /// The caller listens to values immediately and awaits remote CCCD setup.
  BleNotifications subscribe(BleCharacteristic characteristic);

  /// Completes on transport success or throws on failure. A write completion
  /// is distinct from an application-level reply from the wearable.
  Future<void> write(
      BleCharacteristic characteristic, List<int> value, BleWriteMode mode);

  /// Idempotent. Releases all resources on this link, including pending work.
  Future<void> close();
}

abstract interface class BleNotifications {
  Future<void> get ready;

  /// One complete characteristic value per event, scoped to this subscription.
  Stream<List<int>> get values;

  /// Idempotent. Cancels pending setup or disables the subscription.
  Future<void> close();
}
