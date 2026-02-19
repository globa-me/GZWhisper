#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

APP_NAME = "GZWhisper Linux"
APP_ID = "gzwhisper-linux"
MODEL_REPO_CANDIDATES = [
    "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
    "SYSTRAN/faster-whisper-large-v3",
]
MODEL_SOURCE_URLS = [f"https://huggingface.co/{repo}" for repo in MODEL_REPO_CANDIDATES]
AUDIO_VIDEO_FILETYPES = [
    (
        "Audio/Video",
        "*.mp3 *.wav *.m4a *.aac *.flac *.ogg *.opus *.mp4 *.mkv *.mov *.avi *.webm *.m4v",
    ),
    ("All files", "*.*"),
]
VIDEO_EXTENSIONS = {".mp4", ".mkv", ".mov", ".avi", ".webm", ".m4v"}
LANGUAGE_OPTIONS = [
    ("Auto", "auto"),
    ("Russian", "ru"),
    ("English", "en"),
    ("Deutsch", "de"),
    ("Espanol", "es"),
]


@dataclass
class LocalModelReference:
    model_id: str
    model_path: str
    source_type: str
    source_repo: str | None
    configured_at: str


def get_data_root() -> Path:
    xdg_data_home = os.environ.get("XDG_DATA_HOME")
    if xdg_data_home:
        return Path(xdg_data_home)
    return Path.home() / ".local" / "share"


DATA_ROOT = get_data_root()
SUPPORT_DIR = DATA_ROOT / APP_ID
VENV_DIR = SUPPORT_DIR / "venv"
WORKER_SCRIPT_RUNTIME = SUPPORT_DIR / "transcription_worker.py"
MODEL_REFERENCE_PATH = SUPPORT_DIR / "selected_model.json"
DEFAULT_MODEL_DOWNLOAD_DIR = Path.home() / "Documents" / "GZWhisper"


def find_worker_template() -> Path:
    current_dir = Path(__file__).resolve().parent
    candidates = [
        current_dir / "transcription_worker.py",
        current_dir.parent / "Resources" / "transcription_worker.py",
        current_dir.parent.parent / "Resources" / "transcription_worker.py",
    ]

    for path in candidates:
        if path.is_file():
            return path

    raise FileNotFoundError("transcription_worker.py not found near application files.")


def format_bytes(num_bytes: int) -> str:
    step = 1024.0
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(num_bytes)
    for unit in units:
        if value < step or unit == units[-1]:
            return f"{value:.1f} {unit}"
        value /= step
    return f"{num_bytes} B"


def parse_last_json(stdout: str) -> dict[str, Any] | None:
    lines = [line.strip() for line in stdout.splitlines() if line.strip()]
    for line in reversed(lines):
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            return payload
    return None


def get_venv_python() -> Path:
    py3 = VENV_DIR / "bin" / "python3"
    if py3.exists():
        return py3

    py = VENV_DIR / "bin" / "python"
    if py.exists():
        return py

    raise FileNotFoundError("Python executable in virtual environment was not found.")


class GZWhisperLinuxApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(APP_NAME)
        self.geometry("1100x760")
        self.minsize(900, 640)

        self.ui_queue: queue.Queue[tuple[Callable[..., None], tuple[Any, ...], dict[str, Any]]] = queue.Queue()
        self.is_busy = False
        self.selected_file: Path | None = None
        self.current_model: LocalModelReference | None = None
        self.last_segments: list[dict[str, Any]] = []
        self.last_model_id: str | None = None
        self.detected_language = "-"

        self.language_display_to_code = {display: code for display, code in LANGUAGE_OPTIONS}
        self.language_code_to_display = {code: display for display, code in LANGUAGE_OPTIONS}

        self.model_status_var = tk.StringVar(value="Model is not connected")
        self.model_source_var = tk.StringVar(value="")
        self.model_location_var = tk.StringVar(value="")
        self.file_var = tk.StringVar(value="No file selected")
        self.status_var = tk.StringVar(value="Ready")
        self.download_source_var = tk.StringVar(value="")
        self.download_progress_var = tk.StringVar(value="")
        self.detected_language_var = tk.StringVar(value="-")
        self.language_var = tk.StringVar(value=self.language_code_to_display["auto"])

        self._build_ui()
        self._load_model_reference()
        self._drain_ui_queue()

    def _build_ui(self) -> None:
        outer = ttk.Frame(self, padding=16)
        outer.pack(fill=tk.BOTH, expand=True)

        header = ttk.Frame(outer)
        header.pack(fill=tk.X)

        ttk.Label(header, text=APP_NAME, font=("TkDefaultFont", 20, "bold")).pack(anchor=tk.W)
        ttk.Label(
            header,
            text="Local audio/video transcription with faster-whisper",
        ).pack(anchor=tk.W, pady=(2, 0))

        model_frame = ttk.LabelFrame(outer, text="Model", padding=12)
        model_frame.pack(fill=tk.X, pady=(14, 8))

        ttk.Label(model_frame, textvariable=self.model_status_var).grid(row=0, column=0, sticky="w")

        self.btn_download_model = ttk.Button(model_frame, text="Download model", command=self.download_model)
        self.btn_download_model.grid(row=0, column=1, padx=(8, 0), sticky="e")

        self.btn_connect_model = ttk.Button(model_frame, text="Connect local", command=self.connect_local_model)
        self.btn_connect_model.grid(row=0, column=2, padx=(8, 0), sticky="e")

        self.btn_open_model = ttk.Button(model_frame, text="Open folder", command=self.open_model_folder)
        self.btn_open_model.grid(row=0, column=3, padx=(8, 0), sticky="e")

        self.btn_delete_model = ttk.Button(model_frame, text="Delete model", command=self.delete_model)
        self.btn_delete_model.grid(row=0, column=4, padx=(8, 0), sticky="e")

        ttk.Label(model_frame, text="Source:").grid(row=1, column=0, sticky="w", pady=(8, 0))
        ttk.Label(model_frame, textvariable=self.model_source_var).grid(row=1, column=1, columnspan=4, sticky="w", pady=(8, 0))

        ttk.Label(model_frame, text="Path:").grid(row=2, column=0, sticky="w", pady=(2, 0))
        ttk.Label(model_frame, textvariable=self.model_location_var).grid(row=2, column=1, columnspan=4, sticky="w", pady=(2, 0))

        ttk.Label(model_frame, textvariable=self.download_source_var).grid(row=3, column=0, columnspan=5, sticky="w", pady=(8, 0))

        self.progress_bar = ttk.Progressbar(model_frame, mode="determinate", maximum=100)
        self.progress_bar.grid(row=4, column=0, columnspan=5, sticky="ew", pady=(4, 0))

        ttk.Label(model_frame, textvariable=self.download_progress_var).grid(row=5, column=0, columnspan=5, sticky="w", pady=(2, 0))

        model_frame.columnconfigure(0, weight=1)

        file_frame = ttk.LabelFrame(outer, text="Input", padding=12)
        file_frame.pack(fill=tk.X, pady=(4, 8))

        self.btn_choose_file = ttk.Button(file_frame, text="Add audio/video", command=self.choose_file)
        self.btn_choose_file.grid(row=0, column=0, sticky="w")

        ttk.Label(file_frame, textvariable=self.file_var).grid(row=0, column=1, sticky="w", padx=(10, 0))

        ttk.Label(file_frame, text="Language:").grid(row=1, column=0, sticky="w", pady=(10, 0))

        self.language_combo = ttk.Combobox(
            file_frame,
            state="readonly",
            values=[display for display, _ in LANGUAGE_OPTIONS],
            textvariable=self.language_var,
            width=18,
        )
        self.language_combo.grid(row=1, column=1, sticky="w", pady=(10, 0))

        ttk.Label(file_frame, text="Detected:").grid(row=1, column=2, sticky="e", padx=(20, 6), pady=(10, 0))
        ttk.Label(file_frame, textvariable=self.detected_language_var).grid(row=1, column=3, sticky="w", pady=(10, 0))

        self.btn_transcribe = ttk.Button(file_frame, text="Transcribe", command=self.transcribe_selected_file)
        self.btn_transcribe.grid(row=1, column=4, sticky="e", padx=(10, 0), pady=(10, 0))

        file_frame.columnconfigure(1, weight=1)

        output_frame = ttk.LabelFrame(outer, text="Result", padding=12)
        output_frame.pack(fill=tk.BOTH, expand=True)

        top_row = ttk.Frame(output_frame)
        top_row.pack(fill=tk.X, pady=(0, 8))

        self.btn_copy = ttk.Button(top_row, text="Copy all", command=self.copy_all_text)
        self.btn_copy.pack(side=tk.LEFT)

        self.btn_save_txt = ttk.Button(top_row, text="Save TXT", command=self.save_txt)
        self.btn_save_txt.pack(side=tk.LEFT, padx=(8, 0))

        self.btn_save_json = ttk.Button(top_row, text="Save JSON", command=self.save_json)
        self.btn_save_json.pack(side=tk.LEFT, padx=(8, 0))

        self.text = tk.Text(output_frame, wrap=tk.WORD)
        self.text.pack(fill=tk.BOTH, expand=True, side=tk.LEFT)

        scrollbar = ttk.Scrollbar(output_frame, orient=tk.VERTICAL, command=self.text.yview)
        scrollbar.pack(fill=tk.Y, side=tk.RIGHT)
        self.text.configure(yscrollcommand=scrollbar.set)

        status_bar = ttk.Frame(outer)
        status_bar.pack(fill=tk.X, pady=(8, 0))
        ttk.Label(status_bar, textvariable=self.status_var).pack(anchor=tk.W)

        self._refresh_controls()

    def _post_ui(self, callback: Callable[..., None], *args: Any, **kwargs: Any) -> None:
        self.ui_queue.put((callback, args, kwargs))

    def _drain_ui_queue(self) -> None:
        while True:
            try:
                callback, args, kwargs = self.ui_queue.get_nowait()
            except queue.Empty:
                break
            callback(*args, **kwargs)
        self.after(80, self._drain_ui_queue)

    def _run_in_background(self, fn: Callable[[], None]) -> None:
        if self.is_busy:
            return

        self.is_busy = True
        self._refresh_controls()

        def worker() -> None:
            try:
                fn()
            except Exception as exc:  # noqa: BLE001
                self._post_ui(self._show_error, str(exc))
            finally:
                self._post_ui(self._finish_background)

        threading.Thread(target=worker, daemon=True).start()

    def _finish_background(self) -> None:
        self.is_busy = False
        self._refresh_controls()

    def _refresh_controls(self) -> None:
        connected = self.current_model is not None
        has_text = bool(self.text.get("1.0", tk.END).strip())

        state_normal = tk.NORMAL if not self.is_busy else tk.DISABLED
        self.btn_download_model.configure(state=state_normal)
        self.btn_connect_model.configure(state=state_normal)
        self.btn_open_model.configure(state=tk.NORMAL if connected and not self.is_busy else tk.DISABLED)
        self.btn_delete_model.configure(state=tk.NORMAL if connected and not self.is_busy else tk.DISABLED)
        self.btn_choose_file.configure(state=state_normal)

        can_transcribe = connected and self.selected_file is not None and not self.is_busy
        self.btn_transcribe.configure(state=tk.NORMAL if can_transcribe else tk.DISABLED)

        text_btn_state = tk.NORMAL if has_text and not self.is_busy else tk.DISABLED
        self.btn_copy.configure(state=text_btn_state)
        self.btn_save_txt.configure(state=text_btn_state)
        self.btn_save_json.configure(state=text_btn_state)

        self.language_combo.configure(state="readonly" if not self.is_busy else "disabled")

    def _set_status(self, value: str) -> None:
        self.status_var.set(value)

    def _set_download_progress(self, downloaded: int, total: int | None) -> None:
        if total and total > 0:
            percent = max(0.0, min(100.0, downloaded * 100.0 / total))
            self.progress_bar.stop()
            self.progress_bar.configure(mode="determinate", value=percent)
            self.download_progress_var.set(
                f"Downloaded: {format_bytes(downloaded)} / {format_bytes(total)} ({percent:.1f}%)"
            )
            return

        if self.progress_bar.cget("mode") != "indeterminate":
            self.progress_bar.configure(mode="indeterminate", value=0)
            self.progress_bar.start(12)

        self.download_progress_var.set(f"Downloaded: {format_bytes(downloaded)}")

    def _reset_download_progress(self) -> None:
        self.progress_bar.stop()
        self.progress_bar.configure(mode="determinate", value=0)
        self.download_source_var.set("")
        self.download_progress_var.set("")

    def _show_error(self, message: str) -> None:
        self._set_status(f"Error: {message}")
        messagebox.showerror(APP_NAME, message)

    def _sync_worker_script(self) -> None:
        SUPPORT_DIR.mkdir(parents=True, exist_ok=True)

        template_path = find_worker_template()
        if WORKER_SCRIPT_RUNTIME.exists() and WORKER_SCRIPT_RUNTIME.read_bytes() == template_path.read_bytes():
            return

        shutil.copy2(template_path, WORKER_SCRIPT_RUNTIME)

    def _prepare_runtime(self, status: Callable[[str], None]) -> None:
        SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
        self._sync_worker_script()

        try:
            python_path = get_venv_python()
        except FileNotFoundError:
            status("Creating local Python virtual environment...")
            base_python = shutil.which("python3") or sys.executable
            if not base_python:
                raise RuntimeError("python3 was not found.")

            venv_result = subprocess.run(
                [base_python, "-m", "venv", str(VENV_DIR)],
                capture_output=True,
                text=True,
            )
            if venv_result.returncode != 0:
                details = (venv_result.stderr or venv_result.stdout).strip()
                raise RuntimeError(f"Failed to create virtual environment.\n{details}")

            python_path = get_venv_python()

        check_result = subprocess.run(
            [str(python_path), "-c", "import faster_whisper, huggingface_hub"],
            capture_output=True,
            text=True,
        )
        if check_result.returncode == 0:
            return

        status("Installing Python dependencies (faster-whisper)...")

        subprocess.run(
            [str(python_path), "-m", "pip", "install", "--upgrade", "pip"],
            capture_output=True,
            text=True,
        )

        install_result = subprocess.run(
            [str(python_path), "-m", "pip", "install", "--upgrade", "faster-whisper", "huggingface_hub"],
            capture_output=True,
            text=True,
        )
        if install_result.returncode != 0:
            details = (install_result.stderr or install_result.stdout).strip()
            raise RuntimeError(f"Failed to install dependencies.\n{details}")

    def _worker_command(self, args: list[str]) -> list[str]:
        python_path = get_venv_python()
        return [str(python_path), str(WORKER_SCRIPT_RUNTIME), *args]

    def _run_worker(self, args: list[str]) -> tuple[subprocess.CompletedProcess[str], dict[str, Any] | None]:
        cmd = self._worker_command(args)
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=str(SUPPORT_DIR),
            env={**os.environ, "PYTHONUNBUFFERED": "1"},
        )
        payload = parse_last_json(result.stdout)
        return result, payload

    def _run_worker_streaming(
        self,
        args: list[str],
        on_payload: Callable[[dict[str, Any]], None],
    ) -> tuple[int, str]:
        cmd = self._worker_command(args)
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=str(SUPPORT_DIR),
            env={**os.environ, "PYTHONUNBUFFERED": "1"},
            bufsize=1,
        )

        assert process.stdout is not None
        assert process.stderr is not None

        for line in process.stdout:
            text = line.strip()
            if not text:
                continue
            try:
                payload = json.loads(text)
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict):
                on_payload(payload)

        stderr_output = process.stderr.read()
        exit_code = process.wait()
        return exit_code, stderr_output

    def _save_model_reference(self, reference: LocalModelReference) -> None:
        SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
        MODEL_REFERENCE_PATH.write_text(json.dumps(reference.__dict__, ensure_ascii=False, indent=2), encoding="utf-8")

    def _load_model_reference(self) -> None:
        if not MODEL_REFERENCE_PATH.exists():
            self.current_model = None
            self.model_status_var.set("Model is not connected")
            self.model_source_var.set("Available sources: " + " | ".join(MODEL_SOURCE_URLS))
            self.model_location_var.set("")
            self._refresh_controls()
            return

        try:
            payload = json.loads(MODEL_REFERENCE_PATH.read_text(encoding="utf-8"))
            reference = LocalModelReference(**payload)
        except Exception:  # noqa: BLE001
            self.current_model = None
            self.model_status_var.set("Model reference is corrupted")
            self.model_source_var.set("")
            self.model_location_var.set("")
            self._refresh_controls()
            return

        if not Path(reference.model_path).exists():
            self.current_model = None
            self.model_status_var.set("Model path does not exist")
            self.model_source_var.set("")
            self.model_location_var.set("")
            self._refresh_controls()
            return

        self.current_model = reference
        self.model_status_var.set(f"Connected: {reference.model_id}")
        self.model_location_var.set(reference.model_path)

        if reference.source_repo:
            self.model_source_var.set(f"Source: https://huggingface.co/{reference.source_repo}")
        else:
            self.model_source_var.set("Source: Local path")

        self._refresh_controls()

    def download_model(self) -> None:
        if self.is_busy:
            return

        destination = filedialog.askdirectory(
            title="Where to save the model",
            initialdir=str(DEFAULT_MODEL_DOWNLOAD_DIR),
        )
        if not destination:
            return

        self._reset_download_progress()

        def task() -> None:
            try:
                self._post_ui(self._set_status, "Preparing runtime...")
                self._prepare_runtime(lambda message: self._post_ui(self._set_status, message))

                final_payload: dict[str, Any] | None = None

                def on_payload(payload: dict[str, Any]) -> None:
                    nonlocal final_payload

                    if "ok" in payload:
                        final_payload = payload
                        return

                    event = payload.get("event")
                    if event == "source":
                        repo_id = str(payload.get("repo_id", ""))
                        self._post_ui(self.download_source_var.set, f"Downloading from: https://huggingface.co/{repo_id}")
                    elif event == "progress":
                        downloaded = int(payload.get("downloaded_bytes") or 0)
                        total_raw = payload.get("total_bytes")
                        total = int(total_raw) if isinstance(total_raw, int) and total_raw > 0 else None
                        self._post_ui(self._set_download_progress, downloaded, total)
                    elif event == "status":
                        self._post_ui(self._set_status, str(payload.get("message", "")))

                exit_code, stderr_output = self._run_worker_streaming(
                    [
                        "download",
                        "--output-dir",
                        str(Path(destination).expanduser().resolve()),
                        "--repo-id",
                        MODEL_REPO_CANDIDATES[0],
                        "--repo-id",
                        MODEL_REPO_CANDIDATES[1],
                    ],
                    on_payload,
                )

                if exit_code != 0 or not final_payload or not bool(final_payload.get("ok")):
                    details = ""
                    if final_payload and final_payload.get("details"):
                        details = str(final_payload.get("details"))
                    message = str(final_payload.get("error") if final_payload else "") or stderr_output.strip() or "Model download failed."
                    full_error = f"{message}\n{details}".strip()
                    raise RuntimeError(full_error)

                reference = LocalModelReference(
                    model_id=str(final_payload.get("model_id") or "unknown"),
                    model_path=str(final_payload.get("model_path") or ""),
                    source_type="downloaded",
                    source_repo=str(final_payload.get("repo_id") or ""),
                    configured_at=datetime.now(timezone.utc).isoformat(),
                )

                if not reference.model_path:
                    raise RuntimeError("Model path is missing in download response.")

                self._save_model_reference(reference)
                self._post_ui(self._set_status, "Model downloaded and connected.")
                self._post_ui(self._load_model_reference)
            finally:
                self._post_ui(self._reset_download_progress)

        self._run_in_background(task)

    def connect_local_model(self) -> None:
        if self.is_busy:
            return

        model_dir = filedialog.askdirectory(title="Select local model folder", initialdir=str(DEFAULT_MODEL_DOWNLOAD_DIR))
        if not model_dir:
            return

        model_path = str(Path(model_dir).expanduser().resolve())

        def task() -> None:
            self._post_ui(self._set_status, "Preparing runtime...")
            self._prepare_runtime(lambda message: self._post_ui(self._set_status, message))

            self._post_ui(self._set_status, "Validating local model...")

            result, payload = self._run_worker(["validate-model", "--model-path", model_path])
            if result.returncode != 0 or not payload or not bool(payload.get("ok")):
                details = str(payload.get("details") if payload else "")
                message = str(payload.get("error") if payload else "") or (result.stderr or result.stdout).strip() or "Failed to validate model."
                full_error = f"{message}\n{details}".strip()
                raise RuntimeError(full_error)

            reference = LocalModelReference(
                model_id=str(payload.get("model_id") or Path(model_path).name),
                model_path=model_path,
                source_type="linked",
                source_repo=None,
                configured_at=datetime.now(timezone.utc).isoformat(),
            )
            self._save_model_reference(reference)
            self._post_ui(self._load_model_reference)
            self._post_ui(self._set_status, "Local model connected.")

        self._run_in_background(task)

    def open_model_folder(self) -> None:
        if not self.current_model:
            return

        model_path = Path(self.current_model.model_path)
        if not model_path.exists():
            messagebox.showerror(APP_NAME, "Model path does not exist.")
            return

        opener = shutil.which("xdg-open")
        if not opener:
            messagebox.showinfo(APP_NAME, f"Open manually:\n{model_path}")
            return

        subprocess.Popen([opener, str(model_path)])

    def delete_model(self) -> None:
        if self.is_busy or not self.current_model:
            return

        reference = self.current_model

        if reference.source_type == "downloaded":
            prompt = "Delete downloaded model files from disk?"
        else:
            prompt = "Remove only model link (files on disk will stay)?"

        if not messagebox.askyesno(APP_NAME, prompt):
            return

        try:
            if reference.source_type == "downloaded":
                model_path = Path(reference.model_path)
                if model_path.exists() and model_path.is_dir():
                    shutil.rmtree(model_path)

            if MODEL_REFERENCE_PATH.exists():
                MODEL_REFERENCE_PATH.unlink()

            self._load_model_reference()
            self._set_status("Model removed.")
        except Exception as exc:  # noqa: BLE001
            self._show_error(str(exc))

    def choose_file(self) -> None:
        if self.is_busy:
            return

        file_path = filedialog.askopenfilename(title="Select audio/video file", filetypes=AUDIO_VIDEO_FILETYPES)
        if not file_path:
            return

        self.selected_file = Path(file_path)
        self.file_var.set(str(self.selected_file))
        self._set_status(f"Selected: {self.selected_file.name}")
        self._refresh_controls()

    def _extract_audio_with_ffmpeg(self, source: Path) -> Path:
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            raise RuntimeError("ffmpeg is required for video files. Install it first, for example: sudo apt install ffmpeg")

        fd, output_path = tempfile.mkstemp(prefix="gzwhisper-audio-", suffix=".m4a")
        os.close(fd)
        output = Path(output_path)

        result = subprocess.run(
            [ffmpeg, "-y", "-i", str(source), "-vn", "-acodec", "aac", str(output)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            details = (result.stderr or result.stdout).strip()
            try:
                output.unlink(missing_ok=True)
            except OSError:
                pass
            raise RuntimeError(f"Failed to extract audio from video.\n{details}")

        return output

    def transcribe_selected_file(self) -> None:
        if self.is_busy:
            return

        if not self.selected_file:
            messagebox.showerror(APP_NAME, "Select an audio/video file first.")
            return

        if not self.current_model:
            messagebox.showerror(APP_NAME, "Connect a model first.")
            return

        language_display = self.language_var.get()
        language_code = self.language_display_to_code.get(language_display, "auto")

        source_file = self.selected_file
        model_reference = self.current_model

        def task() -> None:
            self._post_ui(self._set_status, "Preparing runtime...")
            self._prepare_runtime(lambda message: self._post_ui(self._set_status, message))

            prepared_path = source_file
            should_cleanup = False

            try:
                if source_file.suffix.lower() in VIDEO_EXTENSIONS:
                    self._post_ui(self._set_status, "Extracting audio from video...")
                    prepared_path = self._extract_audio_with_ffmpeg(source_file)
                    should_cleanup = True

                self._post_ui(self._set_status, "Running local transcription...")

                args = [
                    "transcribe",
                    "--model-path",
                    model_reference.model_path,
                    "--model-id",
                    model_reference.model_id,
                    "--input",
                    str(prepared_path),
                ]
                if language_code != "auto":
                    args.extend(["--language", language_code])

                result, payload = self._run_worker(args)
                if result.returncode != 0 or not payload or not bool(payload.get("ok")):
                    details = str(payload.get("details") if payload else "")
                    message = str(payload.get("error") if payload else "") or (result.stderr or result.stdout).strip() or "Transcription failed."
                    full_error = f"{message}\n{details}".strip()
                    raise RuntimeError(full_error)

                text = str(payload.get("text") or "")
                model_id = str(payload.get("model_id") or model_reference.model_id)
                language = str(payload.get("language") or "-")
                raw_segments = payload.get("segments")
                segments: list[dict[str, Any]] = raw_segments if isinstance(raw_segments, list) else []

                self._post_ui(self._apply_transcription_result, text, model_id, language, segments)
                self._post_ui(self._set_status, "Transcription completed.")
            finally:
                if should_cleanup:
                    try:
                        prepared_path.unlink(missing_ok=True)
                    except OSError:
                        pass

        self._run_in_background(task)

    def _apply_transcription_result(
        self,
        text: str,
        model_id: str,
        language: str,
        segments: list[dict[str, Any]],
    ) -> None:
        self.text.delete("1.0", tk.END)
        self.text.insert("1.0", text)
        self.last_model_id = model_id
        self.detected_language = language or "-"
        self.detected_language_var.set(self.detected_language)
        self.last_segments = segments
        self._refresh_controls()

    def copy_all_text(self) -> None:
        value = self.text.get("1.0", tk.END).strip()
        if not value:
            return

        self.clipboard_clear()
        self.clipboard_append(value)
        self._set_status("Text copied to clipboard.")

    def save_txt(self) -> None:
        value = self.text.get("1.0", tk.END).strip()
        if not value:
            return

        destination = filedialog.asksaveasfilename(
            title="Save transcript as TXT",
            defaultextension=".txt",
            initialfile="transcript.txt",
            filetypes=[("Text", "*.txt"), ("All files", "*.*")],
        )
        if not destination:
            return

        Path(destination).write_text(value, encoding="utf-8")
        self._set_status(f"Saved: {destination}")

    def save_json(self) -> None:
        value = self.text.get("1.0", tk.END).strip()
        if not value:
            return

        destination = filedialog.asksaveasfilename(
            title="Save transcript as JSON",
            defaultextension=".json",
            initialfile="transcript.json",
            filetypes=[("JSON", "*.json"), ("All files", "*.*")],
        )
        if not destination:
            return

        payload: dict[str, Any] = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "text": value,
            "detected_language": self.detected_language,
            "segments": self.last_segments,
        }

        if self.selected_file:
            payload["source_file"] = str(self.selected_file)

        if self.last_model_id:
            payload["model_id"] = self.last_model_id

        if self.current_model:
            payload["model_path"] = self.current_model.model_path

        Path(destination).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        self._set_status(f"Saved: {destination}")


def main() -> int:
    app = GZWhisperLinuxApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
