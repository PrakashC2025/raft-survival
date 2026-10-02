# Building the Android APK

> **⚠️ `build/OceanSurvival.apk` in this repo is a STALE build (2026-09-03).**
> It predates the current project layout: it contains **no main menu at all**
> (no `main_menu.gdc`, no HUD, no islands, no sharks, scripts still at the old
> flat `res://player.gd` paths). Installing it does **not** run the game you
> see in this source tree. Re-export before testing anything.

## 1. One-time setup (per machine)

1. **Godot 4.7.x** editor (the project is `config/features = 4.7`).
2. **Export templates**: Editor → *Manage Export Templates* → download **4.7.x**
   (must match the editor version exactly).
3. **Java JDK 17** and the **Android SDK** (`build-tools`, `platform-tools`,
   `platforms;android-35`). Point Godot at them in
   Editor → *Editor Settings → Export → Android*:
   - `Java SDK Path`
   - `Android SDK Path`
   - `Debug Keystore` — generate one if you don't have it:
     ```bash
     keytool -keyalg RSA -genkeypair -alias androiddebugkey \
       -keypass android -keystore ~/.android/debug.keystore -storepass android \
       -dname "CN=Android Debug,O=Android,C=US" -validity 9999
     ```
4. Enable the Gradle-less export (already set in `export_presets.cfg`):
   `gradle_build/use_gradle_build = false`, `architectures/arm64-v8a = true`.

## 2. Export

**From the editor:** open the project, let it finish importing (the first open
generates `.import` files for the Kenney/beach GLBs — wait for the progress bar
to disappear), then *Project → Export… → Android → Export Project…* and save
over `build/OceanSurvival.apk`.

**From a terminal (headless):**
```bash
godot --headless --path . --import                                  # generate .godot/ + .import files
godot --headless --path . --export-release "Android" build/OceanSurvival.apk
```

## 3. Install on the phone

```bash
adb install -r build/OceanSurvival.apk
```
`version/code` is now **2** (`version/name` 1.0.1) so it upgrades cleanly over
the old build. If Android still refuses, uninstall the old app first
(`adb uninstall com.praka.oceansurvival`) — this also clears the old saves in
`user://`, so the menu will show **NEW GAME** only.

## 4. Verifying you are running the new build

On the start screen tap **NEW GAME** (or **CONTINUE**):

* the tapped plank immediately flips to **`LOADING…`** with a percentage and a
  progress bar (the game scene is pre-loaded on a background thread, so on most
  phones this is a fraction of a second);
* then the game opens.

If something is wrong you now get an on-screen **red banner** with the reason
(e.g. `MISSING res://scenes/main.tscn`, `COULD NOT START GAME · err 18`)
instead of a menu that silently ignores taps. Grab the matching log line with:

```bash
adb logcat -s godot:* AndroidRuntime:E DEBUG:F | grep -i "MainMenu\|ERROR"
```

## 5. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Menu shows a red `MISSING res://scenes/main.tscn` | The export dropped the game scene. Re-run `--import`, then export with `export_filter="all_resources"` (already set). |
| Menu shows `COULD NOT START GAME · err N` | `main.tscn` failed to open. Check `adb logcat` for a missing resource — usually a GLB that was never imported (see step 2). |
| Banner `GAME SCENE FAILED TO LOAD · code 2` | Threaded load failed (out of memory on a small phone). Tap again — the menu falls back to a normal blocking load. |
| App installs but shows the old game with no menu | You installed the stale APK from the repo, not your fresh export. |
| Taps work on the menu but not in game | Unrelated to the menu; see `scripts/mobile_controls.gd` (F10 toggles the overlay on desktop previews). |
