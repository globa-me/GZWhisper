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

APP_NAME = "GZWhisper"
APP_ID = "gzwhisper-linux"
MODEL_REPO_CANDIDATES = [
    "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
    "SYSTRAN/faster-whisper-large-v3",
]
MODEL_SOURCE_URLS = [f"https://huggingface.co/{repo}" for repo in MODEL_REPO_CANDIDATES]
VIDEO_EXTENSIONS = {".mp4", ".mkv", ".mov", ".avi", ".webm", ".m4v"}
SUPPORTED_UI_LANGS = {"en", "ru", "zh"}

TEXTS: dict[str, dict[str, str]] = {
    "en": {
        "header_subtitle": "Local audio and video transcription on your computer",
        "section_model": "Model",
        "section_input": "Input",
        "section_result": "Result",
        "label_source": "Source:",
        "label_path": "Path:",
        "label_language": "Language:",
        "label_detected": "Detected:",
        "btn_download_model": "Download model",
        "btn_connect_local": "Connect local",
        "btn_open_folder": "Open folder",
        "btn_delete_model": "Delete model",
        "btn_add_media": "Add audio/video",
        "btn_transcribe": "Transcribe",
        "btn_copy_all": "Copy all",
        "btn_save_txt": "Save TXT",
        "btn_save_json": "Save JSON",
        "lang_auto": "Auto",
        "lang_ru": "Russian",
        "lang_en": "English",
        "lang_zh": "Chinese",
        "filter_media": "Audio/Video",
        "filter_text": "Text",
        "filter_json": "JSON",
        "filter_all": "All files",
        "status_ready": "Ready",
        "status_error": "Error: {message}",
        "status_model_not_connected": "Model is not connected",
        "status_model_reference_corrupted": "Model reference is corrupted",
        "status_model_path_missing": "Model path does not exist",
        "status_connected_model": "Connected: {model_id}",
        "status_source_available": "Available sources: {sources}",
        "status_source": "Source: {source}",
        "status_source_local": "Source: local path",
        "text_file_not_selected": "No file selected",
        "status_preparing_runtime": "Preparing runtime...",
        "status_validating_model": "Validating local model...",
        "status_installing_deps": "Installing Python dependencies...",
        "status_model_downloaded": "Model downloaded and connected.",
        "status_model_connected": "Local model connected.",
        "status_model_removed": "Model removed.",
        "status_selected_file": "Selected: {name}",
        "status_extracting_audio": "Extracting audio from video...",
        "status_running_transcription": "Running local transcription...",
        "status_transcription_completed": "Transcription completed.",
        "status_copied": "Text copied to clipboard.",
        "status_saved": "Saved: {path}",
        "status_download_source": "Downloading from: {source}",
        "status_download_progress": "Downloaded: {downloaded} / {total} ({percent:.1f}%)",
        "status_downloaded_only": "Downloaded: {downloaded}",
        "dialog_choose_model_dir": "Where to save the model",
        "dialog_choose_local_model": "Select local model folder",
        "dialog_choose_media": "Select audio/video file",
        "dialog_save_txt": "Save transcript as TXT",
        "dialog_save_json": "Save transcript as JSON",
        "dialog_open_manual": "Open manually:\n{path}",
        "dialog_delete_downloaded": "Delete downloaded model files from disk?",
        "dialog_delete_linked": "Remove only model link (files on disk will stay)?",
        "error_worker_missing": "transcription_worker.py not found near application files.",
        "error_venv_python_missing": "Python executable in virtual environment was not found.",
        "error_python_missing": "python3 was not found.",
        "error_create_venv": "Failed to create virtual environment.\n{details}",
        "error_install_deps": "Failed to install dependencies.\n{details}",
        "error_model_download_failed": "Model download failed.",
        "error_model_path_missing": "Model path is missing in download response.",
        "error_validate_model_failed": "Failed to validate model.",
        "error_model_path_not_exists": "Model path does not exist.",
        "error_ffmpeg_required": "ffmpeg is required for video files. Install it first.",
        "error_extract_audio": "Failed to extract audio from video.\n{details}",
        "error_select_media_first": "Select an audio/video file first.",
        "error_connect_model_first": "Connect a model first.",
        "error_transcription_failed": "Transcription failed.",
    },
    "ru": {
        "header_subtitle": "Локальная транскрипция аудио и видео на вашем компьютере",
        "section_model": "Модель",
        "section_input": "Файл",
        "section_result": "Результат",
        "label_source": "Источник:",
        "label_path": "Путь:",
        "label_language": "Язык:",
        "label_detected": "Определен:",
        "btn_download_model": "Загрузить модель",
        "btn_connect_local": "Подключить локальную",
        "btn_open_folder": "Открыть папку",
        "btn_delete_model": "Удалить модель",
        "btn_add_media": "Добавить аудио/видео",
        "btn_transcribe": "Транскрибировать",
        "btn_copy_all": "Скопировать все",
        "btn_save_txt": "Сохранить TXT",
        "btn_save_json": "Сохранить JSON",
        "lang_auto": "Авто",
        "lang_ru": "Русский",
        "lang_en": "Английский",
        "lang_zh": "Китайский",
        "filter_media": "Аудио/Видео",
        "filter_text": "Текст",
        "filter_json": "JSON",
        "filter_all": "Все файлы",
        "status_ready": "Готово",
        "status_error": "Ошибка: {message}",
        "status_model_not_connected": "Модель не подключена",
        "status_model_reference_corrupted": "Файл привязки модели поврежден",
        "status_model_path_missing": "Путь к модели не существует",
        "status_connected_model": "Подключена: {model_id}",
        "status_source_available": "Доступные источники: {sources}",
        "status_source": "Источник: {source}",
        "status_source_local": "Источник: локальный путь",
        "text_file_not_selected": "Файл не выбран",
        "status_preparing_runtime": "Подготовка окружения...",
        "status_validating_model": "Проверяю локальную модель...",
        "status_installing_deps": "Устанавливаю Python-зависимости...",
        "status_model_downloaded": "Модель загружена и подключена.",
        "status_model_connected": "Локальная модель подключена.",
        "status_model_removed": "Модель удалена.",
        "status_selected_file": "Выбран файл: {name}",
        "status_extracting_audio": "Извлекаю аудио из видео...",
        "status_running_transcription": "Выполняю локальную транскрипцию...",
        "status_transcription_completed": "Транскрипция завершена.",
        "status_copied": "Текст скопирован в буфер обмена.",
        "status_saved": "Сохранено: {path}",
        "status_download_source": "Скачиваю из: {source}",
        "status_download_progress": "Загружено: {downloaded} / {total} ({percent:.1f}%)",
        "status_downloaded_only": "Загружено: {downloaded}",
        "dialog_choose_model_dir": "Куда сохранить модель",
        "dialog_choose_local_model": "Выберите папку локальной модели",
        "dialog_choose_media": "Выберите аудио/видео файл",
        "dialog_save_txt": "Сохранить транскрипцию в TXT",
        "dialog_save_json": "Сохранить транскрипцию в JSON",
        "dialog_open_manual": "Откройте вручную:\n{path}",
        "dialog_delete_downloaded": "Удалить скачанные файлы модели с диска?",
        "dialog_delete_linked": "Удалить только привязку (файлы на диске останутся)?",
        "error_worker_missing": "Файл transcription_worker.py не найден рядом с приложением.",
        "error_venv_python_missing": "Python в виртуальном окружении не найден.",
        "error_python_missing": "python3 не найден.",
        "error_create_venv": "Не удалось создать виртуальное окружение.\n{details}",
        "error_install_deps": "Не удалось установить зависимости.\n{details}",
        "error_model_download_failed": "Не удалось скачать модель.",
        "error_model_path_missing": "В ответе нет пути к модели.",
        "error_validate_model_failed": "Не удалось проверить модель.",
        "error_model_path_not_exists": "Путь к модели не существует.",
        "error_ffmpeg_required": "Для видео нужен ffmpeg. Установите его перед запуском.",
        "error_extract_audio": "Не удалось извлечь аудио из видео.\n{details}",
        "error_select_media_first": "Сначала выберите аудио/видео файл.",
        "error_connect_model_first": "Сначала подключите модель.",
        "error_transcription_failed": "Ошибка транскрипции.",
    },
    "zh": {
        "header_subtitle": "在您的电脑上进行本地音视频转写",
        "section_model": "模型",
        "section_input": "输入",
        "section_result": "结果",
        "label_source": "来源：",
        "label_path": "路径：",
        "label_language": "语言：",
        "label_detected": "识别：",
        "btn_download_model": "下载模型",
        "btn_connect_local": "连接本地模型",
        "btn_open_folder": "打开文件夹",
        "btn_delete_model": "删除模型",
        "btn_add_media": "添加音频/视频",
        "btn_transcribe": "开始转写",
        "btn_copy_all": "复制全部",
        "btn_save_txt": "保存 TXT",
        "btn_save_json": "保存 JSON",
        "lang_auto": "自动",
        "lang_ru": "俄语",
        "lang_en": "英语",
        "lang_zh": "中文",
        "filter_media": "音频/视频",
        "filter_text": "文本",
        "filter_json": "JSON",
        "filter_all": "所有文件",
        "status_ready": "就绪",
        "status_error": "错误：{message}",
        "status_model_not_connected": "模型未连接",
        "status_model_reference_corrupted": "模型引用文件已损坏",
        "status_model_path_missing": "模型路径不存在",
        "status_connected_model": "已连接：{model_id}",
        "status_source_available": "可用来源：{sources}",
        "status_source": "来源：{source}",
        "status_source_local": "来源：本地路径",
        "text_file_not_selected": "未选择文件",
        "status_preparing_runtime": "正在准备环境...",
        "status_validating_model": "正在验证本地模型...",
        "status_installing_deps": "正在安装 Python 依赖...",
        "status_model_downloaded": "模型已下载并连接。",
        "status_model_connected": "本地模型已连接。",
        "status_model_removed": "模型已删除。",
        "status_selected_file": "已选择：{name}",
        "status_extracting_audio": "正在从视频提取音频...",
        "status_running_transcription": "正在执行本地转写...",
        "status_transcription_completed": "转写完成。",
        "status_copied": "文本已复制到剪贴板。",
        "status_saved": "已保存：{path}",
        "status_download_source": "下载来源：{source}",
        "status_download_progress": "已下载：{downloaded} / {total} ({percent:.1f}%)",
        "status_downloaded_only": "已下载：{downloaded}",
        "dialog_choose_model_dir": "选择模型保存位置",
        "dialog_choose_local_model": "选择本地模型文件夹",
        "dialog_choose_media": "选择音频/视频文件",
        "dialog_save_txt": "将转写结果保存为 TXT",
        "dialog_save_json": "将转写结果保存为 JSON",
        "dialog_open_manual": "请手动打开：\n{path}",
        "dialog_delete_downloaded": "是否删除磁盘上的模型文件？",
        "dialog_delete_linked": "仅删除模型链接（保留磁盘文件）？",
        "error_worker_missing": "在应用附近未找到 transcription_worker.py。",
        "error_venv_python_missing": "未找到虚拟环境中的 Python 可执行文件。",
        "error_python_missing": "未找到 python3。",
        "error_create_venv": "创建虚拟环境失败。\n{details}",
        "error_install_deps": "安装依赖失败。\n{details}",
        "error_model_download_failed": "模型下载失败。",
        "error_model_path_missing": "下载结果中缺少模型路径。",
        "error_validate_model_failed": "模型校验失败。",
        "error_model_path_not_exists": "模型路径不存在。",
        "error_ffmpeg_required": "视频文件需要 ffmpeg，请先安装。",
        "error_extract_audio": "从视频提取音频失败。\n{details}",
        "error_select_media_first": "请先选择音频/视频文件。",
        "error_connect_model_first": "请先连接模型。",
        "error_transcription_failed": "转写失败。",
    },
}


