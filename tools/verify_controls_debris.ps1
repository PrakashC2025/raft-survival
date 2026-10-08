param([string]$GodotPath = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe')
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -Tests @('edit_tree_smoke.gd','rope_smoke.gd','testing_resources_smoke.gd','menu_loading_smoke.gd','environment_smoke.gd','action_farming_smoke.gd') -GodotUserArgs @('--mobile-effects')
