# GBand 2.3.14 wire formats

Scope is Android `com.vpgband.app` build 377 from [APK provenance](apk-provenance.md). These are static findings. Byte offsets are zero based. Tables describe the characteristic value, with no ATT headers. Values written in hex are shown in uppercase. Multi-byte lengths and indices are unsigned unless specified.

## Transport and binding

- `VPBleCenter.startScanDevice` uses Nordic Scanner Compat. `VPOperateManager.connectDevice` delegates to Inuker with 10 s connect and 5 s service discovery timeouts and zero configured retries in that overload. `BleConnectWorker` calls Android LE GATT connect and service discovery.
- The primary health service is `f0080001-0451-4000-b000-000000000000`. The SDK subscribes to `f0080002-0451-4000-b000-000000000000` via `com.veepoo.protocol.j`. Inuker enables local notification delivery and writes CCCD `2902` with the Android notification enable value (`01 00`). `com.veepoo.protocol.r` maps notifications through `lf/b.java`. `com.veepoo.protocol.e.send` uses Inuker `write` to `f0080003-0451-4000-b000-000000000000` and passes the payload unchanged. `BleConnectWorker.writeCharacteristic` leaves the characteristic write type as configured.
- `VPBleCenter.connectDevice$lambda$5` starts the app-level check after successful subscription. `VPOperateManager.confirmDevicePwd` registers response and feature listeners. `p001if/v1.java` constructs the 20-byte `A1` request containing the supplied numeric password, time fields, a signed UTC offset in quarter hours and flags, including optional on-device confirmation. The response parser requires 20 bytes. Offset 3 reports password check success (`01`), failure (`00`) or password and time check success (`06`), among other status codes. Offsets 4–5 are the big-endian model number and 6–9 are the firmware and test version components. Exact firmware policies for bond, reconnect and confirmation remain open. The Dart package has no binding implementation.
- `com.veepoo.protocol.r` treats device number `2501` and test version `00.00.00.00` specially in follow-up after password dispatch. Other branches consult cached update information or trigger a network task. A stock-app capture should record whether the network is available. These branches do not establish raw sensor support.

The `A1` check builder places the low two bytes of the supplied decimal password at offsets 1–2 in LE order and sets offset 3 to zero. Time fields at 4–10 are BE 16-bit year, then month, day, hour, minute and second. Offset 11 is the boolean passed alongside the password, 12 is `01`, 13 is the signed offset in quarter hours and 14 is the confirmation flag in the app's overload. Bytes 15–19 are zero-filled. This documents the observed legitimate bind flow. Credential policy, the meaning of every flag and confirmation on each firmware still require observation.

## Stored PPG on the primary characteristic

| Direction | Value | Interpretation |
| --- | --- | --- |
| Write | `EB 02 mode t0 t1 t2 t3` | Mode `01` or `02`. Start time is signed 32-bit Unix seconds, little endian in Android's conversion. Modes describe collection schedules, not sample frequencies. |
| Notify | `EB 02 00 count ...` | Starts a read and clears previous blocks. Byte 3 supplies the block count via a signed Java byte. Behavior above 127 is open. |
| Notify | `EB 02 mode ...` | Block fragment. Mode is `01` or `02`. See below. |
| Write | `EB 02 04 01` | Sent after the SDK finishes parsing a block, including the last block. Retry and device behavior for other acknowledgment values are unknown. |
| Notify | `EB 02 05 ...` | Read stopped callback. Other bytes are unresolved. |

| Offset | Size | Meaning |
| --- | --- | --- |
| 0–2 | 3 | `EB 02 mode`. |
| 3–4 | 2 | Fragment index, LE. Zero is the header. |
| 5–6 | 2 | Last fragment index, LE. The APK processes the block when a continuation's index equals this value. |
| 7, header only | 1 | Block index. The SDK adds one to a signed byte for its callback. The codec keeps the original octet. |
| 8–11, header only | 4 | Block timestamp, signed 32-bit LE. `TimeData(long)` multiplies by 1,000 and builds a calendar from that epoch value. Clock accuracy and which sample the timestamp represents are open. |
| 12–13, header only | 2 | LE field named CRC. The handler stores it. Polynomial, initial value, coverage and even whether it is active on firmware remain unknown. |
| 14–15, header only | 2 | LE reported count. The handler stores it and does not use it to bound decoding. Exact meaning is open. |
| 16 onward, header only | variable | Ignored by the APK's reassembly path. |
| 7 onward, continuation | variable | Fragment payload. There is no block ID in continuations. |

