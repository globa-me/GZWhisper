#!/usr/bin/env bash
set -u

APP_NAME="GZWhisper.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_IN_APPS="/Applications/$APP_NAME"
APP_NEAR_SCRIPT="$SCRIPT_DIR/$APP_NAME"
TARGET_APP="$APP_IN_APPS"

locale_value="${GZWHISPER_UI_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}"

case "$locale_value" in
  ru*|RU*)
    TITLE="GZWhisper: локальная очистка quarantine для уже скопированного приложения"
    STEP1="1) Если приложения нет в /Applications, скопирует его туда (если оно рядом со скриптом)."
    STEP2="2) Снимет quarantine-атрибут только у копии приложения."
    STEP3="3) Попробует запустить приложение."
    STEP4="4) Если запуск все еще заблокирован, подскажет официальный путь через Privacy & Security."

    MSG_COPY_START="Приложение не найдено в /Applications. Копирую из DMG в /Applications..."
    MSG_COPY_FAIL="Не удалось скопировать приложение в /Applications."
    MSG_APP_NOT_FOUND="Приложение не найдено:"
    MSG_ENTER_PATH="Введите полный путь к GZWhisper.app: "
    MSG_PATH_NOT_FOUND="Путь к приложению не найден:"

    MSG_REMOVE_Q="Снимаю quarantine:"
    MSG_OPENING="Открываю приложение..."

    MSG_DONE_1="Готово. Если macOS все еще блокирует запуск, откройте приложение через:"
    MSG_DONE_2="Системные настройки -> Конфиденциальность и безопасность -> Все равно открыть"

    PROMPT_EXIT="Нажмите любую клавишу для выхода..."
    PROMPT_CLOSE="Нажмите любую клавишу, чтобы закрыть окно..."
    ;;

  zh*|ZH*)
    TITLE="GZWhisper：对已复制应用执行本地 quarantine 清理"
    STEP1="1) 如果 /Applications 中没有应用，会从脚本旁边复制过去。"
    STEP2="2) 仅移除应用副本的 quarantine 属性。"
    STEP3="3) 尝试启动应用。"
    STEP4="4) 如果仍被拦截，提示使用 Privacy & Security 中的官方放行方式。"

    MSG_COPY_START="在 /Applications 中未找到应用。正在从 DMG 复制到 /Applications..."
    MSG_COPY_FAIL="复制应用到 /Applications 失败。"
    MSG_APP_NOT_FOUND="未找到应用："
    MSG_ENTER_PATH="请输入 GZWhisper.app 的完整路径："
    MSG_PATH_NOT_FOUND="应用路径不存在："

    MSG_REMOVE_Q="正在移除 quarantine："
    MSG_OPENING="正在打开应用..."

    MSG_DONE_1="完成。如果 macOS 仍然阻止启动，请在以下位置手动允许："
    MSG_DONE_2="系统设置 -> 隐私与安全性 -> 仍要打开"

    PROMPT_EXIT="按任意键退出..."
    PROMPT_CLOSE="按任意键关闭窗口..."
    ;;

  *)
    TITLE="GZWhisper: local quarantine cleanup for the copied app"
    STEP1="1) If the app is missing in /Applications, copy it there (if it is next to this script)."
    STEP2="2) Remove quarantine from the copied app only."
    STEP3="3) Try to launch the app."
    STEP4="4) If it is still blocked, use the official Privacy & Security override."

    MSG_COPY_START="App not found in /Applications. Copying from DMG to /Applications..."
    MSG_COPY_FAIL="Failed to copy app into /Applications."
    MSG_APP_NOT_FOUND="App not found:"
    MSG_ENTER_PATH="Enter full path to GZWhisper.app: "
    MSG_PATH_NOT_FOUND="App path not found:"

    MSG_REMOVE_Q="Removing quarantine:"
    MSG_OPENING="Opening app..."

    MSG_DONE_1="Done. If macOS still blocks launch, open the app via:"
    MSG_DONE_2="System Settings -> Privacy & Security -> Open Anyway"

    PROMPT_EXIT="Press any key to exit..."
    PROMPT_CLOSE="Press any key to close this window..."
    ;;
esac

clear
cat <<TEXT
$TITLE

$STEP1
$STEP2
$STEP3
$STEP4
TEXT

echo
if [[ ! -d "$APP_IN_APPS" && -d "$APP_NEAR_SCRIPT" ]]; then
  echo "$MSG_COPY_START"
  if ! sudo /usr/bin/ditto "$APP_NEAR_SCRIPT" "$APP_IN_APPS"; then
    echo "$MSG_COPY_FAIL"
    read -n 1 -s -r -p "$PROMPT_EXIT"
    echo
    exit 1
  fi
fi

if [[ ! -d "$TARGET_APP" ]]; then
  echo "$MSG_APP_NOT_FOUND $TARGET_APP"
  read -r -p "$MSG_ENTER_PATH" CUSTOM_PATH
  TARGET_APP="$CUSTOM_PATH"
fi

if [[ ! -d "$TARGET_APP" ]]; then
  echo "$MSG_PATH_NOT_FOUND $TARGET_APP"
  read -n 1 -s -r -p "$PROMPT_EXIT"
  echo
  exit 1
fi

echo
echo "$MSG_REMOVE_Q $TARGET_APP"
sudo /usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" || true

echo "$MSG_OPENING"
open "$TARGET_APP"

echo
echo "$MSG_DONE_1"
echo "$MSG_DONE_2"
read -n 1 -s -r -p "$PROMPT_CLOSE"
echo
