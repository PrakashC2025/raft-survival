param(
    [Parameter(Mandatory=$true)][string]$ApkPath,
    [Parameter(Mandatory=$true)][string]$GodotPath
)
$ErrorActionPreference = 'Stop'
function Read-TestLog([string]$path) {
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = [IO.StreamReader]::new($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}
$projectRoot = Split-Path $PSScriptRoot -Parent
$apkAbsolute = (Resolve-Path -LiteralPath $ApkPath).Path
$godotAbsolute = (Resolve-Path -LiteralPath $GodotPath).Path
$buildRoot = Join-Path $projectRoot 'build'
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $buildRoot '.gdignore'), '')
$auditRoot = Join-Path $buildRoot ('apk-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($apkAbsolute)
try {
    foreach ($entry in $archive.Entries) {
        if (-not $entry.FullName.StartsWith('assets/') -or $entry.FullName.EndsWith('/')) { continue }
        $target = [IO.Path]::GetFullPath((Join-Path $auditRoot $entry.FullName.Substring(7)))
        if (-not $target.StartsWith($auditRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Unsafe path in APK asset archive.'
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
    }
} finally { $archive.Dispose() }
# Change only the test data location, using all the exported game scripts.
$config = '[application]' + [Environment]::NewLine + 'config/use_custom_user_dir=true' + [Environment]::NewLine + 'config/custom_user_dir_name="OceanSurvivalMobileTests"'
[IO.File]::WriteAllText((Join-Path $auditRoot 'override.cfg'), $config)
$logPath = Join-Path $buildRoot 'mobile-smoke.log'
& $godotAbsolute --headless --path $auditRoot --script (Join-Path $projectRoot 'tests/mobile_smoke.gd') --log-file $logPath
$testExitCode = $LASTEXITCODE
$logText = (Read-TestLog $logPath)
if ($testExitCode -ne 0 -or $logText -match 'SCRIPT ERROR:|ERROR:|FAIL:' -or $logText -notmatch 'MOBILE SMOKE: \d+ checks, 0 failures') {
    throw "Android asset/control verification failed. Read $logPath"
}
$foundationLog = Join-Path $buildRoot 'foundation-smoke.log'
& $godotAbsolute --headless --path $auditRoot --script (Join-Path $projectRoot 'tests/foundation_smoke.gd') --log-file $foundationLog
$foundationExitCode = $LASTEXITCODE
$foundationText = (Read-TestLog $foundationLog)
if ($foundationExitCode -ne 0 -or $foundationText -match 'SCRIPT ERROR:|ERROR:|FAIL:' -or $foundationText -notmatch 'FOUNDATION SMOKE: \d+ checks, 0 failures') {
    throw "Foundation placement verification failed. Read $foundationLog"
}
Write-Output "Verified packaged APK assets, mobile controls and foundation placement. Logs: $logPath, $foundationLog"