param([string]$GodotPath = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe')
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -GodotUserArgs @('--mobile-effects') -Tests @(
    'underwater_expansion_smoke.gd','survival_tools_biomes_smoke.gd',
    'advanced_survival_smoke.gd','portable_electronics_smoke.gd',
    'action_farming_smoke.gd','construction_weather_smoke.gd','rope_smoke.gd',
    'foundation_smoke.gd','mobile_smoke.gd','menu_loading_smoke.gd'
)
# First-install defaults are checked in fresh, isolated preferences.
& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -GodotUserArgs @('--mobile-effects') -Tests @('loading_performance_smoke.gd')
& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -GodotUserArgs @('--mobile-effects') -Tests @('night_sky_smoke.gd')
