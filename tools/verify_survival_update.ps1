param(
    [string]$GodotPath = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -GodotUserArgs @('--mobile-effects') -Tests @(
    'survival_services_smoke.gd', 'portable_electronics_smoke.gd', 'island_wild_plants_smoke.gd',
    'action_farming_smoke.gd', 'mobile_smoke.gd', 'survival_loop_smoke.gd', 'advanced_survival_smoke.gd',
    'crop_torch_smoke.gd', 'shelter_farming_ui_smoke.gd', 'planter_onion_smoke.gd', 'island_visual_smoke.gd',
    'environment_smoke.gd', 'testing_resources_smoke.gd', 'mobile_clear_air_smoke.gd',
    'construction_weather_smoke.gd', 'foundation_smoke.gd', 'visual_build_overhaul_smoke.gd', 'world_visual_smoke.gd'
)
