# Technical findings and protocol inventory

The inspected builds are **HBand `com.veepoo.hband` 11.0.50 (11050)** and **GBand `com.vpgband.app` 2.3.14 (377)**. See [APK provenance](apk-provenance.md) for sample hashes, signers, full manifest permissions and native library inventories.

**Evidence levels.** Static trace means a method body, call site or dispatcher shows the behavior in the APK. Static lead means a parser, API or symbol exists but routing, field semantics or feature reachability still need confirmation. Open means the inspected evidence does not resolve the question. Runtime verified requires a reproducible observation on identified firmware. This report has no runtime-verified entries.

## HBand 11.0.50

Source references below are relative to the JADX package `com.veepoo.hband`. The primary path uses Android GATT and Nordic Scanner Compat. The APK also contains Nordic DFU, Goodix BLE, Jieli OTA/RCSP and Bluetrum FOTA. The native split includes Jieli auth and OTA auth libraries. Their presence alone does not put them on the primary health-channel authentication path.

| Stage | Static evidence | Remaining uncertainty |
| --- | --- | --- |
| Discovery | `activity.desingguide.GuideScanListActivity` uses Nordic Scanner Compat and calls `util.VpBLEDeviceScanRecordManager.filterDevice` on advertisement bytes. Its click handler sends selected name/address through `LocalBroadcastSender.sendConnectActionByManual`. The filter has Veepoo marker and brand-specific branches. `ble.BluetoothService.startScan` also has a reconnect scan path. | Exact supported advertisement variants per model. |
| Connect | `ble.BluetoothService` uses `connectGatt(context, false, callback, 2)` and discovers services. `onServicesDiscovered` identifies the Veepoo protocol service and prepares its notification characteristic. | Negotiated MTU, retry timing and optional characteristics per firmware. |
| Subscribe | `BluetoothService.bleNotify` enables characteristic notifications and writes the client configuration descriptor `2902`. `onCharacteristicChanged` passes UUID and bytes to `ble.BleProfileUtil.getAction` for dispatch. | Which optional subscriptions appear on each supported watch. |
| Bind/authenticate | The descriptor setup flow calls `sendPasswordCheckCmd` on the application GATT channel. `optionDevicePwd` uses `PwdHandler.getReturnData` to gate the connected/settings flow. `ble.bluetooth3.Bluetooth3Manager` has a separate Classic Bluetooth bonding path. | Whether particular LE firmware requires an OS bond and what initial bind/rebind looks like at runtime. |
| History | `ble.readmanager.OriginalHander` and `OriginalDFHander` write day and position-oriented reads on the primary channel. `Spo2hOriginalHander`, `TemptureOriginalHander` and `HRVHandler` implement separate reads. Oxygen and temperature handlers update their own read positions. | Full ordering, termination, retention and repeat-sync behavior on a device. |

Primary service and characteristics use the suffix `-0451-4000-b000-000000000000`. `BleProfile` and the service call sites identify `f0080001` as the service, `f0080002` as the notification characteristic and `f0080003` as the command characteristic. `BleProfileUtil` also recognizes `f0020002` in the BP service and accepts `f0080003` as input to its dispatcher. The `f003...` UI/OTA and other chip-specific paths have separate roles.

| Measurement | Evidence and assessment |
| --- | --- |
| HR | Static trace. `BleProfile.RATE_CURRENT_READ` and `RATE_CURRENT_CLOSE` define `D0 01` and `D0 00`. The notification dispatcher routes `D0` to the current-rate action. |
| SpO₂ | Static trace for history. `BleProfileUtil` routes `D2` to `Spo2hOriginalHander` history. Per-model live measurement remains open. |
| Temperature | Static trace for history and a live action. `BleProfileUtil` routes `87` with subcode `01` and history `88`. Follow `TemptureDetectHandler` and `TemptureOriginalHander` for decoding. Sensor site and calibration are open. |
| Motion | Static trace for steps and sport values in `OriginalHander`, plus current-sport and sport-session actions in `BleProfileUtil`. Raw accelerometer and gyroscope sample streams remain open. |
| Raw PPG | Open. No HBand raw waveform path established. |
| RR/PPI/IBI | Static lead. `RRIntervalManager` has a block request builder and fragment parser. No call site into that parser was found in the inspected application. The generic dispatcher uses `70` for GPS, so the matching RR opcode alone cannot establish reachability. |
| HRV | Static trace for a separate `D9` history path through `HRVHandler`. This reports no evidence of beat-level timestamping. |

### HBand RR fragment evidence

`RRIntervalManager.getRRHopByHopCmd` builds a 20-byte buffer beginning with `70`, a day selector, and a little-endian two-byte position. `handler` reads a little-endian block index at offsets 1–2, a total block count at 3–4, and fragment counters at 5–6. Fragment zero reads day state at 7, a six-byte calendar date/time at 8–13, and an allocation count at 14–15. Fragment zero copies data beginning at offset 16 and continuation fragments begin at offset 7. The helper populates an integer array from byte values. A zero block is treated as unsupported. This establishes a block timestamp field in the parser. The sample encoding, interval units, timing origin and per-beat timestamps are open.

## GBand 2.3.14

