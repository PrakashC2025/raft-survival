param([string]$GodotPath = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe')
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -Tests @(
    'mobile_bag_rain_smoke.gd', 'construction_weather_smoke.gd',
    'survival_services_smoke.gd', 'edit_tree_smoke.gd', 'mobile_smoke.gd', 'menu_loading_smoke.gd'
) -GodotUserArgs @('--mobile-effects')