@dataclass
class LocalModelReference:
    model_id: str
    model_path: str
    source_type: str
    source_repo: str | None
    configured_at: str


def detect_ui_lang() -> str:
    for candidate in (
        os.environ.get("GZWHISPER_UI_LANG"),
        os.environ.get("LC_ALL"),
        os.environ.get("LC_MESSAGES"),
        os.environ.get("LANG"),
    ):
        if not candidate:
            continue
        code = candidate.split(".", 1)[0].lower()
        if code.startswith("ru"):
            return "ru"
        if code.startswith("zh"):
            return "zh"
    return "en"


def tr(lang: str, key: str, **kwargs: Any) -> str:
    template = TEXTS.get(lang, TEXTS["en"]).get(key, TEXTS["en"].get(key, key))
    if kwargs:
        return template.format(**kwargs)
    return template


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

    raise FileNotFoundError(tr(detect_ui_lang(), "error_worker_missing"))


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

    raise FileNotFoundError(tr(detect_ui_lang(), "error_venv_python_missing"))


class GZWhisperLinuxApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()

        self.ui_lang = detect_ui_lang()
        self.worker_lang = self.ui_lang if self.ui_lang in SUPPORTED_UI_LANGS else "en"

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

        self.language_options = [
            (self.t("lang_auto"), "auto"),
            (self.t("lang_ru"), "ru"),
            (self.t("lang_en"), "en"),
            (self.t("lang_zh"), "zh"),
        ]
        self.language_display_to_code = {display: code for display, code in self.language_options}
        self.language_code_to_display = {code: display for display, code in self.language_options}

        self.model_status_var = tk.StringVar(value=self.t("status_model_not_connected"))
        self.model_source_var = tk.StringVar(value="")
        self.model_location_var = tk.StringVar(value="")
        self.file_var = tk.StringVar(value=self.t("text_file_not_selected"))
        self.status_var = tk.StringVar(value=self.t("status_ready"))
        self.download_source_var = tk.StringVar(value="")
        self.download_progress_var = tk.StringVar(value="")
        self.detected_language_var = tk.StringVar(value="-")
        self.language_var = tk.StringVar(value=self.language_code_to_display["auto"])

        self._build_ui()
        self._load_model_reference()
        self._drain_ui_queue()

    def t(self, key: str, **kwargs: Any) -> str:
        return tr(self.ui_lang, key, **kwargs)

    def _filetypes_media(self) -> list[tuple[str, str]]:
        return [
            (
                self.t("filter_media"),
                "*.mp3 *.wav *.m4a *.aac *.flac *.ogg *.opus *.mp4 *.mkv *.mov *.avi *.webm *.m4v",
            ),
            (self.t("filter_all"), "*.*"),
        ]

    def _build_ui(self) -> None:
        outer = ttk.Frame(self, padding=16)
        outer.pack(fill=tk.BOTH, expand=True)

        header = ttk.Frame(outer)
        header.pack(fill=tk.X)

        ttk.Label(header, text=APP_NAME, font=("TkDefaultFont", 20, "bold")).pack(anchor=tk.W)
        ttk.Label(header, text=self.t("header_subtitle")).pack(anchor=tk.W, pady=(2, 0))

        model_frame = ttk.LabelFrame(outer, text=self.t("section_model"), padding=12)
        model_frame.pack(fill=tk.X, pady=(14, 8))

        ttk.Label(model_frame, textvariable=self.model_status_var).grid(row=0, column=0, sticky="w")

        self.btn_download_model = ttk.Button(model_frame, text=self.t("btn_download_model"), command=self.download_model)
        self.btn_download_model.grid(row=0, column=1, padx=(8, 0), sticky="e")

        self.btn_connect_model = ttk.Button(model_frame, text=self.t("btn_connect_local"), command=self.connect_local_model)
        self.btn_connect_model.grid(row=0, column=2, padx=(8, 0), sticky="e")

        self.btn_open_model = ttk.Button(model_frame, text=self.t("btn_open_folder"), command=self.open_model_folder)
        self.btn_open_model.grid(row=0, column=3, padx=(8, 0), sticky="e")

        self.btn_delete_model = ttk.Button(model_frame, text=self.t("btn_delete_model"), command=self.delete_model)
        self.btn_delete_model.grid(row=0, column=4, padx=(8, 0), sticky="e")

        ttk.Label(model_frame, text=self.t("label_source")).grid(row=1, column=0, sticky="w", pady=(8, 0))
        ttk.Label(model_frame, textvariable=self.model_source_var).grid(row=1, column=1, columnspan=4, sticky="w", pady=(8, 0))

        ttk.Label(model_frame, text=self.t("label_path")).grid(row=2, column=0, sticky="w", pady=(2, 0))
        ttk.Label(model_frame, textvariable=self.model_location_var).grid(row=2, column=1, columnspan=4, sticky="w", pady=(2, 0))

        ttk.Label(model_frame, textvariable=self.download_source_var).grid(row=3, column=0, columnspan=5, sticky="w", pady=(8, 0))

        self.progress_bar = ttk.Progressbar(model_frame, mode="determinate", maximum=100)
        self.progress_bar.grid(row=4, column=0, columnspan=5, sticky="ew", pady=(4, 0))

        ttk.Label(model_frame, textvariable=self.download_progress_var).grid(row=5, column=0, columnspan=5, sticky="w", pady=(2, 0))

        model_frame.columnconfigure(0, weight=1)

        file_frame = ttk.LabelFrame(outer, text=self.t("section_input"), padding=12)
        file_frame.pack(fill=tk.X, pady=(4, 8))

        self.btn_choose_file = ttk.Button(file_frame, text=self.t("btn_add_media"), command=self.choose_file)
        self.btn_choose_file.grid(row=0, column=0, sticky="w")

        ttk.Label(file_frame, textvariable=self.file_var).grid(row=0, column=1, sticky="w", padx=(10, 0))

        ttk.Label(file_frame, text=self.t("label_language")).grid(row=1, column=0, sticky="w", pady=(10, 0))

        self.language_combo = ttk.Combobox(
            file_frame,
            state="readonly",
            values=[display for display, _ in self.language_options],
            textvariable=self.language_var,
            width=18,
        )
        self.language_combo.grid(row=1, column=1, sticky="w", pady=(10, 0))

        ttk.Label(file_frame, text=self.t("label_detected")).grid(row=1, column=2, sticky="e", padx=(20, 6), pady=(10, 0))
        ttk.Label(file_frame, textvariable=self.detected_language_var).grid(row=1, column=3, sticky="w", pady=(10, 0))

        self.btn_transcribe = ttk.Button(file_frame, text=self.t("btn_transcribe"), command=self.transcribe_selected_file)
        self.btn_transcribe.grid(row=1, column=4, sticky="e", padx=(10, 0), pady=(10, 0))

        file_frame.columnconfigure(1, weight=1)

        output_frame = ttk.LabelFrame(outer, text=self.t("section_result"), padding=12)
        output_frame.pack(fill=tk.BOTH, expand=True)

        top_row = ttk.Frame(output_frame)
        top_row.pack(fill=tk.X, pady=(0, 8))

        self.btn_copy = ttk.Button(top_row, text=self.t("btn_copy_all"), command=self.copy_all_text)
        self.btn_copy.pack(side=tk.LEFT)

        self.btn_save_txt = ttk.Button(top_row, text=self.t("btn_save_txt"), command=self.save_txt)
        self.btn_save_txt.pack(side=tk.LEFT, padx=(8, 0))

        self.btn_save_json = ttk.Button(top_row, text=self.t("btn_save_json"), command=self.save_json)
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
                self.t(
                    "status_download_progress",
                    downloaded=format_bytes(downloaded),
                    total=format_bytes(total),
                    percent=percent,
                )
            )
            return

        if self.progress_bar.cget("mode") != "indeterminate":
            self.progress_bar.configure(mode="indeterminate", value=0)
            self.progress_bar.start(12)

        self.download_progress_var.set(self.t("status_downloaded_only", downloaded=format_bytes(downloaded)))

    def _reset_download_progress(self) -> None:
        self.progress_bar.stop()
        self.progress_bar.configure(mode="determinate", value=0)
        self.download_source_var.set("")
        self.download_progress_var.set("")

    def _show_error(self, message: str) -> None:
        self._set_status(self.t("status_error", message=message))
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
            status(self.t("status_preparing_runtime"))
            base_python = shutil.which("python3") or sys.executable
            if not base_python:
                raise RuntimeError(self.t("error_python_missing"))

            venv_result = subprocess.run(
                [base_python, "-m", "venv", str(VENV_DIR)],
                capture_output=True,
                text=True,
            )
            if venv_result.returncode != 0:
                details = (venv_result.stderr or venv_result.stdout).strip()
                raise RuntimeError(self.t("error_create_venv", details=details))

            python_path = get_venv_python()

        check_result = subprocess.run(
            [str(python_path), "-c", "import faster_whisper, huggingface_hub"],
            capture_output=True,
            text=True,
        )
        if check_result.returncode == 0:
            return

        status(self.t("status_installing_deps"))

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
            raise RuntimeError(self.t("error_install_deps", details=details))

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
            env={
                **os.environ,
                "PYTHONUNBUFFERED": "1",
                "GZWHISPER_UI_LANG": self.worker_lang,
            },
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
            env={
                **os.environ,
                "PYTHONUNBUFFERED": "1",
                "GZWHISPER_UI_LANG": self.worker_lang,
            },
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
            self.model_status_var.set(self.t("status_model_not_connected"))
            self.model_source_var.set(self.t("status_source_available", sources=" | ".join(MODEL_SOURCE_URLS)))
            self.model_location_var.set("")
            self._refresh_controls()
            return

        try:
            payload = json.loads(MODEL_REFERENCE_PATH.read_text(encoding="utf-8"))
            reference = LocalModelReference(**payload)
        except Exception:  # noqa: BLE001
            self.current_model = None
            self.model_status_var.set(self.t("status_model_reference_corrupted"))
            self.model_source_var.set("")
            self.model_location_var.set("")
            self._refresh_controls()
            return

        if not Path(reference.model_path).exists():
            self.current_model = None
            self.model_status_var.set(self.t("status_model_path_missing"))
            self.model_source_var.set("")
            self.model_location_var.set("")
            self._refresh_controls()
            return

        self.current_model = reference
        self.model_status_var.set(self.t("status_connected_model", model_id=reference.model_id))
        self.model_location_var.set(reference.model_path)

        if reference.source_repo:
            self.model_source_var.set(self.t("status_source", source=f"https://huggingface.co/{reference.source_repo}"))
        else:
            self.model_source_var.set(self.t("status_source_local"))

        self._refresh_controls()

    def download_model(self) -> None:
        if self.is_busy:
            return

        destination = filedialog.askdirectory(
            title=self.t("dialog_choose_model_dir"),
            initialdir=str(DEFAULT_MODEL_DOWNLOAD_DIR),
        )
        if not destination:
            return

        self._reset_download_progress()

        def task() -> None:
            try:
                self._post_ui(self._set_status, self.t("status_preparing_runtime"))
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
                        self._post_ui(self.download_source_var.set, self.t("status_download_source", source=f"https://huggingface.co/{repo_id}"))
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
                    message = str(final_payload.get("error") if final_payload else "") or stderr_output.strip() or self.t("error_model_download_failed")
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
                    raise RuntimeError(self.t("error_model_path_missing"))

                self._save_model_reference(reference)
                self._post_ui(self._set_status, self.t("status_model_downloaded"))
                self._post_ui(self._load_model_reference)
            finally:
                self._post_ui(self._reset_download_progress)

        self._run_in_background(task)

    def connect_local_model(self) -> None:
        if self.is_busy:
            return

        model_dir = filedialog.askdirectory(title=self.t("dialog_choose_local_model"), initialdir=str(DEFAULT_MODEL_DOWNLOAD_DIR))
        if not model_dir:
            return

        model_path = str(Path(model_dir).expanduser().resolve())

        def task() -> None:
            self._post_ui(self._set_status, self.t("status_validating_model"))
            self._prepare_runtime(lambda message: self._post_ui(self._set_status, message))

            self._post_ui(self._set_status, self.t("status_preparing_runtime"))

            result, payload = self._run_worker(["validate-model", "--model-path", model_path])
            if result.returncode != 0 or not payload or not bool(payload.get("ok")):
                details = str(payload.get("details") if payload else "")
                message = str(payload.get("error") if payload else "") or (result.stderr or result.stdout).strip() or self.t("error_validate_model_failed")
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
            self._post_ui(self._set_status, self.t("status_model_connected"))

        self._run_in_background(task)

    def open_model_folder(self) -> None:
        if not self.current_model:
            return

        model_path = Path(self.current_model.model_path)
        if not model_path.exists():
            messagebox.showerror(APP_NAME, self.t("error_model_path_not_exists"))
            return

        opener = shutil.which("xdg-open")
        if not opener:
            messagebox.showinfo(APP_NAME, self.t("dialog_open_manual", path=model_path))
            return

        subprocess.Popen([opener, str(model_path)])

    def delete_model(self) -> None:
        if self.is_busy or not self.current_model:
            return

        reference = self.current_model

        if reference.source_type == "downloaded":
            prompt = self.t("dialog_delete_downloaded")
        else:
            prompt = self.t("dialog_delete_linked")

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
            self._set_status(self.t("status_model_removed"))
        except Exception as exc:  # noqa: BLE001
            self._show_error(str(exc))

    def choose_file(self) -> None:
        if self.is_busy:
            return

        file_path = filedialog.askopenfilename(title=self.t("dialog_choose_media"), filetypes=self._filetypes_media())
        if not file_path:
            return

        self.selected_file = Path(file_path)
        self.file_var.set(str(self.selected_file))
        self._set_status(self.t("status_selected_file", name=self.selected_file.name))
        self._refresh_controls()

    def _extract_audio_with_ffmpeg(self, source: Path) -> Path:
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            raise RuntimeError(self.t("error_ffmpeg_required"))

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
            raise RuntimeError(self.t("error_extract_audio", details=details))

        return output

    def transcribe_selected_file(self) -> None:
        if self.is_busy:
            return

        if not self.selected_file:
            messagebox.showerror(APP_NAME, self.t("error_select_media_first"))
            return

        if not self.current_model:
            messagebox.showerror(APP_NAME, self.t("error_connect_model_first"))
            return

        language_display = self.language_var.get()
        language_code = self.language_display_to_code.get(language_display, "auto")

        source_file = self.selected_file
        model_reference = self.current_model

        def task() -> None:
            self._post_ui(self._set_status, self.t("status_preparing_runtime"))
            self._prepare_runtime(lambda message: self._post_ui(self._set_status, message))

            prepared_path = source_file
            should_cleanup = False

            try:
                if source_file.suffix.lower() in VIDEO_EXTENSIONS:
                    self._post_ui(self._set_status, self.t("status_extracting_audio"))
                    prepared_path = self._extract_audio_with_ffmpeg(source_file)
                    should_cleanup = True

                self._post_ui(self._set_status, self.t("status_running_transcription"))

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
                    message = str(payload.get("error") if payload else "") or (result.stderr or result.stdout).strip() or self.t("error_transcription_failed")
                    full_error = f"{message}\n{details}".strip()
                    raise RuntimeError(full_error)

                text = str(payload.get("text") or "")
                model_id = str(payload.get("model_id") or model_reference.model_id)
                language = str(payload.get("language") or "-")
                raw_segments = payload.get("segments")
                segments: list[dict[str, Any]] = raw_segments if isinstance(raw_segments, list) else []

                self._post_ui(self._apply_transcription_result, text, model_id, language, segments)
                self._post_ui(self._set_status, self.t("status_transcription_completed"))
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
        self._set_status(self.t("status_copied"))

    def save_txt(self) -> None:
        value = self.text.get("1.0", tk.END).strip()
        if not value:
            return

        destination = filedialog.asksaveasfilename(
            title=self.t("dialog_save_txt"),
            defaultextension=".txt",
            initialfile="transcript.txt",
            filetypes=[(self.t("filter_text"), "*.txt"), (self.t("filter_all"), "*.*")],
        )
        if not destination:
            return

        Path(destination).write_text(value, encoding="utf-8")
        self._set_status(self.t("status_saved", path=destination))

    def save_json(self) -> None:
        value = self.text.get("1.0", tk.END).strip()
        if not value:
            return

        destination = filedialog.asksaveasfilename(
            title=self.t("dialog_save_json"),
            defaultextension=".json",
            initialfile="transcript.json",
            filetypes=[(self.t("filter_json"), "*.json"), (self.t("filter_all"), "*.*")],
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
        self._set_status(self.t("status_saved", path=destination))


def main() -> int:
    app = GZWhisperLinuxApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
