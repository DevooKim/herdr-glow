#!/bin/sh
# Triggered by herdr on pane.agent_status_changed / pane.closed / pane.exited.
# Keeps the edge glow on while at least one pane's agent is blocked (orange)
# or done (green). blocked takes priority over done.
DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="${TMPDIR:-/tmp}/herdr-glow"
mkdir -p "$STATE"
PANE="$(printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p')"
[ -n "$PANE" ] || exit 0
KEY="$(printf '%s' "$PANE" | tr -c 'A-Za-z0-9_-' '_')"

BLOCKED_COLOR=FF8A1F
DONE_COLOR=34C759

glow_alive() { [ -f "$STATE/glow.pid" ] && kill -0 "$(cat "$STATE/glow.pid")" 2>/dev/null; }
glow_stop() {
  glow_alive && kill "$(cat "$STATE/glow.pid")" 2>/dev/null
  rm -f "$STATE/glow.pid" "$STATE/glow.color"
}

# Shows which agent changed, but only when a pane newly enters blocked/done.
toast() {
  [ -f "$STATE/$1.$KEY" ] && return
  [ -f "$STATE/toast.pid" ] && kill "$(cat "$STATE/toast.pid")" 2>/dev/null
  "$DIR/toast" --pane "$PANE" --status "$1" --color "$2" >/dev/null 2>&1 &
  echo $! > "$STATE/toast.pid"
}

case "$HERDR_PLUGIN_EVENT_JSON" in
  *'"agent_status":"blocked"'*) toast blocked "$BLOCKED_COLOR"; NEW=blocked ;;
  *'"agent_status":"done"'*) toast done "$DONE_COLOR"; NEW=done ;;
  *) NEW="" ;;
esac
rm -f "$STATE/blocked.$KEY" "$STATE/done.$KEY"
[ -n "$NEW" ] && : > "$STATE/$NEW.$KEY"

if ls "$STATE"/blocked.* >/dev/null 2>&1; then
  WANT="$BLOCKED_COLOR"
elif ls "$STATE"/done.* >/dev/null 2>&1; then
  WANT="$DONE_COLOR"
else
  WANT=""
fi

if [ -z "$WANT" ]; then
  glow_stop
elif ! glow_alive || [ "$(cat "$STATE/glow.color" 2>/dev/null)" != "$WANT" ]; then
  glow_stop
  "$DIR/glow" --color "$WANT" --width 60 --watch --idle 30 --intro 5.6 >/dev/null 2>&1 &
  echo $! > "$STATE/glow.pid"
  echo "$WANT" > "$STATE/glow.color"
fi
