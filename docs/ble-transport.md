# Independent BLE transport and GBand adapter

The Dart package implements the GBand stored PPG connection flow above a transport interface. The package has no runtime dependencies. Protocol-specific data comes out as the existing PPG block and measurement types, so future adapters can use the same physiological models.

| Layer | Interfaces and ownership |
| --- | --- |
| Transport | `BleTransport` starts a cancellable scan and opens a connection handle. `BleAdvertisement` carries the device ID, local name, RSSI, service UUIDs, manufacturer data and service data when available. |
| Connection | `BleLink` owns readiness, link-state events, GATT discovery, writes and close. A link is returned immediately so the caller can cancel while the connection is pending. |
| Notification | `BleNotifications` owns one characteristic subscription. Its readiness future completes after notification setup, separately from its stream of characteristic values. |
| GBand adapter | `GBandCoordinator` manages scanning and one link at a time. A `GBandSession` identifies that link and owns its authorization scope, serial write queue and one stored PPG read. |
| Binding | `GBandAuthorizer` receives a scoped `GBandBindingChannel`. The implementation supplies the user's authorized binding procedure and reports success only after verifying the device reply. |
| Protocol | `StoredPpgTransfer` handles request and acknowledgment bytes, block ordering and deadlines. It emits decoded blocks after the acknowledgment write reports success. |

## Connection and command flow

1. Listen to `discover()` or use a known device ID. The scan exposes advertisements even if the Veepoo service is absent from the advertisement. A candidate is validated by GATT discovery after connection.
2. Call `connect(deviceId)`. The coordinator watches disconnect events and waits for readiness. It checks for exactly one Veepoo `f0080001` service, one notifiable `f0080002` and one `f0080003` with write-with-response support. The requirement for write-with-response is a conservative adapter choice. The APK uses Inuker's ordinary write path and leaves the characteristic write type configured by the Android stack. The advertised service and GATT UUIDs establish no particular firmware feature support.
3. Subscribe to the notify characteristic and await setup before invoking the authorizer. The authorizer receives only notification packets from that characteristic and serialized writes to the documented command characteristic. Its write scope closes when authorization ends. A binding timeout, rejection or transport write failure closes the link.
4. Listen to `readStoredPpg(mode, from)` on the authorized session. The adapter routes values from that link to its own transfer token, dispatches only pending writes and reports transport results back to the transfer manager. A successful GATT write result is distinct from another wearable reply. Completion closes the stream. Terminal failures surface as stream errors.
5. Await `session.closed` before opening the next link. A read completes with link cleanup because stored PPG continuations lack a transfer ID. Cancelling its subscription also closes the link. Use `coordinator.disconnect()` to stop a pending setup or active link, and `dispose()` to stop scans and release coordinator resources. Session cleanup failures are observable on `cleanupErrors`.

`GBandTimeouts` configures the scan window and the connect, discovery, subscription, authorization, write, receive and cleanup deadlines. Driver implementations must scope callbacks to the original link or subscription and make close idempotent and safe during pending setup or writes. Their close implementation must initiate release even when a timed-out operation is pending. The coordinator invalidates the session before cleanup begins and bounds its cleanup wait. It emits no retry or resume commands.

## Authentication boundary

The [APK trace](gband-wire.md#transport-and-binding) describes the application-level `A1` exchange and optional device confirmation that follows subscription. The package requires an explicit authorizer and provides no default implementation or credentials. A physical implementation must use the user's legitimate binding input, await the response and fail closed when the device rejects the request or requires confirmation. Do not log credentials in traces. An authorized session grants access to the stored PPG flow only through the adapter's verified GATT path.

## Synthetic peripheral

The [test peripheral](../packages/wearable_protocol/test/support/synthetic_peripheral.dart) supplies a scripted advertisement, GATT capabilities, notification setup and stored PPG reads built from the existing generated fixtures. It advances blocks on acknowledgment writes. It supports deterministic gates for connection, subscription, delivery and write results, and injections for dropped fragments, duplicates, malformed notifications, failed writes and disconnections. Tests inject a test-only authorizer. The peripheral implements no binding behavior. A scripted response to a write establishes only the behavior of this simulator.

From the Dart package directory:

```sh
dart pub get
dart analyze
dart test
dart test test/gband_connection_test.dart
```

## Scope and future physical-device setup

- The [wire inventory](gband-wire.md) records statically observed GBand behavior. Integration tests exercise the Dart coordinator and synthetic driver. Physical verification is unavailable.
- The coordinator exposes stored PPG only. RR remains available as a standalone history codec. Live PPG, HR, SpO₂, temperature, platform drivers and real-device binding are outside this adapter's current coverage. Stored PPG CRC, optical units, sample timing and firmware-dependent ordering remain unverified.
- On compatible hardware, implement `BleTransport`, `BleLink` and `BleNotifications` around the chosen platform BLE API. Map characteristic handles to discovery results, return link-scoped state and notification streams, await actual CCCD completion and use the native write result. Configure OS Bluetooth permissions and validate cancellation on that platform.
- Verify the device's model, firmware, service, characteristic properties and normal user-authorized binding before trying stored PPG. Compare a sanitized vendor-app or vendor-provided trace with the session flow, including setup, result ordering, late notifications, reconnect and final acknowledgment. Run the same integration cases against recordings before attempting sustained live collection. [Hardware shortlist and capture plan](device-compatibility.md)
