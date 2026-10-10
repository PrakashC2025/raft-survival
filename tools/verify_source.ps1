param(
    [Parameter(Mandatory=$true)][string]$GodotPath,
    [string[]]$Tests = @('rope_smoke.gd', 'testing_resources_smoke.gd', 'mobile_smoke.gd', 'foundation_smoke.gd', 'environment_smoke.gd', 'island_marker_smoke.gd', 'menu_loading_smoke.gd', 'survival_loop_smoke.gd', 'advanced_survival_smoke.gd', 'cinematic_raft_smoke.gd', 'world_visual_smoke.gd', 'visual_build_overhaul_smoke.gd', 'island_visual_smoke.gd'),
    [string[]]$GodotUserArgs = @(),
    [string[]]$GodotEngineArgs = @(),
    [switch]$StrictWarnings
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $projectRoot ('build/source-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sourceRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'project.godot') -Destination (Join-Path $sourceRoot 'project.godot')
foreach ($folder in @('.godot', 'addons', 'audio', 'video', 'models', '3d models', 'scenes', 'scripts', 'shaders', 'textures', 'grass', 'Depries')) {
    $target = Join-Path $projectRoot $folder
    if (Test-Path -LiteralPath $target) {
        New-Item -ItemType Junction -Path (Join-Path $sourceRoot $folder) -Target $target | Out-Null
    }
}
$config = '[application]' + [Environment]::NewLine + 'config/use_custom_user_dir=true' + [Environment]::NewLine + 'config/custom_user_dir_name="OceanSurvivalSourceMobileTests-' + (Split-Path $sourceRoot -Leaf) + '"'
if ($StrictWarnings) {
    # Promote Godot 4.7's normally enabled first-party warnings only in this
    # isolated project. Keep the owner's settings and addon directory rules.
    $warningNames = @(
        'unassigned_variable',
        'unassigned_variable_op_assign',
        'unused_variable',
        'unused_local_constant',
        'unused_private_class_variable',
        'unused_parameter',
        'unused_signal',
        'shadowed_variable',
        'shadowed_variable_base_class',
        'shadowed_global_identifier',
        'unreachable_code',
        'unreachable_pattern',
        'standalone_expression',
        'standalone_ternary',
        'incompatible_ternary',
        'unsafe_void_return',
        'static_called_on_instance',
        'missing_tool',
        'redundant_static_unload',
        'redundant_await',
        'assert_always_true',
        'assert_always_false',
        'integer_division',
        'narrowing_conversion',
        'int_as_enum_without_cast',
        'int_as_enum_without_match',
        'enum_variable_without_default',
        'empty_file',
        'deprecated_keyword',
        'confusable_identifier',
        'confusable_local_declaration',
        'confusable_local_usage',
        'confusable_capture_reassignment',
        'confusable_temporary_modification',
        'property_used_as_function',
        'constant_used_as_function',
        'function_used_as_property'
    )
    $config += [Environment]::NewLine + '[debug]'
    foreach ($warningName in $warningNames) {
        $config += [Environment]::NewLine + 'gdscript/warnings/' + $warningName + '=2'
    }
}
[IO.File]::WriteAllText((Join-Path $sourceRoot 'override.cfg'), $config)
foreach ($test in $Tests) {
    $testPath = Join-Path (Join-Path $projectRoot 'tests') $test
    $logPath = Join-Path (Join-Path $projectRoot 'build') ('source-' + [IO.Path]::GetFileNameWithoutExtension($test) + '.log')
    # Windows PowerShell treats native stderr as an ErrorRecord. Capture the
    # complete fixture result before interpreting it, including failures.
    $ErrorActionPreference = 'Continue'
    try {
        $processOutput = & $GodotPath @GodotEngineArgs --headless --path $sourceRoot --script $testPath --log-file $logPath -- @GodotUserArgs 2>&1 | Out-String
        $testExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = 'Stop' }
    $consolePath = Join-Path (Join-Path $projectRoot 'build') ('source-' + [IO.Path]::GetFileNameWithoutExtension($test) + '-console.log')
    [IO.File]::WriteAllText($consolePath, $processOutput)
    $stream = [IO.File]::Open($logPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = [IO.StreamReader]::new($stream)
    try { $result = $reader.ReadToEnd() + [Environment]::NewLine + $processOutput } finally { $reader.Dispose() }
    if ($testExit -ne 0 -or $result -match 'SCRIPT ERROR:|ERROR:|FAIL:' -or ($StrictWarnings -and $result -match 'WARNING:') -or $result -notmatch '\d+ checks, 0 failures') {
        throw "Source verification failed: $testPath. Read $logPath and $consolePath"
    }
    Write-Output ([regex]::Match($processOutput, '(?m)^.*\d+ checks, 0 failures.*$').Value.Trim())
}
Write-Output "Source checks passed without exporting an APK. Test project: $sourceRoot"
