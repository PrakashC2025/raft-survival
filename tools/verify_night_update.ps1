param([string]$GodotPath = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe')
$ErrorActionPreference = 'Stop'
# Preference migration/fresh defaults need their own isolated settings file.
& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -Tests @('night_sky_smoke.gd') -GodotUserArgs @('--mobile-effects')
& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -Tests @(
    'stairs_sky_smoke.gd', 'survival_loop_smoke.gd', 'visual_build_overhaul_smoke.gd',
    'environment_smoke.gd', 'portable_electronics_smoke.gd', 'crop_torch_smoke.gd'
) -GodotUserArgs @('--mobile-effects')
