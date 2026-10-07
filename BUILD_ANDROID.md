# Android build and mobile play

The current preset is **1.1.2 (version code 5)** for manual phone testing.
It retains the New Game / Continue loading fix first delivered in 1.1.1.
The previous export excluded `models/sand_raftsurvival_Image_*`, although the
imported island scene still depends on six of those textures. Godot consequently
reported threaded load status 2 and scene error 19. Keep required island textures
in the export; reducing their size should be done through import settings.

## Build

### Export from the editor

1. Close and reopen this Godot project before exporting. An editor left open can
   overwrite externally corrected presets with its cached old settings.
2. Open **Project → Export**, then select **Android**.
3. Check **Resources → Export all resources in the project**. The exclusion
   field must not contain `models/sand_raftsurvival_Image_*` or
   `textures/sand_raftsurvival_*`; the island needs those textures.
4. Under **Options**, use **APK**, **Use Gradle Build: Off**,
   **Arm64-v8a: On**, **Version Code: 5**, **Version Name: 1.1.2**,
   **Unique Name: com.praka.oceansurvival**, and **Signed: On**.
   Leave SDK version overrides and custom templates empty to use the installed
   Godot templates. Keep the existing debug signing key.
5. Click **Export Project**, save to `build/OceanSurvival-updated.apk`, leave
   **Export With Debug** checked for this testing build, then click **Save**.
6. Copy the newly exported APK to the phone and install it as an update.

Matching **4.7.1.stable.mono** Android export templates and Android SDK build
tools are installed locally. If Godot reports missing prerequisites, check
**Editor → Manage Export Templates** and **Editor → Editor Settings → Export →
Android**. The Android SDK directory is
`C:\Users\praka\AppData\Local\Android\Sdk`; Java SDK Path must point to the
installed JDK directory (currently
`C:\Program Files\Eclipse Adoptium\jdk-25.0.4.101-hotspot`). See the
[official Android export instructions](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html).

This preset is for an APK installed directly on your phone. Play Store submission
uses an AAB, Gradle, and release signing instead.

### Optional command line export and package check

Use the installed Godot 4.7.1 editor and matching Android export templates, JDK,
Android SDK, and existing debug keystore. This local APK uses debug signing so it
can update an installation signed with the same key.

```powershell
$godot = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe'
& $godot --headless --path . --export-debug Android build/OceanSurvival-updated.apk
.\tools\verify_android.ps1 -ApkPath .\build\OceanSurvival-updated.apk -GodotPath $godot
```

The verification script extracts the **built APK**, then checks packaged scene
loading, New Game, Continue, touch routing, action buttons, inventory dragging,
climbing, editing, pause, help, map, crafting, saves, and settings. Foundation checks cover P and mobile PLACE, exact positions, five-wood costs, missing socket metadata, and saved buildings. It uses an
isolated `OceanSurvivalMobileTests` save folder. A passing source-tree run alone
cannot catch assets excluded from an APK.

The export intentionally excludes build output, tests, and asset-download tools.
Do not add broad exclusion patterns for textures referenced by game scenes.

## Install the update

Copy `build/OceanSurvival-updated.apk` to the Android phone and open it to install the
update. Keep the existing app installed to retain its saves. Alternatively:

```powershell
& 'C:\Users\praka\AppData\Local\Android\Sdk\platform-tools\adb.exe' install -r .\build\OceanSurvival-updated.apk
```

This package targets ARM64 phones and uses Godot's Mobile renderer. APKs are for
Android; this build does not provide an iPhone installer.

## Phone controls and settings

- Play in landscape. Left joystick moves; drag elsewhere to look around.
- Jump, run, hook, dive, and use support independent fingers. Release the hook
  button to throw; drag out of a held button to cancel that input.
- Map, crafting, bag, pause, and help are on-screen. The hand and climb buttons
  appear when the aimed item can be used or the raft is within reach.
- Build selects a preview; Next chooses a piece; Rotate turns it; Place builds.
  Aim at a placed piece and tap Edit to move it, or Remove to refund it.
- Settings are available on the main menu and the pause menu. Graphics, 30/60 FPS,
  look speed, inverted look, camera view, and sound volume are saved automatically.
- Start with Auto graphics. For a slower or hotter phone, choose Battery Saver
  and 30 FPS. Auto reduces 3D resolution under sustained slow frames while keeping
  the interface clear. Phone grass generation is capped and split across frames.
- Android Back closes the current panel or toggles pause. Switching apps pauses
  play and saves progress. The bag's Quick Save button writes a separate slot.

A desktop packaged-asset test confirms loading and input logic. Confirm graphics,
frame rate, heat, and multi-touch feel on the actual phone before distribution.


## Latest source fixes and Xiaomi testing

The 2026-10-03 source fixes the Pause → Quit detached-HUD error and the reported integer-division/fishing-variable warnings. Tree preparation is split across frames, and Android grass scattering uses smaller work batches to reduce startup spikes. Reopen Godot before manually exporting a fresh APK; installing the old build will not include these changes. No new APK was exported by the coding agent.

For the owner's Xiaomi 11 Lite-class phone, begin with **Settings → Graphics → Battery Saver**, **Frame rate → 30 FPS**, in landscape. Keep ARM64 enabled and all required island textures included when exporting. Install the APK as an update with the existing signing key and package name, preserving app data/saves. Test New Game/Continue, walking and looking together, Pause → Quit → Continue, building and bag/map/crafting. Actual phone frame rate, temperature and memory use remain unverified. Try Balanced after stable play; High may need more GPU time than this device can sustain.


## New video intro (2026-10-07)

New Game now uses the 31-second movie with video sound, spoken narration and subtitles, followed by a prepared dawn fade. Reopen the project and let resource imports finish before exporting. Keep **Export all resources** selected and do not exclude `video/*`: both `video/new_game_intro.ogv` and `video/intro_arrival.jpg` are required. The existing preset already includes them. The local raw film and preparation tools under `tools/` remain excluded. Required island textures must also remain included.

After manually exporting, test full New Game playback, Skip, Back to Menu/Android Back, background/resume, volume/mute, the dawn transition and Continue on the phone. Continue should bypass the video and restore its saved time. Four isolated source suites passed 164 checks, and full desktop Mobile-renderer playback/arrival passed; no APK or Android phone playback was verified by this change. Battery Saver at 30 FPS remains the suggested starting setting for the owner's Xiaomi phone.


## Latest rounded timber source update

Reopen the editor and let resource imports finish before the owner's manual export. Keep `models/survivalist.glb`, `scenes/half_wall.tscn`, `scenes/cargo_crate.tscn`, `textures/construction/` and all existing required island textures included. The selected timber atlas retains its import settings: VRAM compression, High Quality, mipmaps, and Size Limit 1024. Current generated formats are desktop BPTC and Android ASTC; the source PNG remains 1254 by 1254. The existing video-intro export instructions still apply. No APK was built or inspected for this source update.

The Mobile renderer uses depth fog and analytic ocean reflection; SSAO, SSR and volumetric fog are enabled only for the supported desktop Forward+ profile. Start phone testing with Battery Saver and 30 FPS, then check the intro transition, rounded decks, room roofs, the cargo crate/net/coil, open wooden shutters and touch release after pausing. Desktop preview rates are not phone evidence.

Encrypted-save transfers require `raft_save.key` along with the primary and backup save files in the same app data directory. Do not delete the owner's app data to test this update; source verification uses isolated storage.