The APK concatenates continuation tails in arrival order. Its header path returns before completion, so the codec requires at least one continuation. With that buffer, `A0` reads a LE two-byte value retained as `contentLength`. `A1` reads a LE two-byte lane length and its bytes. `A2` reads a LE two-byte lane length and its bytes and emits a record when an `A1` buffer is present. `A0` resets the pending `A1` buffer. The units and coverage of `contentLength` are unresolved. The Dart decoder accepts the explicitly framed `A0 / A1 / A2` sequence and 300-byte lanes, rejecting unknown tags and layouts.

- Green lane `A1` yields 100 slots, each a three-byte unsigned LE value. `80 80 80` is filtered in Android. Dart preserves its slot as null. Sample units and actual sample rate are unknown.
- Accelerometer lane `A2` yields 50 signed 16-bit LE X/Y/Z triples. Absolute units, axis orientation and sample timing are unknown. The lane sizes alone do not establish timing.
- The APK emits a block, sends the acknowledgment, and reports transfer completion when the one-based block index equals the count from the start event. The codec exposes block events and inert acknowledgment bytes. The caller owns the session and must reset at each block boundary. Never mix packets across transfers.

## RR blocks on the primary characteristic

Write 20 bytes `70 day first_lo first_hi` followed by 16 zero bytes. Day selectors `00`, `01` and `02` mean today, yesterday and the day before, according to the SDK enum. The SDK clamps positions below 1 to 1. The Dart builder requires a one-based position in `1..65535`.

| Offset | Size | Meaning |
| --- | --- | --- |
| 0 | 1 | `70` for GBand RR. HBand's generic dispatcher assigns this byte to GPS. |
| 1–2 | 2 | LE block number. Zero exits the SDK handler. Static interpretation is unsupported; no device result distinguishes unsupported from empty. |
| 3–4 | 2 | LE total block count. |
| 5–6 | 2 | Fragment index, then last fragment index, one octet each. |
| 7, header only | 1 | Reported day selector. |
| 8–13, header only | 6 | Device calendar fields year minus 2000, month, day, hour, minute, second. No offset is in this header. |
| 14–15, header only | 2 | LE count used to allocate the Android integer array. The copy loop feeds unsigned octets into it. |
| 16 onward, header only | variable | Initial data octets. |
| 7 onward, continuation | variable | More data octets. Bytes beyond the declared count have unresolved meaning. |

The parser requires at least 20 bytes per fragment. The last fragment triggers progress, then transfer completion if its block number equals the total. No RR acknowledgment or checksum verification is present in this traced handler. The original copy code also checks the packet offset against the destination length, which can leave entries unfilled. Dart instead verifies there are enough source bytes, returns exactly the declared prefix and never manufactures missing data. These octets have no verified scale, beat boundaries or per-beat timestamps. They stay outside the physiological interval model until conversion is supported.

## Raw PPG capability observations

`readPPGTestStatus` writes `EB 01 01 00`. Notifications beginning with `EB 01` use subcode `01` for a read response, `02` for a setting response and `03` for a device report. Byte 3 maps to off (`01`), mode 1 (`02`) or mode 2 (`03`); this decoder does not include a separate unsupported status. A generic PPG setting is independent of this raw-test path. The codecs leave switch reads and state changes to later validation.

## Live PPG on the secondary characteristic

`VPOperateManager.startPPGRealTimeTransmission` initiates a subscription to service `f0020001-0451-4000-b000-000000000000`, characteristic `f0020002-0451-4000-b000-000000000000`, then requests enable on the primary write characteristic using `EB 03 02 02`. Stop unsubscribes and sends `EB 03 02 01`. On the primary notify characteristic, `EB 03 01 02` signals that the wearable requests enable and `EB 03 02 01` is tested as a successful response to the app's request. These are separate from the stored block flow.

