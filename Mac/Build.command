#!/bin/zsh
cd "${0:A:h}"
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Нужны инструменты Apple Command Line Tools. Сейчас откроется установщик."
  xcode-select --install
  echo "После установки снова откройте Build.command."
else
  zsh ./build.sh
  result=$?
  if [[ $result -eq 0 ]]; then
    open ../Releases
  else
    echo "Сборка не завершена. Код ошибки: $result. Смотрите сообщение выше."
  fi
fi
echo "Нажмите Enter, чтобы закрыть окно."
read -r
