#!/usr/bin/env python3
import argparse
import json
import os
import sys
import threading
import time
from pathlib import Path

DEFAULT_REPO_CANDIDATES = [
    "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
    "SYSTRAN/faster-whisper-large-v3",
]


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def import_whisper_model():
    try:
        from faster_whisper import WhisperModel
    except Exception as exc:
        emit(
            {
                "ok": False,
                "error": "Не удалось импортировать faster-whisper. Установите зависимости через приложение.",
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
                "error": "Не удалось импортировать huggingface_hub.",
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
                    "message": f"Не удалось скачать {repo_id}, пробую следующий источник...",
                }
            )

    emit(
        {
            "ok": False,
            "error": "Не удалось скачать или инициализировать модель Whisper.",
            "details": last_error,
        }
    )
    sys.exit(1)


def cmd_validate_model(args):
    model_path = Path(args.model_path).expanduser().resolve()
    if not model_path.exists():
        emit({"ok": False, "error": f"Путь к модели не найден: {model_path}"})
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
                "error": "Указанная папка не выглядит как рабочая локальная модель faster-whisper.",
                "details": str(exc),
            }
        )
        sys.exit(1)


def cmd_transcribe(args):
    model_path = Path(args.model_path).expanduser().resolve()
    audio_path = Path(args.input).expanduser().resolve()

    if not audio_path.exists():
        emit({"ok": False, "error": f"Файл не найден: {audio_path}"})
        sys.exit(1)

    if not model_path.exists():
        emit({"ok": False, "error": f"Локальная модель не найдена: {model_path}"})
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
                "error": "Не удалось загрузить локальную модель.",
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

        items = []
        text_parts = []
        for seg in segments:
            seg_text = seg.text.strip()
            if seg_text:
                text_parts.append(seg_text)
            items.append({"start": seg.start, "end": seg.end, "text": seg_text})

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
                "error": "Ошибка во время транскрипции.",
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
