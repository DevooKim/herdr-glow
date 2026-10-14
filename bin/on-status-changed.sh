#!/bin/sh
# Triggered by herdr on pane.agent_status_changed / pane.closed / pane.exited.
# What each agent status does comes from config.toml in the plugin config dir,
# one section per status (blocked, done, idle, working):
#   pulse = SEC    pulse length when a pane enters the status (0 = no glow)
#   idle = SEC     while the status lasts, glow again after this much user idle time (0 = never)
#   toast = true | false
#   color = RRGGBB
#   [glow] width = PT, screen = active | all   which displays glow (active = the one under the mouse)
#   [toast] duration = SEC, click = true | false   how long the toast stays; click it to focus the pane
# When several statuses want to come back on idle, the first in $PRIORITY wins.
#   on-status-changed.sh dismiss   clear everything and turn the glow off
#   on-status-changed.sh demo STATUS   preview STATUS's pulse and toast with the current config
# On pane/tab/workspace focus, done panes you're now looking at count as seen.
DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="${TMPDIR:-/tmp}/herdr-glow"
PANES="$STATE/panes"
mkdir -p "$PANES"
PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin"
CONFIG="${HERDR_PLUGIN_CONFIG_DIR:-$HOME/.config/herdr/plugins/config/devookim.herdr-glow}/config.toml"
PRIORITY="blocked done working idle"

# cfg SECTION KEY DEFAULT: reads a flat `key = value` from a [section] of config.toml.
cfg() {
  v=""
  [ -f "$CONFIG" ] && v="$(awk -v s="[$1]" -v k="$2" '
    { sub(/[ \t]*#.*/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
    /^\[/ { in_s = ($0 == s); next }
    in_s && index($0, "=") {
      key = substr($0, 1, index($0, "=") - 1); gsub(/[ \t]+$/, "", key)
      if (key != k) next
      val = substr($0, index($0, "=") + 1); gsub(/^[ \t]+|"/, "", val)
      print val; exit
    }' "$CONFIG")"
  printf '%s' "${v:-$3}"
}

# Built-in defaults per status; config.toml overrides any of them.
pulse_of() { case "$1" in blocked|done) d=5.6 ;; *) d=0 ;; esac; cfg "$1" pulse "$d"; }
idle_of() { case "$1" in blocked) d=30 ;; *) d=0 ;; esac; cfg "$1" idle "$d"; }
toast_of() { case "$1" in blocked|done) d=true ;; *) d=false ;; esac; cfg "$1" toast "$d"; }
color_of() { case "$1" in blocked) d=FF8A1F ;; done) d=34C759 ;; working) d=0A84FF ;; *) d=8E8E93 ;; esac; cfg "$1" color "$d"; }
is_zero() { awk -v n="$1" 'BEGIN { exit !(n + 0 <= 0) }'; }
WIDTH="$(cfg glow width 60)"
SCREEN="$(cfg glow screen active)"
TOAST_DURATION="$(cfg toast duration 4)"
TOAST_CLICK="$(cfg toast click true)"

glow_alive() { [ -f "$STATE/glow.pid" ] && kill -0 "$(cat "$STATE/glow.pid")" 2>/dev/null; }
glow_stop() {
  glow_alive && kill "$(cat "$STATE/glow.pid")" 2>/dev/null
  rm -f "$STATE/glow.pid" "$STATE/glow.status"
}
toast_stop() { [ -f "$STATE/toast.pid" ] && kill "$(cat "$STATE/toast.pid")" 2>/dev/null; }

