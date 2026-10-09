param([string]$GodotPath = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe', [ValidateSet('food','tools','stations')][string]$IconFolder='food')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
# A small real directory, with no junctions or game save files.
$iconProject = Join-Path $projectRoot "build/$IconFolder-icon-import"
$iconDirectory = Join-Path $iconProject "textures/ui/$IconFolder"
New-Item -ItemType Directory -Force -Path $iconDirectory | Out-Null
[IO.File]::WriteAllText((Join-Path $iconProject 'project.godot'), ('[application]' + [Environment]::NewLine + 'config/name="Food Icon Import"'))
Get-ChildItem -LiteralPath (Join-Path $projectRoot "textures/ui/$IconFolder") -Filter '*.png' -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $iconDirectory -Force
}
$audioDirectory = Join-Path $iconProject 'audio'
New-Item -ItemType Directory -Force -Path $audioDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'audio/action_stone.wav') -Destination $audioDirectory -Force
& $GodotPath --headless --editor --path $iconProject --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Food icon import failed.' }
Get-ChildItem -LiteralPath $iconDirectory -Filter '*.import' -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $projectRoot "textures/ui/$IconFolder") -Force
}
Copy-Item -LiteralPath (Join-Path $audioDirectory 'action_stone.wav.import') -Destination (Join-Path $projectRoot 'audio') -Force
Get-ChildItem -LiteralPath (Join-Path $iconProject '.godot/imported') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $projectRoot '.godot/imported') -Force
}
Write-Output "$IconFolder pictures and stone-striking sound imported. No saves or APK changed."
