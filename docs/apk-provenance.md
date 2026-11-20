# APK provenance

Inspected the supplied APKCube split bundles locally. Package and SDK fields come from the binary base manifests. APKCube metadata is packaging provenance. The signing digests identify these samples.

## HBand

```text
package: name='com.veepoo.hband' versionCode='11050' versionName='11.0.50' platformBuildVersionName='14' platformBuildVersionCode='34' compileSdkVersion='34' compileSdkVersionCodename='14'
minSdkVersion:'23'
targetSdkVersion:'37'
uses-permission: name='android.permission.ACTIVITY_RECOGNITION'
uses-permission: name='android.permission.MODIFY_AUDIO_SETTINGS'
uses-permission: name='android.permission.FOREGROUND_SERVICE'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.ACCESS_NOTIFICATION_POLICY'
uses-permission: name='android.permission.VIBRATE'
uses-permission: name='android.permission.WRITE_EXTERNAL_STORAGE' maxSdkVersion='32'
uses-permission: name='android.permission.READ_EXTERNAL_STORAGE' maxSdkVersion='32'
uses-permission: name='android.permission.ACCESS_WIFI_STATE'
uses-permission: name='android.permission.CHANGE_WIFI_STATE'
uses-permission: name='android.permission.CAMERA'
uses-permission: name='android.permission.DISABLE_KEYGUARD'
uses-permission: name='android.permission.WAKE_LOCK'
uses-permission: name='android.permission.MANAGE_ACCOUNTS'
uses-permission: name='android.permission.GET_ACCOUNTS'
uses-permission: name='android.permission.RECEIVE_BOOT_COMPLETED'
uses-permission: name='android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'
uses-permission: name='android.permission.SYSTEM_ALERT_WINDOW'
uses-permission: name='android.permission.SYSTEM_OVERLAY_WINDOW'
uses-permission: name='android.permission.READ_CONTACTS'
uses-permission: name='android.permission.WRITE_CONTACTS'
uses-permission: name='android.permission.ANSWER_PHONE_CALLS'
uses-permission: name='android.permission.CALL_PHONE'
uses-permission: name='android.permission.READ_PHONE_STATE'
uses-permission: name='android.permission.ACCESS_BACKGROUND_LOCATION'
uses-permission: name='android.permission.ACCESS_LOCATION_EXTRA_COMMANDS'
uses-permission: name='android.permission.QUERY_ALL_PACKAGES'
uses-permission: name='android.permission.ACCESS_COARSE_LOCATION'
uses-permission: name='android.permission.ACCESS_FINE_LOCATION'
uses-permission: name='android.permission.BLUETOOTH' maxSdkVersion='30'
uses-permission: name='android.permission.BLUETOOTH_ADMIN' maxSdkVersion='30'
uses-permission: name='android.permission.BLUETOOTH_SCAN' usesPermissionFlags='neverForLocation'
uses-permission: name='android.permission.BLUETOOTH_ADVERTISE' usesPermissionFlags='neverForLocation'
uses-permission: name='android.permission.BLUETOOTH_CONNECT' usesPermissionFlags='neverForLocation'
uses-permission: name='android.permission.MEDIA_CONTENT_CONTROL'
uses-permission: name='android.permission.RECORD_AUDIO'
uses-permission: name='android.permission.POST_NOTIFICATIONS'
uses-permission: name='android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE'
uses-permission: name='android.permission.FOREGROUND_SERVICE_LOCATION'
uses-permission: name='android.permission.BROADCAST_STICKY'
uses-permission: name='com.veepoo.hband.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

Declared permissions above include duplicate manifest entries where reported by `aapt2`.

| Artifact | SHA-256 |
| --- | --- |
| H-Band_11.0.50_apkcube.apks | `dfb62cb94914051dd86b3cc541800bc39a27c1588a5b885db874ee80342e8af9` |
| base.apk | `2937b4714c43499481e18e3cc77bce57174373c770cc7a6de168d6f5e1a8d7fd` |
| split_config.arm64_v8a.apk | `819f38e270ee1026ea07466a3479ef653ed4af83f8fc93e19e1b07797dc2ef3d` |

Base and ARM64 split signer SHA-256 is `81da19948bfd13139cae459f1bd4e63b8c780e2be846471e74392c0562b53ac5`. The base has three DEX files. ARM64 is the only ABI split supplied.

### ARM64 native libraries

- `libAMapSDK_MAP_v11_1_063.so`
- `libBugly_Native.so`
- `libSparkChain.so`
- `libabpartool.so`
- `libbugly_dumper.so`
- `libbuglybacktrace.so`
- `libfntvcrash.so`
- `libjl_auth.so`
- `libjl_bmp_convert.so`
- `libjl_crc.so`
- `libjl_fatfs.so`
- `libjl_ota_auth.so`
- `libjl_pack_format.so`
- `libluoentz.so`
- `libnative-lib.so`
- `libopus.so`
- `libopusJni.so`
- `librmonitor_base.so`
- `librmonitor_memory.so`
- `libscannative.so`
- `libspark.so`

## GBand

```text
package: name='com.vpgband.app' versionCode='377' versionName='2.3.14' platformBuildVersionName='14' platformBuildVersionCode='34' compileSdkVersion='34' compileSdkVersionCodename='14'
minSdkVersion:'26'
targetSdkVersion:'36'
uses-permission: name='android.permission.BLUETOOTH' maxSdkVersion='30'
uses-permission: name='android.permission.BLUETOOTH_ADMIN'
uses-permission: name='android.permission.ACCESS_FINE_LOCATION'
uses-permission: name='android.permission.READ_EXTERNAL_STORAGE' maxSdkVersion='32'
uses-permission: name='android.permission.CAMERA'
uses-permission: name='android.permission.REORDER_TASKS'
uses-permission: name='android.permission.BLUETOOTH_SCAN' usesPermissionFlags='neverForLocation'
uses-permission: name='android.permission.BLUETOOTH_ADVERTISE' usesPermissionFlags='neverForLocation'
uses-permission: name='android.permission.POST_NOTIFICATIONS'
uses-permission: name='android.permission.BLUETOOTH_CONNECT' usesPermissionFlags='neverForLocation'
uses-permission: name='android.permission.READ_CALL_LOG'
uses-permission: name='android.permission.READ_CONTACTS'
uses-permission: name='android.permission.ANSWER_PHONE_CALLS'
uses-permission: name='android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'
uses-permission: name='android.permission.ACCESS_COARSE_LOCATION'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.ACCESS_WIFI_STATE'
uses-permission: name='android.permission.CHANGE_WIFI_STATE'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.READ_PHONE_STATE'
uses-permission: name='android.permission.WRITE_EXTERNAL_STORAGE' maxSdkVersion='32'
uses-permission: name='android.permission.ACCESS_LOCATION_EXTRA_COMMANDS'
uses-permission: name='android.permission.FOREGROUND_SERVICE'
uses-permission: name='android.permission.ACCESS_BACKGROUND_LOCATION'
uses-permission: name='android.permission.VIBRATE'
uses-permission: name='android.permission.USE_VIBRATION_API'
uses-permission: name='android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING'
uses-permission: name='android.permission.FOREGROUND_SERVICE_LOCATION'
uses-permission: name='android.permission.FOREGROUND_SERVICE_TYPE_DATA_SYNC'
uses-permission: name='android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE'
uses-permission: name='android.permission.health.WRITE_HEART_RATE'
uses-permission: name='android.permission.health.WRITE_SLEEP'
uses-permission: name='android.permission.health.WRITE_STEPS'
uses-permission: name='android.permission.health.WRITE_DISTANCE'
uses-permission: name='android.permission.health.WRITE_TOTAL_CALORIES_BURNED'
uses-permission: name='android.permission.health.WRITE_OXYGEN_SATURATION'
uses-permission: name='android.permission.health.WRITE_BLOOD_PRESSURE'
uses-permission: name='android.permission.health.WRITE_BODY_TEMPERATURE'
uses-permission: name='android.permission.health.WRITE_BLOOD_GLUCOSE'
uses-permission: name='android.permission.MODIFY_AUDIO_SETTINGS'
uses-permission: name='android.permission.QUERY_ALL_PACKAGES'
uses-permission: name='android.permission.ACTIVITY_RECOGNITION'
uses-permission: name='android.permission.REQUEST_COMPANION_RUN_IN_BACKGROUND'
uses-permission: name='android.permission.REQUEST_COMPANION_USE_DATA_IN_BACKGROUND'
uses-permission: name='android.permission.REQUEST_OBSERVE_COMPANION_DEVICE_PRESENCE'
uses-permission: name='android.permission.FLASHLIGHT'
uses-permission: name='android.permission.WAKE_LOCK'
uses-permission: name='com.vpgband.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