if [ "$1" = dismiss ]; then
  rm -f "$PANES"/*
  glow_stop
  toast_stop
  "$DIR/toast" --title "Herdr Glow" --subtitle "dismissed" --color 8E8E93 --duration 2 >/dev/null 2>&1 &
  echo $! > "$STATE/toast.pid"
  exit 0
fi

if [ "$1" = demo ]; then
  S="$2"
  case " $PRIORITY " in *" $S "*) ;; *) echo "usage: $0 demo blocked|done|working|idle" >&2; exit 1 ;; esac
  COLOR="$(color_of "$S")"
  PULSE="$(pulse_of "$S")"
  if is_zero "$PULSE" && [ "$(toast_of "$S")" != true ]; then
    # Nothing configured for this status; say so instead of silently doing nothing.
    toast_stop
    "$DIR/toast" --title "Herdr Glow · $S" --subtitle "no glow, no toast" --color "$COLOR" --duration 2 >/dev/null 2>&1 &
    echo $! > "$STATE/toast.pid"
    exit 0
  fi
  is_zero "$PULSE" || "$DIR/glow" --color "$COLOR" --width "$WIDTH" --screen "$SCREEN" --duration "$PULSE" >/dev/null 2>&1 &
  if [ "$(toast_of "$S")" = true ]; then
    toast_stop
    case "$S" in blocked) VERB="needs your input" ;; done) VERB="is done" ;; *) VERB="is $S" ;; esac
    # Clicking the demo toast focuses the agent pane you're on, so click and hover can be tried too.
    DEMO_PANE="$(herdr agent list 2>/dev/null | sed -n 's/.*"focused":true[^{}]*"pane_id":"\([^"]*\)".*/\1/p' | head -1)"
    "$DIR/toast" --title "Demo · Agent" --subtitle "$VERB" --color "$COLOR" --duration "$TOAST_DURATION" --pane "$DEMO_PANE" --click "$TOAST_CLICK" >/dev/null 2>&1 &
    echo $! > "$STATE/toast.pid"
  fi
  exit 0
fi

# Each pane file holds "STATUS PANE_ID".
case "$HERDR_PLUGIN_EVENT_JSON" in
  *'"pane.focused"'*|*'"tab.focused"'*|*'"workspace.focused"'*)
    # Focus events don't say which pane, so recheck every done pane.
    for f in "$PANES"/*; do
      [ -f "$f" ] || continue
      read -r S ID < "$f"
      [ "$S" = done ] || continue
      case "$(herdr agent get "$ID" 2>/dev/null)" in
        *'"agent_status":"done"'*'"focused":false'*) ;;
        *) rm -f "$f" ;;
      esac
    done ;;
  *)
    PANE="$(printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p')"
    [ -n "$PANE" ] || exit 0
    KEY="$(printf '%s' "$PANE" | tr -c 'A-Za-z0-9_-' '_')"
    NEW="$(printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | sed -n 's/.*"agent_status":"\([^"]*\)".*/\1/p')"
    OLD=""
    [ -f "$PANES/$KEY" ] && read -r OLD _ < "$PANES/$KEY"
    case " $PRIORITY " in *" $NEW "*) ;; *) NEW="" ;; esac
    if [ -z "$NEW" ]; then
      rm -f "$PANES/$KEY"
    elif [ "$NEW" != "$OLD" ]; then
      echo "$NEW $PANE" > "$PANES/$KEY"
      # Pulse and toast only when a pane newly enters the status.
      COLOR="$(color_of "$NEW")"
      # Statuses with idle > 0 get their pulse from the idle glow's intro below.
      if ! is_zero "$(pulse_of "$NEW")" && is_zero "$(idle_of "$NEW")" && ! glow_alive; then
        "$DIR/glow" --color "$COLOR" --width "$WIDTH" --screen "$SCREEN" --duration "$(pulse_of "$NEW")" >/dev/null 2>&1 &
      fi
      if [ "$(toast_of "$NEW")" = true ]; then
        toast_stop
        "$DIR/toast" --pane "$PANE" --status "$NEW" --color "$COLOR" --duration "$TOAST_DURATION" --click "$TOAST_CLICK" >/dev/null 2>&1 &
        echo $! > "$STATE/toast.pid"
      fi
    fi ;;
esac

# The idle glow follows the highest-priority status that has idle > 0 and a live pane.
WANT=""
for S in $PRIORITY; do
  is_zero "$(idle_of "$S")" && continue
  if grep -qs "^$S " "$PANES"/*; then WANT="$S"; break; fi
done

if [ -z "$WANT" ]; then
  glow_stop
elif ! glow_alive || [ "$(cat "$STATE/glow.status" 2>/dev/null)" != "$WANT" ]; then
  glow_stop
  PULSE="$(pulse_of "$WANT")"
  is_zero "$PULSE" && PULSE=0
  "$DIR/glow" --color "$(color_of "$WANT")" --width "$WIDTH" --screen "$SCREEN" --watch --idle "$(idle_of "$WANT")" --intro "$PULSE" >/dev/null 2>&1 &
  echo $! > "$STATE/glow.pid"
  echo "$WANT" > "$STATE/glow.status"
fi
