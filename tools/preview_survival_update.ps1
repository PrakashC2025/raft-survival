param(
    [string]$GodotPath = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe',
    [ValidateSet('survival_services_smoke.gd','loading_performance_smoke.gd','edit_tree_smoke.gd')][string]$TestScript = 'survival_services_smoke.gd',
    [ValidateRange(60,300)][int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
# Reuse the source verifier's isolation setup with no headless suites.
$setupOutput = & (Join-Path $PSScriptRoot 'verify_source.ps1') -GodotPath $GodotPath -Tests @()
$stage = [regex]::Match(($setupOutput -join "`n"), 'Test project: (.+)').Groups[1].Value.Trim()
if (-not $stage) { throw 'Preview isolation setup did not return a project.' }
$logPrefix = if ($TestScript -eq 'loading_performance_smoke.gd') { 'loading' } elseif ($TestScript -eq 'edit_tree_smoke.gd') { 'edit-tree' } else { 'services' }
$outputLog = Join-Path $projectRoot "build/$logPrefix-native-final-console.log"
$errorLog = Join-Path $projectRoot "build/$logPrefix-native-final-errors.log"
$arguments = @('--path', ('"' + $stage + '"'), '--script', ('"' + (Join-Path $projectRoot ('tests/' + $TestScript)) + '"'), '--rendering-method', 'mobile', '--rendering-driver', 'd3d12', '--', '--preview', '--mobile-effects', '--profile-loading')
$previewProcess = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $outputLog -RedirectStandardError $errorLog -PassThru
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while (-not $previewProcess.WaitForExit(1000)) {
    if ([DateTime]::UtcNow -lt $deadline) { continue }
    # Only close this isolated preview and its console wrapper, never the owner's editor.
    $previewTasks = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -like '*Godot*' -and $_.CommandLine.Contains($stage) -and $_.CommandLine.Contains($TestScript)
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
if ($previewProcess.ExitCode -ne 0 -or $result -match 'SCRIPT ERROR:|ERROR:|FAIL:' -or $result -notmatch '\d+ checks, 0 failures') {
    throw "Desktop preview failed. Read $outputLog and $errorLog."
}
Write-Output ([regex]::Match($result, '(?m)^.*\d+ checks, 0 failures.*$').Value.Trim())
Write-Output "Desktop $logPrefix preview passed with isolated saves. No APK exported."