Source references below use JADX package or file names. GBand uses Nordic Scanner Compat for app scanning and the bundled Inuker `BluetoothClient` for the primary GATT path. `com.veepoo.protocol.VPOperateManager` coordinates the Veepoo SDK operations. DEX packages also show Nordic BLE and DFU, Goodix BLE, Jieli OTA/RCSP, and Bluetrum tooling. `com.veepoo.device.utils.LorentzWrapper` loads `libhrv-analysis.so`. The raw PPG and RR handlers below are visible in DEX, independently of the native HRV library.

| Stage | Static evidence | Remaining uncertainty |
| --- | --- | --- |
| Discovery | `com.veepoo.device.VPBleCenter.startScanDevice` uses Nordic Scanner Compat and passes scan bytes to `handleSearchResult`, which calls `VpBleByteUtil.isBeyondVpV2`. The SDK also has an Inuker scanning entry point. | Exact classification bytes and filters for individual firmware. |
| Connect and subscribe | `VPOperateManager.connectDevice` calls Inuker `BluetoothClient.connect` with a 10 s connection timeout and 5 s discovery timeout. `BleConnectWorker` calls Android GATT connect and service discovery. `com.veepoo.protocol.j` subscribes to the Veepoo notification characteristic. `r` passes received bytes to `lf/b.java` and the manager dispatcher. | MTU and optional services per firmware. |
| Bind/authenticate | On successful notification setup, `VPBleCenter.connectDevice$lambda$5` calls `confirmDevicePwd`. The manager delegates to the `pwd_comfirm_oprate` operation. `VPBleCenter.AnonymousClass2` handles the password response. | Initial bind, any BLE OS bonding requirement, reconnect behavior and exact firmware-specific framing. |
| History | `com.veepoo.device.utils.OriginDataReader` selects a day and stored position, calls `VPOperateManager.readOriginDataSingleDay`, persists results, and updates the cursor in `OriginDataVersionDao`. It uses origin protocol version and separate data callbacks, including oxygen history and HRV. | Firmware retention, paging limits, cursor resets and wire-level completion behavior. |

The primary UUIDs are independently confirmed by `lf/a.java`, the notify call in `com/veepoo/protocol/j.java`, and the write call in `com/veepoo/protocol/e.java`. With suffix `-0451-4000-b000-000000000000`, they are `f0080001` service, `f0080002` notifications and `f0080003` writes. The optional `f0020001` service and `f0020002` notifications carry the SDK's live PPG path.

| Measurement | Evidence and assessment |
| --- | --- |
| HR | Static trace. `VPBleCenter.startDetectHeart` calls the SDK live measurement API. `lf/b.java` maps `D0` to its heart-rate action. History flows through origin records. |
| SpO₂ | Static trace. `VPBleCenter.startDetectSPO2H` calls the live API. The dispatcher maps `80` to oxygen measurement and `D2` to oxygen history. The characteristic and active operation matter because the separate live PPG callback also recognizes `80`. |
| Temperature | Static trace. `VPBleCenter.startDetectTemperature` calls `startDetectTempture`. The dispatcher recognizes `87` and history `88`. Skin placement and accuracy are open. |
| Motion | Static trace for activity summaries and raw accelerometer decoding in the PPG subsystem. Gyroscope samples and absolute acceleration units are open. |
| Raw PPG | Static trace within the SDK. `readPPGRawData` reaches the stored `EB` handler, which emits timestamped blocks containing green-light samples and acceleration. `startPPGRealTimeTransmission` subscribes to the separate `f0020002` path, where the callback decodes green-light and acceleration notifications. App-screen callers and firmware availability remain open. |
| RR/PPI/IBI | Static trace within the SDK. `readRRIntervalByDay` creates a `70` request and registers a listener. `lf/b.java` routes `70` to `rr_interval_oprate`, which calls `p001if/w1.java` (`RRIntervalOprate`). The parser returns calendar-dated blocks and integer arrays. App-screen callers, interval encoding and per-beat timestamps remain open. |
| HRV | Static trace for separate on-demand and historical HRV flows. Native analysis presence and derived HRV output provide no evidence about beat-level timestamps. |

### GBand PPG framing leads

- `p001if/r1.java` (`PPGRawDataOperaterEB`) writes a stored read beginning with `EB 02`, mode and a four-byte start time derived from timestamp seconds. Its handler tracks fragments and reads a block index, timestamp, CRC field and count from the header. Reassembled data uses records tagged `A1` and `A2` to construct `PPGSecondData`. The parser has a follow-up write, so read-only collection still depends on the transfer state machine.
- `PPGSecondData` requires a 300-byte buffer for each lane. It reads green-light values as little-endian 24-bit integers and drops `0x808080`. It decodes acceleration as signed little-endian 16-bit X/Y/Z triples. These sizes allow up to 100 green values and 50 acceleration triples per record. Confirm cadence, sample timing and scaling with a capture. The green conversion masks all three bytes despite its signed-sounding method name.
- The live SDK callback on `f0020002` uses `80` for green light and `89` for acceleration. Its packing differs from the stored parser. Trailer meaning, integrity verification and timestamp semantics are open.

## Cross-build conclusion

Both builds contain independently traced Veepoo GATT UUIDs and some common action bytes. The `70` dispatcher difference and GBand’s dedicated PPG paths show why compatibility has to be established per operation, app build and wearable firmware. Preserve separate protocol inventories until hardware traces support consolidation. No Dart implementation or fixtures are committed at this stage. Device captures are needed to validate behavior and produce representative fixtures.
