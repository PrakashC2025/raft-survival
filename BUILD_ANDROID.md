# Android build and mobile play

The 1.1.1 update (version code 4) fixes the New Game / Continue loading failure.
The previous export excluded `models/sand_raftsurvival_Image_*`, although the
imported island scene still depends on six of those textures. Godot consequently
reported threaded load status 2 and scene error 19. Keep required island textures
in the export; reducing their size should be done through import settings.

## Build

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