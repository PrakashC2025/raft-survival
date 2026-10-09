param([string]$GodotPath = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe')
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -GodotUserArgs @('--mobile-effects') -Tests @(
    'tumbler_smoke.gd','realism_polish_smoke.gd','food_action_smoke.gd','survival_services_smoke.gd',
    'island_wild_plants_smoke.gd','action_farming_smoke.gd','cinematic_raft_smoke.gd',
    'environment_smoke.gd','construction_weather_smoke.gd','mobile_smoke.gd','menu_loading_smoke.gd'
)
