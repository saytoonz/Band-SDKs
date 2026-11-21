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

## Stored PPG transfer manager

Subscribe to `StoredPpgTransfer.events` before calling `start`. Create a new `StoredPpgConnection` with `openConnection` after the transport has established an authorized connection and subscribed to the primary characteristic. Capture that token in the notification and disconnect callbacks for that link. Use a fresh link for each transfer so delayed frames from an interrupted read cannot be attributed to a later read on the same link.

Dispatch a `StoredPpgWrite` only while `isPending(write)` is true. Report success or failure using `writeResult` with the same event object. A successful result means the transport reported its write complete. It carries no independent confirmation from the wearable. The manager emits progress after each block acknowledgment write result and reports completion after the final one. Consumers can persist progress blocks as they arrive. The manager retains only the current block and a bounded queue of notifications arriving before its write result. Call `disconnect` when the link closes and `dispose` when the manager is no longer needed.

The session manager treats a zero count as an empty result and restricts nonzero counts to the positive signed-byte range read by the APK. It expects contiguous zero-based block indices and a header before continuations. Within an identified block, continuations can arrive out of order. An old connection token is ignored, and continuations received between blocks before a new header are discarded. A delayed continuation arriving after a new header has no wire identifier to distinguish it from the current block.

The configurable defaults are 10 seconds per outstanding write and 30 seconds to receive the initial count or complete a block. Duplicate and partial notifications do not extend a deadline. Cancellation is local and discards pending state and write receipts. Device stop, malformed data, a failed write and timeouts each produce an explicit terminal event. The manager generates no automatic retry, resume or cancellation command.

## Parser limits

Characteristic values are bounded at 512 bytes. The codec caps each block at 4,096 fragments and 1 MiB of retained wire bytes, and the transfer manager buffers at most 256 notifications while a write result is pending. These are local resource controls. The limits do not describe a wearable's supported sizes. RR assembly copies at most the declared octet count and rejects impossible calendar dates and clock fields. Date validation leaves the device UTC offset unknown. PPG Unix seconds retain signed 32-bit semantics. Truncated frames and excessive resources fail without manufacturing samples.
