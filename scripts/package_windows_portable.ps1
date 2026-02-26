param(
    [string]$PythonExe = "python",
    [string]$OutputRoot = "build",
    [string]$FfmpegExe = ""
)

$ErrorActionPreference = "Stop"

if ($env:OS -notlike "*Windows*") {
    throw "This script must be run on Windows."
}

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RootDir

$BuildDir = Join-Path $RootDir $OutputRoot
$DistDir = Join-Path $BuildDir "windows-dist"
$WorkDir = Join-Path $BuildDir "pyinstaller-work"
$SpecDir = Join-Path $BuildDir "pyinstaller-spec"
$PortableDir = Join-Path $BuildDir "GZWhisper-windows-portable"
$ZipPath = Join-Path $BuildDir "GZWhisper-windows-portable.zip"

function Run-Step {
    param(
        [string]$Exe,
        [string[]]$Args
    )

    & $Exe @Args
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Exe $($Args -join ' ')"
    }
}

Run-Step -Exe $PythonExe -Args @("-m", "pip", "install", "--upgrade", "pip")
Run-Step -Exe $PythonExe -Args @("-m", "pip", "install", "--upgrade", "pyinstaller", "faster-whisper", "huggingface_hub")

$EntryScript = Join-Path $RootDir "linux\gzwhisper_linux.py"
if (-not (Test-Path $EntryScript)) {
    throw "Entry script not found: $EntryScript"
}

$AddWorkerData = "Resources\transcription_worker.py;Resources"
$AddIconData = "Resources\AppIcon.png;Resources"

Run-Step -Exe $PythonExe -Args @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--windowed",
    "--name", "GZWhisper",
    "--distpath", $DistDir,
    "--workpath", $WorkDir,
    "--specpath", $SpecDir,
    "--add-data", $AddWorkerData,
    "--add-data", $AddIconData,
    "--collect-all", "faster_whisper",
    "--collect-all", "huggingface_hub",
    "--collect-all", "ctranslate2",
    "--collect-all", "tokenizers",
    $EntryScript
)

if (Test-Path $PortableDir) {
    Remove-Item $PortableDir -Recurse -Force
}
New-Item -ItemType Directory -Path $PortableDir | Out-Null

$BuiltAppDir = Join-Path $DistDir "GZWhisper"
if (-not (Test-Path $BuiltAppDir)) {
    throw "PyInstaller output not found: $BuiltAppDir"
}

Copy-Item -Path (Join-Path $BuiltAppDir "*") -Destination $PortableDir -Recurse -Force

if ($FfmpegExe -and (Test-Path $FfmpegExe)) {
    Copy-Item -Path $FfmpegExe -Destination (Join-Path $PortableDir "ffmpeg.exe") -Force
}

$ReadmePath = Join-Path $PortableDir "README-Windows.txt"
@"
GZWhisper Windows Portable

Run:
  GZWhisper.exe

Notes:
  - This is a portable build and does not require installer setup.
  - For video transcription, place ffmpeg.exe next to GZWhisper.exe (or provide it in PATH).
  - Models and history are stored in your user profile.
"@ | Set-Content -Path $ReadmePath -Encoding UTF8

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}
Compress-Archive -Path (Join-Path $PortableDir "*") -DestinationPath $ZipPath -Force

Write-Host "Created: $PortableDir"
Write-Host "Created: $ZipPath"
