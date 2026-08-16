# Phase 0.2 camera spike

Throwaway measurement harness for `design_docs/implementation_plan.md` §0.2 and
`architecture.md` §10.2. Measures the naive GDScript camera path on the target
Android tablet:

```
CameraServer/CameraFeed → CameraTexture.get_image() readback → JPEG encode
```

Per second it logs: camera feed fps, extracted frames/s, readback and encode
timings (avg/max), JPEG size, process and total CPU %, memory, temperature.
Output: `user://camera_spike_<timestamp>.csv` + a JSON summary at run end.
This is the commit-or-abandon test for the vision path — the numbers decide:
GDScript sufficient / C++ GDExtension required / camera plan revised.

## Controls (on device)

- **Start/Stop** — 30-minute benchmark run (auto-stops, writes JSON summary)
- **Rate** — extraction rate: 5 / 10 / 15 / 30 fps / MAX (every process frame)
- **Res** — requested feed format: 640×480 / 1280×720 / 1920×1080
- **Camera** — cycle front/rear feeds

Single-threaded on purpose: the point is measuring the naive path, not masking
its cost.

## Desktop smoke test (no camera needed)

```
godot --headless --path spikes/camera_spike -- --self-test
```

Runs a 6-second benchmark with no feed (state `NO_FEED`) and quits; validates
script, logging and summary end-to-end.

## Deploy to the tablet (tomorrow)

1. Prereq on the dev PC: a working Android SDK (build-tools + platform) and the
   Godot editor settings `export/android/android_sdk_path` /
   `export/android/java_sdk_path` pointing at it. The SDK on this machine is
   incomplete (only `platform-tools`) — **the user will reinstall it**; the
   agent must not fix or redownload it.
2. `export_presets.cfg` is gitignored; if missing, create an Android preset in
   the editor with package `org.echo.camspike` and **CAMERA permission** (both
   already set in the local preset file when present).
3. Tablet: developer mode + USB debugging, connect, `adb devices`.
4. Either "Remote Deploy" from the Godot editor, or:
   ```
   godot --headless --path spikes/camera_spike --export-debug Android build/camera_spike.apk
   adb install -r build/camera_spike.apk
   ```

## Collecting a run

```
adb shell am start -n org.echo.camspike/com.godot.game.GodotApp
tools/collect_device_metrics.sh 1 1800   # adb-side thermal/CPU during the run
```

Then pull the app logs (path is printed at startup and shown on screen):

```
adb exec-out run-as org.echo.camspike cat \
  /data/data/org.echo.camspike/files/camera_spike_<ts>.csv > camera_spike_<ts>.csv
# or, if user:// resolved to external storage:
adb pull /sdcard/Android/data/org.echo.camspike/files/ .
```

## Recording the result

Write measured numbers + failure modes into `design_docs/implementation_plan.md`
§0.2 and record the decision there (GDScript / GDExtension / plan revised).
