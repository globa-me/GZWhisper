#!/usr/bin/env python3
import argparse
import json
import os
import sys
import threading
from pathlib import Path

DEFAULT_REPO_CANDIDATES = [
    "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
    "SYSTRAN/faster-whisper-large-v3",
]

TEXTS = {
    "en": {
        "import_whisper_failed": "Failed to import faster-whisper. Please install dependencies through the app.",
        "import_hf_failed": "Failed to import huggingface_hub.",
        "download_try_next": "Failed to download {repo_id}, trying the next source...",
        "download_failed": "Failed to download or initialize Whisper model.",
        "model_path_not_found": "Model path was not found: {path}",
        "invalid_local_model": "The selected folder does not look like a valid faster-whisper local model.",
        "file_not_found": "File was not found: {path}",
        "local_model_not_found": "Local model was not found: {path}",
        "load_local_model_failed": "Failed to load local model.",
        "transcription_failed": "Transcription failed.",
    },
    "ru": {
        "import_whisper_failed": "Не удалось импортировать faster-whisper. Установите зависимости через приложение.",
        "import_hf_failed": "Не удалось импортировать huggingface_hub.",
        "download_try_next": "Не удалось скачать {repo_id}, пробую следующий источник...",
        "download_failed": "Не удалось скачать или инициализировать модель Whisper.",
        "model_path_not_found": "Путь к модели не найден: {path}",
        "invalid_local_model": "Указанная папка не выглядит как рабочая локальная модель faster-whisper.",
        "file_not_found": "Файл не найден: {path}",
        "local_model_not_found": "Локальная модель не найдена: {path}",
        "load_local_model_failed": "Не удалось загрузить локальную модель.",
        "transcription_failed": "Ошибка во время транскрипции.",
    },
    "zh": {
        "import_whisper_failed": "无法导入 faster-whisper。请通过应用安装依赖。",
        "import_hf_failed": "无法导入 huggingface_hub。",
        "download_try_next": "下载 {repo_id} 失败，正在尝试下一个来源...",
        "download_failed": "下载或初始化 Whisper 模型失败。",
        "model_path_not_found": "未找到模型路径：{path}",
        "invalid_local_model": "所选文件夹不是有效的 faster-whisper 本地模型。",
        "file_not_found": "未找到文件：{path}",
        "local_model_not_found": "未找到本地模型：{path}",
        "load_local_model_failed": "加载本地模型失败。",
        "transcription_failed": "转写失败。",
    },
}


def detect_lang() -> str:
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


UI_LANG = detect_lang()


def t(key: str, **kwargs):
    template = TEXTS.get(UI_LANG, TEXTS["en"]).get(key, TEXTS["en"].get(key, key))
    if kwargs:
        return template.format(**kwargs)
    return template


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def import_whisper_model():
    try:
        from faster_whisper import WhisperModel
    except Exception as exc:
        emit(
            {
                "ok": False,
                "error": t("import_whisper_failed"),
                "details": str(exc),
            }
        )
        sys.exit(2)
    return WhisperModel


def safe_directory_size(path: Path) -> int:
    total = 0
    if not path.exists():
        return total

    for entry in path.rglob("*"):
        if not entry.is_file():
            continue
        try:
            total += entry.stat().st_size
        except OSError:
            continue
    return total


def get_total_repo_size(repo_id: str):
    try:
        from huggingface_hub import HfApi

        api = HfApi()
        info = api.model_info(repo_id=repo_id, files_metadata=True)
        total = 0
        for sibling in info.siblings or []:
            size = getattr(sibling, "size", None)
            if isinstance(size, int):
                total += size
        return total if total > 0 else None
    except Exception:
        return None


def validate_model_locally(whisper_model_cls, model_path: Path):
    model = whisper_model_cls(
        str(model_path),
        device="auto",
        compute_type="int8",
        local_files_only=True,
    )
    del model


