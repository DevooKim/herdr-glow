#!/bin/sh
# Triggered by herdr on pane.agent_status_changed / pane.closed / pane.exited.
# Keeps the edge glow on while at least one pane's agent is blocked.
DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="${TMPDIR:-/tmp}/herdr-glow"
mkdir -p "$STATE"
PANE="$(printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p')"
[ -n "$PANE" ] || exit 0
KEY="$(printf '%s' "$PANE" | tr -c 'A-Za-z0-9_-' '_')"

glow_alive() { [ -f "$STATE/glow.pid" ] && kill -0 "$(cat "$STATE/glow.pid")" 2>/dev/null; }

case "$HERDR_PLUGIN_EVENT_JSON" in
  *'"agent_status":"blocked"'*)
    : > "$STATE/blocked.$KEY"
    if ! glow_alive; then
      "$DIR/glow" --color FF8A1F --width 60 --watch --idle 30 --intro 5.6 >/dev/null 2>&1 &
      echo $! > "$STATE/glow.pid"
    fi ;;
  *)
    rm -f "$STATE/blocked.$KEY"
    if ! ls "$STATE"/blocked.* >/dev/null 2>&1 && glow_alive; then
      kill "$(cat "$STATE/glow.pid")" 2>/dev/null
      rm -f "$STATE/glow.pid"
    fi ;;
esac
