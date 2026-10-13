param(
    [string]$GodotPath = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe',
    [ValidateSet('fishing_drinking_smoke.gd','swim_jump_smoke.gd','free_assets_smoke.gd','mixamo_character_smoke.gd','jump_smoke.gd','render_stability_smoke.gd','single_coconut_smoke.gd','torch_distance_smoke.gd','craft_ocean_hitch_smoke.gd','held_tools_garden_smoke.gd','ocean_surface_preview.gd','underwater_reference_smoke.gd','garden_cycle_smoke.gd','salvage_power_net_smoke.gd','ocean_menu_preview.gd','equipment_repair_smoke.gd','portable_electronics_smoke.gd','current_wind_build_smoke.gd','meals_night_supplies_smoke.gd','camp_fire_smoke.gd','survival_services_smoke.gd','loading_performance_smoke.gd','edit_tree_smoke.gd','stairs_sky_smoke.gd','food_action_smoke.gd','cinematic_native_preview.gd','realism_polish_smoke.gd','tumbler_smoke.gd','survival_tools_biomes_smoke.gd','night_sky_smoke.gd','underwater_expansion_smoke.gd','mobile_bag_rain_smoke.gd')][string]$TestScript = 'survival_services_smoke.gd',
    [ValidateRange(60,300)][int]$TimeoutSeconds = 120,
    [switch]$SilentAudio,
    [switch]$SurfaceClearance,
    [ValidateSet('mobile','gl_compatibility')][string]$Renderer = 'mobile'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
# Reuse the source verifier's isolation setup with no headless suites.
$setupOutput = & (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -Tests @()
$stage = [regex]::Match(($setupOutput -join "`n"), 'Test project: (.+)').Groups[1].Value.Trim()
if (-not $stage) { throw 'Preview isolation setup did not return a project.' }
$logPrefix = if ($TestScript -eq 'craft_ocean_hitch_smoke.gd') { 'craft-hitch' } elseif ($TestScript -eq 'held_tools_garden_smoke.gd') { 'held-tools-garden' } elseif ($TestScript -eq 'ocean_surface_preview.gd') { 'ocean-blue-' + $Renderer } elseif ($TestScript -eq 'underwater_reference_smoke.gd') { 'reef-reference-' + $Renderer } elseif ($TestScript -eq 'garden_cycle_smoke.gd') { 'garden-cycle' } elseif ($TestScript -eq 'salvage_power_net_smoke.gd') { 'salvage-power-net' } elseif ($TestScript -eq 'ocean_menu_preview.gd') { 'ocean-menu' } elseif ($TestScript -eq 'current_wind_build_smoke.gd') { 'current-wind-build' } elseif ($TestScript -eq 'meals_night_supplies_smoke.gd') { 'meals-night-supplies' } elseif ($TestScript -eq 'camp_fire_smoke.gd') { 'camp-fire' } elseif ($TestScript -eq 'mobile_bag_rain_smoke.gd') { 'mobile-bag-rain' } elseif ($TestScript -eq 'underwater_expansion_smoke.gd') { 'underwater' } elseif ($TestScript -eq 'night_sky_smoke.gd') { 'night-sky' } elseif ($TestScript -eq 'survival_tools_biomes_smoke.gd') { 'tools-biomes' } elseif ($TestScript -eq 'tumbler_smoke.gd') { 'tumbler' } elseif ($TestScript -eq 'realism_polish_smoke.gd') { 'realism' } elseif ($TestScript -eq 'food_action_smoke.gd') { 'food-action' } elseif ($TestScript -eq 'cinematic_native_preview.gd') { 'cinematic' } elseif ($TestScript -eq 'loading_performance_smoke.gd') { 'loading' } elseif ($TestScript -eq 'edit_tree_smoke.gd') { 'edit-tree' } elseif ($TestScript -eq 'stairs_sky_smoke.gd') { 'stairs-sky' } else { 'services' }
if ($TestScript -eq 'torch_distance_smoke.gd') { $logPrefix = 'torch-distance' }
if ($TestScript -eq 'single_coconut_smoke.gd') { $logPrefix = 'single-coconut' }
if ($TestScript -eq 'render_stability_smoke.gd') { $logPrefix = 'render-stability' }
if ($TestScript -eq 'jump_smoke.gd') { $logPrefix = 'jump' }
if ($TestScript -eq 'fishing_drinking_smoke.gd') { $logPrefix = 'fishing-drinking' }
if ($TestScript -eq 'swim_jump_smoke.gd') { $logPrefix = 'swim-jump' }
if ($TestScript -eq 'free_assets_smoke.gd') { $logPrefix = 'free-assets' }
if ($TestScript -eq 'mixamo_character_smoke.gd') { $logPrefix = 'mixamo-character' }
$outputLog = Join-Path $projectRoot "build/$logPrefix-native-final-console.log"
$errorLog = Join-Path $projectRoot "build/$logPrefix-native-final-errors.log"
$arguments = @('--path', ('"' + $stage + '"'), '--script', ('"' + (Join-Path $projectRoot ('tests/' + $TestScript)) + '"'), '--rendering-method', $Renderer, '--rendering-driver', $(if ($Renderer -eq 'gl_compatibility') { 'opengl3' } else { 'd3d12' }))
if ($SilentAudio) { $arguments += @('--audio-driver','Dummy') }
$arguments += @('--', '--preview', '--mobile-effects', '--profile-loading')
if ($SurfaceClearance) {
    if ($TestScript -ne 'underwater_reference_smoke.gd') { throw 'SurfaceClearance requires the underwater reference fixture.' }
    $arguments += '--clearance-preview'
}
$previewProcess = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $outputLog -RedirectStandardError $errorLog -PassThru
# Retain the process handle so Windows PowerShell can read ExitCode after
# asynchronous polling even when the child exits between checks.
$null = $previewProcess.Handle
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while (-not $previewProcess.WaitForExit(1000)) {
    if ([DateTime]::UtcNow -lt $deadline) { continue }
    # Only close this isolated preview and its console wrapper, never the owner's editor.
    $previewTasks = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -like '*Godot*' -and $_.CommandLine -and $_.CommandLine.Contains($stage) -and $_.CommandLine.Contains($TestScript)
    }
    foreach ($previewTask in $previewTasks) { Stop-Process -Id $previewTask.ProcessId -ErrorAction SilentlyContinue }
    throw "Desktop preview did not close within $TimeoutSeconds seconds. Inspect $outputLog and $errorLog."
}
function Read-SharedLog([string]$Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = [IO.StreamReader]::new($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}
$result = (Read-SharedLog $outputLog) + (Read-SharedLog $errorLog)
if ($previewProcess.ExitCode -ne 0 -or $result -match 'SCRIPT ERROR:|ERROR:|FAIL:' -or $result -notmatch '\d+ checks, 0 failures|NATIVE VIDEO HANDOFF: full film') {
    throw "Desktop preview failed (exit $($previewProcess.ExitCode)). Read $outputLog and $errorLog."
}
Write-Output ([regex]::Match($result, '(?m)^.*\d+ checks, 0 failures.*$').Value.Trim())
Write-Output "Desktop $logPrefix preview passed with isolated saves. No APK exported."