def cmd_download(args):
    try:
        from huggingface_hub import snapshot_download
        from huggingface_hub.utils import disable_progress_bars

        disable_progress_bars()
    except Exception as exc:
        emit(
            {
                "ok": False,
                "error": t("import_hf_failed"),
                "details": str(exc),
            }
        )
        sys.exit(2)

    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    WhisperModel = import_whisper_model()

    candidates = args.repo_id or DEFAULT_REPO_CANDIDATES
    last_error = None

    for repo_id in candidates:
        source_url = f"https://huggingface.co/{repo_id}"
        emit({"event": "source", "repo_id": repo_id, "url": source_url})

        target_dir = output_dir / repo_id.replace("/", "--")
        target_dir.mkdir(parents=True, exist_ok=True)

        total_bytes = get_total_repo_size(repo_id)
        stop_event = threading.Event()

        def report_progress():
            last_value = -1
            while not stop_event.wait(0.5):
                downloaded = safe_directory_size(target_dir)
                if downloaded != last_value:
                    emit(
                        {
                            "event": "progress",
                            "repo_id": repo_id,
                            "downloaded_bytes": downloaded,
                            "total_bytes": total_bytes,
                        }
                    )
                    last_value = downloaded

        reporter = threading.Thread(target=report_progress, daemon=True)
        reporter.start()

        try:
            snapshot_download(
                repo_id=repo_id,
                local_dir=str(target_dir),
                resume_download=True,
                local_files_only=False,
            )

            stop_event.set()
            reporter.join(timeout=1.0)

            downloaded = safe_directory_size(target_dir)
            emit(
                {
                    "event": "progress",
                    "repo_id": repo_id,
                    "downloaded_bytes": downloaded,
                    "total_bytes": total_bytes,
                }
            )

            validate_model_locally(WhisperModel, target_dir)

            emit(
                {
                    "ok": True,
                    "model_id": repo_id,
                    "model_path": str(target_dir),
                    "repo_id": repo_id,
                    "source_url": source_url,
                }
            )
            return
        except Exception as exc:
            stop_event.set()
            reporter.join(timeout=1.0)
            last_error = str(exc)
            emit(
                {
                    "event": "status",
                    "message": t("download_try_next", repo_id=repo_id),
                }
            )

    emit(
        {
            "ok": False,
            "error": t("download_failed"),
            "details": last_error,
        }
    )
    sys.exit(1)


def cmd_validate_model(args):
    model_path = Path(args.model_path).expanduser().resolve()
    if not model_path.exists():
        emit({"ok": False, "error": t("model_path_not_found", path=model_path)})
        sys.exit(1)

    WhisperModel = import_whisper_model()

    try:
        validate_model_locally(WhisperModel, model_path)
        model_id = args.model_id or model_path.name
        emit(
            {
                "ok": True,
                "model_id": model_id,
                "model_path": str(model_path),
            }
        )
    except Exception as exc:
        emit(
            {
                "ok": False,
                "error": t("invalid_local_model"),
                "details": str(exc),
            }
        )
        sys.exit(1)


def cmd_transcribe(args):
    model_path = Path(args.model_path).expanduser().resolve()
    audio_path = Path(args.input).expanduser().resolve()

    if not audio_path.exists():
        emit({"ok": False, "error": t("file_not_found", path=audio_path)})
        sys.exit(1)

    if not model_path.exists():
        emit({"ok": False, "error": t("local_model_not_found", path=model_path)})
        sys.exit(1)

    WhisperModel = import_whisper_model()

    try:
        model = WhisperModel(
            str(model_path),
            device="auto",
            compute_type="int8",
            local_files_only=True,
        )
    except Exception as exc:
        emit(
            {
                "ok": False,
                "error": t("load_local_model_failed"),
                "details": str(exc),
            }
        )
        sys.exit(1)

    try:
        segments, info = model.transcribe(
            str(audio_path),
            beam_size=5,
            vad_filter=True,
            language=args.language,
        )

        total_seconds_raw = getattr(info, "duration", None)
        try:
            total_seconds = float(total_seconds_raw) if total_seconds_raw is not None else None
        except Exception:
            total_seconds = None

        items = []
        text_parts = []
        processed_seconds = 0.0
        for seg in segments:
            seg_text = seg.text.strip()
            if seg_text:
                text_parts.append(seg_text)
            items.append({"start": seg.start, "end": seg.end, "text": seg_text})

            try:
                seg_end = float(seg.end)
                if seg_end > processed_seconds:
                    processed_seconds = seg_end
            except Exception:
                pass

            emit(
                {
                    "event": "progress",
                    "processed_seconds": processed_seconds,
                    "total_seconds": total_seconds,
                }
            )

        full_text = "\n".join(text_parts)
        payload = {
            "ok": True,
            "model_id": args.model_id or model_path.name,
            "language": getattr(info, "language", None),
            "duration": getattr(info, "duration", None),
            "text": full_text,
            "segments": items,
        }
        emit(payload)
    except Exception as exc:
        emit(
            {
                "ok": False,
                "error": t("transcription_failed"),
                "details": str(exc),
            }
        )
        sys.exit(1)


def build_parser():
    parser = argparse.ArgumentParser(prog="transcription_worker")
    subparsers = parser.add_subparsers(dest="command", required=True)

    p_download = subparsers.add_parser("download", help="download whisper model")
    p_download.add_argument("--output-dir", required=True)
    p_download.add_argument("--repo-id", action="append", default=[])
    p_download.set_defaults(func=cmd_download)

    p_validate = subparsers.add_parser("validate-model", help="validate local model directory")
    p_validate.add_argument("--model-path", required=True)
    p_validate.add_argument("--model-id", default=None)
    p_validate.set_defaults(func=cmd_validate_model)

    p_transcribe = subparsers.add_parser("transcribe", help="transcribe media file")
    p_transcribe.add_argument("--model-path", required=True)
    p_transcribe.add_argument("--model-id", default=None)
    p_transcribe.add_argument("--input", required=True)
    p_transcribe.add_argument("--language", default=None)
    p_transcribe.set_defaults(func=cmd_transcribe)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
