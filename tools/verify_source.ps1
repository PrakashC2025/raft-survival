param(
    [Parameter(Mandatory=$true)][string]$GodotPath,
    [string[]]$Tests = @('rope_smoke.gd', 'testing_resources_smoke.gd', 'mobile_smoke.gd', 'foundation_smoke.gd', 'environment_smoke.gd', 'island_marker_smoke.gd')
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $projectRoot ('build/source-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sourceRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'project.godot') -Destination (Join-Path $sourceRoot 'project.godot')
foreach ($folder in @('.godot', 'addons', 'audio', 'models', 'scenes', 'scripts', 'shaders', 'textures', 'grass', 'Depries')) {
    $target = Join-Path $projectRoot $folder
    if (Test-Path -LiteralPath $target) {
        New-Item -ItemType Junction -Path (Join-Path $sourceRoot $folder) -Target $target | Out-Null
    }
}
$config = '[application]' + [Environment]::NewLine + 'config/use_custom_user_dir=true' + [Environment]::NewLine + 'config/custom_user_dir_name="OceanSurvivalSourceMobileTests-' + (Split-Path $sourceRoot -Leaf) + '"'
[IO.File]::WriteAllText((Join-Path $sourceRoot 'override.cfg'), $config)
foreach ($test in $Tests) {
    $testPath = Join-Path (Join-Path $projectRoot 'tests') $test
    $logPath = Join-Path (Join-Path $projectRoot 'build') ('source-' + [IO.Path]::GetFileNameWithoutExtension($test) + '.log')
    $processOutput = & $GodotPath --headless --path $sourceRoot --script $testPath --log-file $logPath 2>&1 | Out-String
    $testExit = $LASTEXITCODE
    $consolePath = Join-Path (Join-Path $projectRoot 'build') ('source-' + [IO.Path]::GetFileNameWithoutExtension($test) + '-console.log')
    [IO.File]::WriteAllText($consolePath, $processOutput)
    $stream = [IO.File]::Open($logPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = [IO.StreamReader]::new($stream)
    try { $result = $reader.ReadToEnd() + [Environment]::NewLine + $processOutput } finally { $reader.Dispose() }
    if ($testExit -ne 0 -or $result -match 'SCRIPT ERROR:|ERROR:|FAIL:' -or $result -notmatch '\d+ checks, 0 failures') {
        throw "Source verification failed: $testPath. Read $logPath and $consolePath"
    }
    Write-Output ([regex]::Match($processOutput, '(?m)^.*\d+ checks, 0 failures.*$').Value.Trim())
}
Write-Output "Source checks passed without exporting an APK. Test project: $sourceRoot"
