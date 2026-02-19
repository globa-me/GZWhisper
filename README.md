# GZWhisper

GZWhisper — приложение для локальной расшифровки аудио и видео в текст.

Проект состоит из двух версий:
- `macOS` приложение на SwiftUI (`Sources/`)
- `Linux` приложение на Python/Tkinter (`linux/gzwhisper_linux.py`)

После подключения модели расшифровка выполняется полностью локально, без отправки медиа на внешние серверы.

## Что умеет

- Загрузка модели из Hugging Face или подключение уже скачанной локальной модели.
- Показ прогресса загрузки модели.
- Выбор аудио и видео файлов.
- Автоматическое извлечение аудио из видео.
- Транскрибация с автоопределением языка или ручным выбором языка.
- Копирование результата и сохранение в `TXT`/`JSON`.

## Быстрый старт (Linux)

### Зависимости

Fedora:

```bash
sudo dnf install -y python3 python3-pip python3-tkinter ffmpeg
```

Ubuntu / Debian:

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-tk ffmpeg
```

### Установка

```bash
./scripts/install_linux.sh
```

Установщик добавит:
- launcher: `~/.local/bin/gzwhisper-linux`
- desktop entry: `~/.local/share/applications/gzwhisper-linux.desktop`

### Запуск

```bash
gzwhisper-linux
```

Если команда не найдена:

```bash
~/.local/bin/gzwhisper-linux
```

### Удаление

```bash
./scripts/uninstall_linux.sh
```

### Архив для раздачи

```bash
./scripts/package_linux.sh
```

Результат: `build/GZWhisper-linux.tar.gz`

## Быстрый старт (macOS)

### Сборка приложения

```bash
./scripts/make_icon.sh
./scripts/build_app.sh
```

Результат: `build/GZWhisper.app`

### ZIP для сайта

```bash
./scripts/package_zip.sh
```

Результат: `build/GZWhisper-macOS.zip`

### DMG-инсталлер

```bash
./scripts/build_dmg.sh
```

Результат: `build/GZWhisper-Installer.dmg`

## Первый запуск

1. Открой приложение.
2. Если модель ещё не подключена, нажми `Загрузить модель` или `Указать локальную`.
3. Дождись подготовки Python-окружения и установки зависимостей (это делается один раз).
4. Выбери аудио/видео файл и запусти транскрибацию.

## Важные заметки

- Для первого запуска нужен интернет: скачать модель и Python-зависимости.
- Дальше можно работать офлайн (если модель уже есть локально).
- Для видео на Linux нужен `ffmpeg`.

## Структура проекта

- `Sources/` — macOS приложение (SwiftUI).
- `linux/` — Linux приложение (Tkinter).
- `Resources/transcription_worker.py` — общий Python worker для модели и транскрибации.
- `scripts/` — скрипты сборки, упаковки и установки.

## Лицензия

Лицензия пока не добавлена. Если нужно, можно быстро добавить MIT.
