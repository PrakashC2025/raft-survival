param([string]$GodotPath='C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$audioProject=Join-Path $projectRoot 'build/contact-audio-import'
$editorProfile=Join-Path $audioProject 'editor-profile'
$audioDirectory=Join-Path $audioProject 'audio/contact'
New-Item -ItemType Directory -Force -Path $audioDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $editorProfile | Out-Null
# Keep headless imports out of the owner's editor settings and user:// save data.
$env:APPDATA=$editorProfile
[IO.File]::WriteAllText((Join-Path $audioProject 'project.godot'), "[application]`nconfig/name=`"Contact Audio Import`"")
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'audio/contact') -Filter '*.wav' -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $audioDirectory -Force
}
& $GodotPath --headless --editor --path $audioProject --import --quit
if ($LASTEXITCODE -ne 0) {throw 'Contact audio import failed.'}
$taskReimport=$false
Get-ChildItem -LiteralPath $audioDirectory -Filter '*.import' -File | ForEach-Object {
    $taskImportText=[IO.File]::ReadAllText($_.FullName)
    if ($taskImportText -match 'compress/mode=[12]') {
        [IO.File]::WriteAllText($_.FullName,($taskImportText -replace 'compress/mode=[12]','compress/mode=0'))
        $taskReimport=$true
    }
}
if ($taskReimport) {
    & $GodotPath --headless --editor --path $audioProject --import --quit
    if ($LASTEXITCODE -ne 0) {throw 'PCM contact audio import failed.'}
}
Get-ChildItem -LiteralPath $audioDirectory -Filter '*.import' -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $projectRoot 'audio/contact') -Force
}
Get-ChildItem -LiteralPath (Join-Path $audioProject '.godot/imported') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $projectRoot '.godot/imported') -Force
}
Write-Output 'Contact recordings imported without touching game saves or APKs.'