Declared permissions above include duplicate manifest entries where reported by `aapt2`.

| Artifact | SHA-256 |
| --- | --- |
| G-Band_2.3.14_apkcube.apks | `06d9ae4cfed947382d676248dff6307ff413f31f242a6418ebbd79edd408ae25` |
| base.apk | `17075099a59ce209cf9cca20f6e62aa0b4c6a8001b46c63b75a12e873de893be` |
| split_config.arm64_v8a.apk | `98465fa5b911f72e2d5fccf01c14712871cdd67d4c68bcabf38f4bfc93d5cc4c` |

Base and ARM64 split signer SHA-256 is `2fd60c92a41c233de777e20cb94921a71d145cfa3c2fa35f5cb4c7d2794f28e9`. The base has three DEX files. ARM64 is the only ABI split supplied.

### ARM64 native libraries

- `libAMapSDK_MAP_v11_1_063.so`
- `libSparkChain.so`
- `libabpartool.so`
- `libfntvcrash.so`
- `libhrv-analysis.so`
- `libimage_processing_util_jni.so`
- `libjl_auth.so`
- `libjl_bmp_convert.so`
- `libjl_crc.so`
- `libjl_fatfs.so`
- `libjl_ota_auth.so`
- `libjl_pack_format.so`
- `libluoentz-ecg.so`
- `libluoentz.so`
- `libmmkv.so`
- `libnative-lib.so`
- `libopus.so`
- `libopusJni.so`
- `libspark.so`
- `libsurface_util_jni.so`

Inspection tools were Android Build Tools 36.0.0 (`aapt2`, `apksigner`) and JADX 1.5.6. Signature verification returned success for both bases and both ARM64 splits. The base verifier emitted warnings for unsigned JAR metadata entries.
