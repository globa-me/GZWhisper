# GZWhisper

Приложение для локальной транскрипции аудио/видео в текст.

## Что умеет

- UI в стиле текстового редактора.
- Если модель не найдена: две кнопки `Загрузить модель` и `Указать локальную`.
- Перед скачиванием приложение спрашивает папку назначения (по умолчанию `~/Documents/GZWhisper`).
- Показ прогресса скачивания: проценты, сколько уже загружено, сколько всего, текущий источник.
- Явно показывает URL источника модели (Hugging Face).
- Клик по плашке модели открывает папку модели в Finder.
- Красная кнопка корзины удаляет загруженную модель (или отвязывает внешнюю локальную).
- Выбор аудио и видео файлов.
- Авто-извлечение аудио из видео и отправка на транскрипцию.
- Полностью локальная транскрипция после загрузки модели.
- Копирование текста, сохранение в `TXT` и `JSON`.
- Подпись в интерфейсе: `Разработал Геннадий Захаров`.

## Linux-версия (установка)

В репозиторий добавлен Linux-аналог приложения: `linux/gzwhisper_linux.py`.

### Что нужно на Linux

- `python3`
- пакет `venv` для Python (обычно `python3-venv`)
- `tkinter` (обычно `python3-tk`)
- `ffmpeg` (для автоматического извлечения аудио из видео)

Пример для Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-tk ffmpeg
```

### Установка

```bash
./scripts/install_linux.sh
```

Скрипт установит launcher в `~/.local/bin/gzwhisper-linux` и desktop entry в `~/.local/share/applications`.

### Запуск

```bash
~/.local/bin/gzwhisper-linux
```

или просто `gzwhisper-linux`, если `~/.local/bin` уже в `PATH`.

### Удаление

```bash
./scripts/uninstall_linux.sh
```

### Linux-пакет для раздачи

```bash
./scripts/package_linux.sh
```

Архив:

`build/GZWhisper-linux.tar.gz`

## Сборка

```bash
./scripts/make_icon.sh
./scripts/build_app.sh
```

Готовое приложение:

`build/GZWhisper.app`

## ZIP для сайта

```bash
./scripts/package_zip.sh
```

Архив:

`build/GZWhisper-macOS.zip`

## Первый запуск

1. Если модель отсутствует, выберите `Загрузить модель` или `Указать локальную`.
2. При загрузке выберите папку для сохранения модели.
3. Приложение создаст локальное Python-окружение и установит `faster-whisper`.
4. После подключения модели можно добавлять аудио/видео и запускать транскрипцию.

## Важные примечания

- Все операции транскрипции выполняются локально после загрузки модели.
- Для первого запуска нужен интернет только чтобы скачать Python-зависимости и модель.
- Нужен установленный `python3` (системный `/usr/bin/python3` в macOS).

## Совместимость и релиз

- Сборка `GZWhisper` в `scripts/build_app.sh` теперь universal: `arm64 + x86_64`.
- Минимальная версия macOS задается переменной `MIN_MACOS_VERSION` (по умолчанию `13.0`).
- Для публичной раздачи через сайт рекомендуется подпись `Developer ID` + notarization, иначе Gatekeeper может блокировать запуск.

Подписанная сборка:

```bash
SIGNING_IDENTITY="Developer ID Application: YOUR_NAME (TEAMID)" ./scripts/build_app.sh
./scripts/package_zip.sh
```

## Временный обход для пользователя

- Кликабельный файл:
`build/Enable_GZWhisper.command`

Скрипт:
- при необходимости копирует `GZWhisper.app` в `/Applications`;
- выполняет `xattr -dr com.apple.quarantine`;
- добавляет приложение в локальный allow-list Gatekeeper;
- пытается запустить приложение.

## DMG-инсталлер

Сборка:

```bash
./scripts/build_dmg.sh
```

Готовый файл:

`build/GZWhisper-Installer.dmg`

Внутри DMG:
- `GZWhisper.app`
- ссылка на `/Applications`
- визуальный фон со стрелкой и подсказкой перетаскивания
- `Enable_GZWhisper.command`
- `Run_If_Blocked.txt` (fallback-команды для Terminal)
- `Install_Instructions.txt`

Если `.command` блокируется сообщением «повреждено», выполните команды из `Run_If_Blocked.txt` вручную в Terminal.

Минимальный ручной обход (если Gatekeeper блокирует запуск):

```bash
sudo xattr -dr com.apple.quarantine "/Volumes/GZWhisper Installer"
sudo xattr -dr com.apple.quarantine "/Applications/GZWhisper.app"
sudo spctl --add --label "GZWhisper Local" "/Applications/GZWhisper.app"
open "/Applications/GZWhisper.app"
```
