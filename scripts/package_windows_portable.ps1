param(
    [string]$PythonExe = "python",
    [string]$OutputRoot = "build",
    [string]$FfmpegExe = "",
    [switch]$SkipBundledFfmpeg,
    [string]$FfmpegDownloadUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
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
$FfmpegCacheDir = Join-Path $BuildDir "ffmpeg-cache"

function Run-Step {
    param(
        [string]$Exe,
        [string[]]$Arguments
    )

    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Exe $($Arguments -join ' ')"
    }
}

function Test-PythonCommand {
    param(
        [string]$Candidate
    )

    try {
        & $Candidate -c "import sys" *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Resolve-PythonExe {
    param(
        [string]$Requested
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($Requested, "python3", "python")) {
        if ($candidate) {
            $candidates.Add($candidate)
        }
    }

    foreach ($baseDir in @(
        (Join-Path $env:LocalAppData "Programs\Python"),
        "C:\Program Files",
        "C:\Program Files (x86)"
    )) {
        if (-not (Test-Path $baseDir)) {
            continue
        }

        Get-ChildItem -Path $baseDir -Directory -Filter "Python*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object {
                $pythonPath = Join-Path $_.FullName "python.exe"
                if (Test-Path $pythonPath) {
                    $candidates.Add($pythonPath)
                }
            }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-PythonCommand -Candidate $candidate) {
            return $candidate
        }
    }

    throw "Working Python executable not found. Install Python 3.11+ or pass -PythonExe <path>."
}

function Resolve-CommandPath {
    param(
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command -and $command.Source -and (Test-Path $command.Source)) {
            return $command.Source
        }
    }

    return $null
}

function Get-OrDownloadBundledFfmpeg {
    param(
        [string]$DownloadUrl,
        [string]$CacheDir
    )

    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null

    $archivePath = Join-Path $CacheDir "ffmpeg-release-essentials.zip"
    $extractDir = Join-Path $CacheDir "ffmpeg-release-essentials"

    if (-not (Test-Path $archivePath)) {
        Write-Host "Downloading ffmpeg from $DownloadUrl"
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $archivePath
    }

    if (Test-Path $extractDir) {
        Remove-Item $extractDir -Recurse -Force
    }
    Expand-Archive -Path $archivePath -DestinationPath $extractDir -Force

    $ffmpegBinary = Get-ChildItem -Path $extractDir -Recurse -Filter "ffmpeg.exe" -File | Select-Object -First 1
    if (-not $ffmpegBinary) {
        throw "Downloaded ffmpeg archive does not contain ffmpeg.exe"
    }

    $licenseFile = Get-ChildItem -Path $extractDir -Recurse -Include "LICENSE*", "COPYING*" -File |
        Sort-Object FullName |
        Select-Object -First 1

    return [pscustomobject]@{
        ExePath     = $ffmpegBinary.FullName
        LicensePath = $(if ($licenseFile) { $licenseFile.FullName } else { $null })
        Source      = "download"
    }
}

function Resolve-FfmpegAsset {
    param(
        [string]$Requested,
        [switch]$SkipDownload
    )

    if ($Requested) {
        if (-not (Test-Path $Requested)) {
            throw "ffmpeg executable not found: $Requested"
        }

        return [pscustomobject]@{
            ExePath     = (Resolve-Path $Requested).Path
            LicensePath = $null
            Source      = "parameter"
        }
    }

    $pathCommand = Resolve-CommandPath -Names @("ffmpeg", "ffmpeg.exe")
    if ($pathCommand) {
        return [pscustomobject]@{
            ExePath     = $pathCommand
            LicensePath = $null
            Source      = "path"
        }
    }

    if ($SkipDownload) {
        return $null
    }

    return Get-OrDownloadBundledFfmpeg -DownloadUrl $FfmpegDownloadUrl -CacheDir $FfmpegCacheDir
}

$ResolvedPythonExe = Resolve-PythonExe -Requested $PythonExe
$ResolvedFfmpegAsset = Resolve-FfmpegAsset -Requested $FfmpegExe -SkipDownload:$SkipBundledFfmpeg

Run-Step -Exe $ResolvedPythonExe -Arguments @("-m", "pip", "install", "--upgrade", "pip")
Run-Step -Exe $ResolvedPythonExe -Arguments @("-m", "pip", "install", "--upgrade", "pyinstaller", "faster-whisper", "huggingface_hub")

$EntryScript = Join-Path $RootDir "linux\gzwhisper_linux.py"
if (-not (Test-Path $EntryScript)) {
    throw "Entry script not found: $EntryScript"
}

$WorkerScriptPath = Join-Path $RootDir "Resources\transcription_worker.py"
$IconPath = Join-Path $RootDir "Resources\AppIcon.png"
$AddWorkerData = "$WorkerScriptPath;Resources"
$AddIconData = "$IconPath;Resources"

Run-Step -Exe $ResolvedPythonExe -Arguments @(
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

if ($ResolvedFfmpegAsset) {
    Copy-Item -Path $ResolvedFfmpegAsset.ExePath -Destination (Join-Path $PortableDir "ffmpeg.exe") -Force

    if ($ResolvedFfmpegAsset.LicensePath) {
        Copy-Item -Path $ResolvedFfmpegAsset.LicensePath -Destination (Join-Path $PortableDir "ffmpeg-LICENSE.txt") -Force
    }
}

$ReadmePath = Join-Path $PortableDir "README-Windows.txt"
@"
GZWhisper Windows Portable

Run:
  GZWhisper.exe

Notes:
  - This is a portable build and does not require installer setup.
  - ffmpeg.exe is bundled for video transcription unless the package was built with -SkipBundledFfmpeg.
  - Models and history are stored in your user profile.
"@ | Set-Content -Path $ReadmePath -Encoding UTF8

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}
Compress-Archive -Path (Join-Path $PortableDir "*") -DestinationPath $ZipPath -Force

Write-Host "Created: $PortableDir"
Write-Host "Created: $ZipPath"
if ($ResolvedFfmpegAsset) {
    Write-Host "Bundled ffmpeg from: $($ResolvedFfmpegAsset.Source)"
}
