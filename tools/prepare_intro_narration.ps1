$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$rootPath = Split-Path $PSScriptRoot -Parent
$clipFolder = Join-Path $rootPath 'tools/intro_source/narration'
New-Item -ItemType Directory -Path $clipFolder -Force | Out-Null
$synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
$synth.SelectVoice('Microsoft David Desktop')
$format = [System.Speech.AudioFormat.SpeechAudioFormatInfo]::new(22050,[System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,[System.Speech.AudioFormat.AudioChannel]::Mono)
$lines = @('A stone from space was falling toward Earth.','Life below went on.','Then it struck the ocean.','A wave higher than the buildings raced toward the shore.','The flood swallowed our cities.','Ninety-five percent of the land vanished. Only a few islands remained.','I woke alone on tied logs.','With my rope gun, I must salvage, build, and survive.')
$limits = @(3.1,1.75,2.65,6.6,2.9,4.3,2.3,4.2)
try {
    for ($lineIndex=0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $clipPath = Join-Path $clipFolder ('line-'+$lineIndex+'.wav')
        for ($speechRate=0; $speechRate -le 5; $speechRate++) {
            $synth.Rate = $speechRate
            $synth.SetOutputToWaveFile($clipPath,$format)
            $synth.Speak($lines[$lineIndex])
            $synth.SetOutputToNull()
            $seconds = ((Get-Item -LiteralPath $clipPath).Length-46)/44100.0
            if ($seconds -lt $limits[$lineIndex]) { break }
        }
        if ($seconds -ge $limits[$lineIndex]) { throw "Narration line $lineIndex does not fit its scene." }
        Write-Output ('Line {0}: {1:N2}s, rate {2}' -f $lineIndex,$seconds,$speechRate)
    }
} finally { $synth.Dispose() }
