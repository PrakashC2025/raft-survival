param([string]$GodotPath = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
# Import just the rendered icons; do not scan test junctions or owner Blender inputs.
$iconProject = Join-Path $projectRoot 'build/produce-icon-import'
$iconDirectory = Join-Path $iconProject 'textures/ui'
New-Item -ItemType Directory -Force -Path $iconDirectory | Out-Null
[IO.File]::WriteAllText((Join-Path $iconProject 'project.godot'), ('[application]' + [Environment]::NewLine + 'config/name="Produce Icon Import"'))
foreach ($item in @('potato','tomato','banana')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot "textures/ui/advanced_$item.png") -Destination $iconDirectory -Force
}
& $GodotPath --headless --editor --path $iconProject --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Produce icon import failed.' }
foreach ($item in @('potato','tomato','banana')) {
    Copy-Item -LiteralPath (Join-Path $iconDirectory "advanced_$item.png.import") -Destination (Join-Path $projectRoot 'textures/ui') -Force
}
Get-ChildItem -LiteralPath (Join-Path $iconProject '.godot/imported') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $projectRoot '.godot/imported') -Force
}
Write-Output 'Three produce icons imported. No game saves or APK changed.'
