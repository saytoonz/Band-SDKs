# ThrivnMe wearable protocol

A standalone Dart package with no runtime dependencies. It provides immutable GATT value packets, GBand 2.3.14 stored PPG and RR history codecs, and manufacturer-independent measurement models. See the repository [wire inventory](../../docs/gband-wire.md) for source and bytecode evidence.

Run `dart pub get`, `dart analyze` and `dart test` from this directory.

## Receiving a block

Feed complete characteristic values with their UUID and direction. Scope one assembler to one operation and reset between blocks or after a failed transfer. Missing fragments leave the operation pending. Byte-identical repeats are ignored, inconsistent repeats are rejected, and fragments within one block can arrive out of order. PPG continuations lack a block identifier. The caller must isolate transfers and provide the block boundary. The request and acknowledgment builders return packets for inspection or replay and perform no I/O.

Structural checks cover routing, headers, fragment sequence bounds, consistent block identifiers and simultaneous metadata, payload lengths and the known PPG record shape. The APK provides no verified integrity algorithm for either codec. The stored CRC value is preserved without a validity claim. RR data comes back as unsigned octets. The assembly stops at the declared count, without interpreting surplus bytes or converting octets into physiological intervals.

## Physiological data contract

The domain models support raw PPG, pulse-to-pulse and ECG-derived RR intervals, heart rate in beats per minute, oxygen saturation in percent, skin temperature with optional scale/site and three-axis acceleration with optional units. Sample rate, amplitude unit, measurement time, receipt time, quality and wear state can be unknown. Device epoch time, unzoned device calendar time and host receipt time use different types. Preserve block time at block scope until a sample-level timestamp can be established. A null PPG sample preserves an absent slot independently of any quality assessment.

RR block octets remain in the codec result. Build a `BeatInterval` only after decoding a duration. This avoids presenting an unsigned wire octet as milliseconds or attaching a block timestamp to every beat.

## Synthetic fixtures

All values in [the tests](test/codec_test.dart) were constructed offline. They demonstrate packet handling using generated input.

- Stored PPG has a header with timestamp `0x12345678`, raw index 3 and arbitrary CRC field `0xBEEF`. Two continuations split one `A0/A1/A2` record across a green sample. The green lane starts with an unsigned high-bit sample and the missing marker. The motion lane starts with −1, −32768 and 32767. The remaining slots use zeros. Tests reverse arrival order, repeat fragments, truncate a header and truncate a record.
- RR uses block 2 of 5 and a clock with no time zone. Two fragments carry seven declared unsigned octets plus synthetic surplus zeros. Tests cover reverse order, duplicate fragments, conflicting duplicates, different block IDs, insufficient payload and the zero-block code.
- Command tests cover byte order, fixed lengths, the stored PPG block acknowledgment, and range validation for the RR cursor.

## Offline transcript replay

The [stored PPG transcript tests](test/transcript_test.dart) replay labelled connections, GATT writes and notifications through the real assembler. On reconnect, the fixture starts a fresh read, drops pending fragments from the old connection and ignores its late notifications. Replay also checks for the expected acknowledgment after a completed block while the connection is open. The harness lives in test support and performs no BLE I/O. To add a device fixture, preserve packet order, connection boundaries and characteristic UUIDs, replace identifying bytes where safe, and record the wearable model, firmware and APK hash.
