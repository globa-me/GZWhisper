# GZWhisper on Windows (Portable)

This guide is for non-technical Windows users and maintainers who build the portable package.

## 1) What "portable" means

- No installer is required.
- You can run the app directly from a folder after extracting the ZIP.
- The app does not need a system-wide Python installation.

## 2) Download and launch (end users)

1. Download `GZWhisper-windows-portable.zip` from Releases.
2. Right-click the ZIP and choose **Extract All...**.
3. Open the extracted folder.
4. Run `GZWhisper.exe`.

Important:
- Do not run directly from inside the ZIP archive.
- Keep all files from the extracted folder together.

## 3) First run

1. Click **Download model** (or **Connect local** if you already have a model folder).
2. Wait for model download and validation.
3. Add one or multiple audio/video files.
4. Click **Transcribe all**.
5. Save result as TXT/JSON if needed.

## 4) Video transcription (`ffmpeg.exe`)

For video files (`.mp4`, `.mkv`, `.mov`, etc.), `ffmpeg.exe` is required.

Options:
- Place `ffmpeg.exe` in the same folder as `GZWhisper.exe` (recommended).
- Or install ffmpeg and ensure it is available in `PATH`.

If ffmpeg is missing, video transcription will fail with an explicit error, while audio-only files still work.

## 5) Where app data is stored

- App support files: `%LOCALAPPDATA%\gzwhisper-windows`
- Default model/transcript folder: `%USERPROFILE%\Documents\GZWhisper`
- Queue history file: `%USERPROFILE%\Documents\GZWhisper\transcripts\history.json`

## 6) Updating portable version

1. Close GZWhisper.
2. Download and extract the new portable ZIP into a new folder.
3. Optionally copy your `ffmpeg.exe` into the new folder.
4. Run the new `GZWhisper.exe`.

Your models/transcripts/history remain in your user profile folders and are not tied to a specific app folder.

## 7) Common Windows issues

### SmartScreen warning

If Windows SmartScreen warns on first run:
1. Click **More info**.
2. Click **Run anyway**.

### Antivirus quarantined files

- Restore quarantined files from antivirus history.
- Add the portable folder to antivirus exclusions.

### "ffmpeg is required"

- Ensure `ffmpeg.exe` exists next to `GZWhisper.exe` or is in `PATH`.
- Reopen the app after adding ffmpeg.

### App fails to start after moving files

- Re-extract ZIP and keep folder structure unchanged.
- Do not move only `GZWhisper.exe` by itself.

## 8) Building portable package (maintainers, on Windows)

From project root:

```powershell
.\scripts\package_windows_portable.ps1
```

Alternative:

```cmd
scripts\package_windows_portable.cmd
```

Optional (bundle ffmpeg into output folder):

```powershell
.\scripts\package_windows_portable.ps1 -FfmpegExe "C:\tools\ffmpeg\bin\ffmpeg.exe"
```

Build outputs:
- `build/GZWhisper-windows-portable/`
- `build/GZWhisper-windows-portable.zip`
