param([string]$GodotPath='C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe',[switch]$WindOnly,[switch]$EquipmentOnly)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$setup=& (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -Tests @()
$stage=[regex]::Match(($setup -join "`n"),'Test project: (.+)').Groups[1].Value.Trim()
$iconModes=@('stations','camp-recipes')
if ($WindOnly) {$iconModes=@('wind-generator')}
if ($EquipmentOnly) {$iconModes=@('wind-generator','electronics')}
foreach ($mode in $iconModes) {
    $out=Join-Path $projectRoot "build/render-$mode.log"
    $err=Join-Path $projectRoot "build/render-$mode-errors.log"
    $args=@('--path',('"'+$stage+'"'),'--script',('"'+(Join-Path $projectRoot 'tools/render_food_icons.gd')+'"'),'--rendering-method','mobile','--rendering-driver','d3d12','--audio-driver','Dummy','--',"--$mode")
    $process=Start-Process -FilePath $GodotPath -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    $null=$process.Handle
    if (-not $process.WaitForExit(60000)) { Stop-Process -Id $process.Id;throw "Icon render timeout: $mode" }
    $result=(Get-Content -LiteralPath $out -Raw)+(Get-Content -LiteralPath $err -Raw)
    if ($process.ExitCode -ne 0 -or $result -match 'ERROR:|SCRIPT ERROR:|FAIL:' -or $result -notmatch '\d+ checks, 0 failures') {throw "Icon renderer failed. See $out and $err"}
    Write-Output ([regex]::Match($result,'(?m)^FOOD ART:.*$').Value)
}
& (Join-Path $PSScriptRoot 'import_food_icons.ps1') -GodotPath $GodotPath -IconFolder stations
if ($EquipmentOnly) { & (Join-Path $PSScriptRoot 'import_food_icons.ps1') -GodotPath $GodotPath -IconFolder tools }
elseif (-not $WindOnly) { & (Join-Path $PSScriptRoot 'import_food_icons.ps1') -GodotPath $GodotPath -IconFolder food }