| First byte on secondary notify | Callback behavior |
| --- | --- |
| `80` | Starts at offset 1 and advances in steps of 3 with a loop condition of offset < length − 4. DEX uses signed Java byte loads and combines them with shifts of 16 and 8 and bitwise OR. It skips combined value `0x080808`, then passes the result to `z0.a`, which tests bit 19 and applies the APK's masks. This is an exact description of the implementation, with no claim about the physical sample encoding or whether the unmasked signed promotions are intended. |
| `89` | Starts at offset 1 and advances in steps of 6 with the same loop condition. Decodes three signed 16-bit LE components. |

The last four bytes are excluded from the loop's start range. Their meaning and the valid frame sizes, integrity and timing semantics are unknown. There is no decoded timestamp in this callback. The standalone package does not decode this path.

## DEX cross-checks

Regenerate disassembly with Android Build Tools 36.0.0 `dexdump -d classes3.dex` after extracting that DEX from the hashed GBand base. Use descriptors rather than the obfuscated JADX file names for cross-referencing.

| Method in GBand classes3.dex | Observed instruction evidence |
| --- | --- |
| `Lif/r1;->handler([B)V`, code item `0x430f3c` | `00e0` drops seven bytes using Kotlin's array helper. `00f8–00fa` sets little endian. The packed switch at `018b` handles `A0..A2`. `01cd–01d5` passes the second consumed byte as the high operand for `A1`, resolving JADX's misleading inline evaluation order. `01ac` uses the LE buffer for `A2`. `01df–01ed` reads the `A0` LE field. The CRC is assigned to the model and never retrieved by this handler. |
| `Lif/r1;->readPPGRawData`, code item `0x4314d8`; `Lcom/veepoo/protocol/VPOperateManager;->readRRIntervalByDay`, `0x3949b4` | Request construction agrees with the byte layouts above. `H(BB)I` treats its first argument as the high byte. |
| `Lif/w1;->handler([B)V`, code item `0x432cb8` | `0004` enforces the 20-byte minimum. `000f` and `001c` combine block index and total. `0028` converts bytes to unsigned integers. `008d–008f` and `00af` invoke copies using the first/continuation offsets. |
| `Lcom/veepoo/protocol/VPOperateManager$x;->onNotify`, code item `0x38fa98` | `001a–0029` confirms signed loads and OR operations in live green decoding. `004d–007b` confirms the length-minus-four guard and acceleration stride. |
| `Lcom/veepoo/protocol/model/datas/PPGSecondData;`, code items `0x3bca00`, `0x3bca2c`, `0x3bcba0`, `0x3bcc24` | Helpers and loops confirm signed 16-bit acceleration, unsigned 24-bit green and the stored green marker. |

### Live path bytecode review

The GBand base APK hash was rechecked against [APK provenance](apk-provenance.md). The nested live callback `VPOperateManager$x.onNotify` at `0x38fa98` calls `util.a.d([B)` at `0x3e56b4`; the helper builds a hex string and its result is discarded. There is no integrity check at that call site.

For `80` frames, the reference callback combines three Java signed-byte promotions. It never masks the lower two octets before the OR. For example, both synthetic triples `00 00 80` and `7F FF 80` produce the intermediate value −128. The sentinel comparison at `002a–002d` checks `0x00080808`. The conversion at `if.z0.a(I)I` (`0x42b8a4`) tests bit 19 and then either masks with `0x0007FFFF` or ORs with `0xFFF00000`. The separate G08W callback at `0x38f4e4` reuses this conversion. The APK establishes the callback's calculation, but the on-wire bit layout, permitted octet ranges and intended handling of sign and missing values are unresolved.

For `89` frames the axis field conversions are signed 16-bit LE. For both frame types the condition `offset < length - 4` limits sample *start positions*. It does not independently verify a full sample fits before a trailer. For example, an eight-byte `89` value starts a six-byte sample at offset 1 and reads through offset 6. The check alone cannot establish a four-byte trailer. Valid lengths, sample count, trailer semantics, checksum or sequence fields, sample timing and physical units require a capture. The package leaves live PPG and live acceleration decoding unimplemented until the frame boundaries and optical semantics can be established.
