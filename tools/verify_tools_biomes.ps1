param([string]$GodotPath = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe')
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -GodotUserArgs @('--mobile-effects') -Tests @(
    'survival_tools_biomes_smoke.gd','island_visual_smoke.gd','island_wild_plants_smoke.gd',
    'action_farming_smoke.gd','cinematic_raft_smoke.gd','foundation_smoke.gd',
    'mobile_smoke.gd','menu_loading_smoke.gd','construction_weather_smoke.gd'
)
# This suite asserts first-install defaults and needs its own fresh preferences.
& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -GodotUserArgs @('--mobile-effects') -Tests @('loading_performance_smoke.gd')
