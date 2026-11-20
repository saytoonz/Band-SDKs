# Experiments and decisions

## 2026-11-20

1. Hashed both supplied bundles, extracted the base and ARM64 splits, checked the manifest with `aapt2 dump badging`, and checked the signing certificates with `apksigner verify --print-certs`. The results are in [APK provenance](apk-provenance.md).
2. Decompiled each base with JADX 1.5.6 using `jadx --no-res -j 3 -d <output> <base.apk>`. Searched all three DEX files for class descriptors in parallel with decompilation. A DEX string can establish that a symbol exists. Method behavior and callers require stronger evidence from decompilation or bytecode.
3. Ran `adb devices -l`. No Android device was attached. No application install, GATT connection, measurement or packet capture was performed.

The repository tracks source citations, observations and decisions. The local APK archives, generated decompiler output and packet captures stay outside Git. Keep independent findings for each app and require device evidence before enabling live transmission from an application. Original codecs should be based on documented field semantics and use sanitized captures or clearly labeled synthetic fixtures. Use fixtures to cover truncation, repeated or missing fragments, unsupported capabilities and reported time boundaries where applicable.

## Reproducing static inspection

Run these commands from the repository root. Set the build-tools location to the installed Android SDK version used for inspection.

```sh
inspection_dir=$(mktemp -d /tmp/thrivnme-apk.XXXXXX)
android_build_tools="$HOME/Library/Android/sdk/build-tools/36.0.0"

for app in HBand GBand; do
  mkdir -p "$inspection_dir/$app"
  unzip -j "$app"/Resource/*.apks base.apk split_config.arm64_v8a.apk -d "$inspection_dir/$app"
  shasum -a 256 "$app"/Resource/*.apks "$inspection_dir/$app"/*.apk
  "$android_build_tools/aapt2" dump badging "$inspection_dir/$app/base.apk"
  "$android_build_tools/apksigner" verify --print-certs "$inspection_dir/$app/base.apk"
  unzip -Z1 "$inspection_dir/$app/split_config.arm64_v8a.apk"
  jadx --no-res -j 3 -d "$inspection_dir/$app/jadx" "$inspection_dir/$app/base.apk"
done
```

## First hardware session

- Identify one supported model per app. Log model, firmware, phone OS and APK hash alongside test timestamps, and retain stable aliases for devices when redacting captures.
- Capture discovery, initial connection, a user-authorized bind, an app restart, and a reconnect with the existing bind. Record advertisement bytes, discovered services, subscribed characteristics, MTU, GATT write types and order. Note any OS bond prompt independently from application binding.
- Capture a single feature at a time. Trigger HR, SpO₂ and temperature measurements, then observe notification routing and data fields. Compare idle telemetry, movement and a workout to establish whether there are raw motion samples or only summaries.
- Disconnect long enough to accumulate history, then record first sync, repeat sync and reconnect during transfer. Locate day selectors, cursors, paging, termination, duplicate handling and any acknowledgments that change watch state.
- On firmware that exposes the capability, isolate raw PPG and RR retrieval. Compare packet lengths, sample widths, sample cadence, channel identities, interval units and the relationship of device wall clock to the session clock. Preserve timestamps and quality flags in fixtures where verified, and redact identifiers and bind credentials.

## Static inspection limits

JADX produced source trees but reported 31 errors for HBand and 144 for GBand. The report relies on visible method bodies and named references. Recheck any ambiguous control flow against DEX disassembly before turning it into a wire specification. The GBand analysis found SDK-internal callers for PPG and RR and no app-screen entry point in the searched call sites. HBand's RR recognition remains unresolved because the parser has no located caller and its first byte also identifies GPS in the generic dispatcher.

## Phase 2 offline investigation

- No compatible Veepoo hardware is available. Apple Watch Series 8 and WHOOP 4.0 were excluded from this study.
- Cross-checked the GBand handlers against Android Build Tools `dexdump` for the original, hashed APK, including an instruction-order discrepancy in JADX around the `A1` lane length. Both lane lengths are LE. The [wire report](gband-wire.md) records method descriptors, code item addresses and verified instructions.
- Traced model and feature gates and compared the bundled SDK symbols with Veepoo's public JH58 documentation. The [compatibility inventory](device-compatibility.md) separates an APK behavior, a project candidate and a retail pairing lead.
- Chose block-scoped, transport-independent codecs that handle reordering within one block, preserve uncalibrated signals and expose inert write packets. CRC, RR unit conversion and live optical decoding remain open. No compatible watch was used for the tests.
- Ran `dart analyze` and `dart test` with Dart 3.13.7. The analyzer reported no issues and all seven synthetic fixture tests passed.
