#!/usr/bin/env bash
set -u

APP_NAME="GZWhisper.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_IN_APPS="/Applications/$APP_NAME"
APP_NEAR_SCRIPT="$SCRIPT_DIR/$APP_NAME"
TARGET_APP="$APP_IN_APPS"

clear
cat <<'TEXT'
GZWhisper: временный обход ограничений macOS (Gatekeeper/quarantine)

Скрипт сделает:
1) Если приложения нет в /Applications, скопирует его туда (если оно рядом со скриптом).
2) Снимет quarantine-атрибут.
3) Добавит приложение в локальный allow-list Gatekeeper.
4) Запустит приложение.
TEXT

echo
if [[ ! -d "$APP_IN_APPS" && -d "$APP_NEAR_SCRIPT" ]]; then
  echo "Приложение не найдено в /Applications. Копирую из DMG в /Applications..."
  if ! sudo /usr/bin/ditto "$APP_NEAR_SCRIPT" "$APP_IN_APPS"; then
    echo "Не удалось скопировать приложение в /Applications."
    read -n 1 -s -r -p "Нажмите любую клавишу для выхода..."
    echo
    exit 1
  fi
fi

if [[ ! -d "$TARGET_APP" ]]; then
  echo "Приложение не найдено: $TARGET_APP"
  read -r -p "Введите полный путь к GZWhisper.app: " CUSTOM_PATH
  TARGET_APP="$CUSTOM_PATH"
fi

if [[ ! -d "$TARGET_APP" ]]; then
  echo "Путь к приложению не найден: $TARGET_APP"
  read -n 1 -s -r -p "Нажмите любую клавишу для выхода..."
  echo
  exit 1
fi

echo
echo "Снимаю quarantine: $TARGET_APP"
sudo /usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" || true

echo "Добавляю приложение в локальный allow-list Gatekeeper"
sudo /usr/sbin/spctl --add --label "GZWhisper Local" "$TARGET_APP" || true

echo "Открываю приложение..."
open "$TARGET_APP"

echo
echo "Готово. Если macOS все еще блокирует запуск, откройте приложение через:"
echo "Системные настройки -> Конфиденциальность и безопасность -> Все равно открыть"
read -n 1 -s -r -p "Нажмите любую клавишу, чтобы закрыть окно..."
echo
