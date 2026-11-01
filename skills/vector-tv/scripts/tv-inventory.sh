#!/usr/bin/env bash
# tv-inventory.sh — снять инвентарь Android TV по ADB и восстановить отключённое.
#
#   tv-inventory.sh inventory 192.168.1.50 [5555]
#   tv-inventory.sh restore   192.168.1.50 tv-inventory-2026-11-01T18-00/
#
# Что делает inventory: подключается, снимает список включённых и отключённых пакетов,
# кто отвечает HOME, настройки анимаций, ключевые свойства и версию Android. Пишет всё
# в каталог рядом — это и есть бэкап, к которому возвращает restore.
#
# Ничего не отключает и не устанавливает: только читает. Отключение — руками или
# промптом из SKILL.md, по списку, который владелец подтвердил.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  tv-inventory.sh inventory <tv-ip> [port]      снять бэкап в ./tv-inventory-<метка>/
  tv-inventory.sh restore   <tv-ip> <каталог>   включить обратно всё из disabled.txt
EOF
  exit 2
}

[ $# -ge 2 ] || usage
MODE=$1; HOST=$2; PORT=${3:-5555}
case "$MODE" in inventory|restore) ;; *) usage ;; esac

need() { command -v "$1" >/dev/null 2>&1 || { echo "нет $1 в PATH" >&2; exit 1; }; }
need adb

say() { printf '%s\n' "$*" >&2; }

connect() {
  say "→ adb connect ${HOST}:${PORT}"
  adb connect "${HOST}:${PORT}" >/dev/null 2>&1 || true
  # ждём device до 20 с: после connect телевизор ещё спрашивает «Allow USB debugging?»
  for _ in $(seq 1 20); do
    state=$(adb -s "${HOST}:${PORT}" get-state 2>/dev/null || true)
    [ "$state" = "device" ] && return 0
    [ "$state" = "unauthorized" ] && {
      say "телевизор ждёт подтверждения: на экране «Разрешить отладку по USB?» — нажмите Разрешить"
    }
    sleep 1
  done
  say "не удалось подключиться к ${HOST}:${PORT}."
  say "проверьте: Developer options → USB debugging включён; TV и компьютер в одной сети;"
  say "на Android 11+ беспроводная отладка требует сопряжения: adb pair ${HOST}:<порт из окна сопряжения>"
  exit 1
}

sh_() { adb -s "${HOST}:${PORT}" shell "$@"; }

case "$MODE" in
inventory)
  connect
  OUT="tv-inventory-$(date +%Y-%m-%dT%H-%M)"
  mkdir -p "$OUT"
  say "→ снимаю в $OUT"

  sh_ 'pm list packages -e' | tr -d '\r' | sed 's/^package://' | sort > "$OUT/enabled.txt"
  sh_ 'pm list packages -d' | tr -d '\r' | sed 's/^package://' | sort > "$OUT/disabled.txt"
  sh_ 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME' \
    | tr -d '\r' > "$OUT/home.txt"
  sh_ 'getprop ro.build.version.release; getprop ro.product.model; getprop ro.product.brand; getprop ro.adb.secure' \
    | tr -d '\r' > "$OUT/props.txt"
  {
    for k in window_animation_scale transition_animation_scale animator_duration_scale; do
      printf '%s=%s\n' "$k" "$(sh_ "settings get global $k" | tr -d '\r')"
    done
  } > "$OUT/animation.txt"

  ENABLED=$(wc -l < "$OUT/enabled.txt")
  DISABLED=$(wc -l < "$OUT/disabled.txt")
  HOME_LINE=$(tail -n +2 "$OUT/home.txt" | tr -d ' ' | head -1)
  SECURE=$(sed -n '4p' "$OUT/props.txt")
  say ""
  say "модель:        $(sed -n '2p' "$OUT/props.txt")"
  say "Android:       $(sed -n '1p' "$OUT/props.txt")"
  say "пакетов:       включено $ENABLED, отключено $DISABLED"
  say "HOME отвечает: ${HOME_LINE:-не ответил}"
  if [ "${SECURE:-}" = "0" ]; then
    say "ВНИМАНИЕ: ro.adb.secure=0 — порт ${PORT} даёт shell любому в сети без подтверждения."
    say "          после работы выключите отладку в Developer options."
  fi
  say ""
  say "бэкап: $OUT"
  ;;

restore)
  [ $# -ge 3 ] || usage
  DIR=$3
  [ -d "$DIR" ] || { say "нет каталога $DIR"; exit 2; }
  [ -s "$DIR/disabled.txt" ] || { say "в $DIR/disabled.txt пусто — восстанавливать нечего"; exit 2; }
  connect
  # enabled.txt — что было включено ДО. Всё, чего в нём нет и что сейчас отключено, включаем.
  FAILED=0
  while read -r pkg; do
    [ -n "$pkg" ] || continue
    if grep -qx "$pkg" "$DIR/enabled.txt" 2>/dev/null; then
      continue   # было отключено и до нас — не трогаем
    fi
    if sh_ "pm enable --user 0 $pkg" >/dev/null 2>&1; then
      say "включён: $pkg"
    else
      say "НЕ включился: $pkg"; FAILED=$((FAILED+1))
    fi
  done < <(sh_ 'pm list packages -d' | tr -d '\r' | sed 's/^package://' | sort)
  say ""
  say "готово, ошибок: $FAILED"
  say "HOME сейчас: $(sh_ 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME' | tail -1 | tr -d '\r')"
  [ "$FAILED" -eq 0 ] || exit 1
  ;;
esac
