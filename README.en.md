# Herdr Glow

**An ambient edge glow for when your Herdr agents need you.**

[한국어](README.md)

![Orange glow pulsing around the screen edges while a Herdr agent is blocked](assets/herdr-glow-demo.gif)

When a coding agent in [Herdr](https://herdr.dev) becomes `blocked` (waiting on an
approval or a question), Herdr Glow lights up the edges of your screen with a soft,
breathing glow. It sits on top of every Space and full-screen app (on the display you're using by default), and it
never takes clicks or keyboard focus.

It is built so you don't miss a prompt when you step away, without nagging you when
you are right there:

1. **Short pulse.** The moment an agent becomes blocked, the glow breathes twice
   (about 5.6 s) and fades out.
2. **Comes back when you're away.** If the agent is still blocked and you haven't
   touched the keyboard or mouse for 30 s, the glow returns and keeps breathing.
3. **Fades on input.** Touch the keyboard or mouse and it fades out. If you leave
   again while the agent is still blocked, it returns after another 30 s.
4. **Stops when unblocked.** It disappears once no agent is blocked, or when the
   blocked pane closes.

If you're already away when an agent blocks, it skips the short pulse and glows
straight away. With several blocked agents there is still just one glow, and it
stays until the last one is unblocked.

When an agent becomes blocked or done, a pill-shaped toast also appears at the
bottom center of the screen for 4 s, naming the agent (e.g. `herdr-glow · Claude  is done`).

## Quick start

Requirements:

- macOS
- A running [Herdr](https://herdr.dev) 0.9.0 or later
- Xcode Command Line Tools (`xcode-select --install`), used to compile the small Swift helper

```sh
herdr plugin install DevooKim/herdr-glow
```

That's all. The plugin builds its helper on install and starts reacting to agent
status changes right away. There are no actions or shortcuts to set up.

To remove it:

```sh
herdr plugin uninstall devookim.herdr-glow
```

## Turning it off

The glow turns off once no agent is blocked. If it sticks
around anyway, the `dismiss` action forces it off until an agent's status changes again.

```sh
herdr plugin action invoke devookim.herdr-glow.dismiss
```

To bind it to a key, add this to Herdr's `config.toml`:

```toml
[[keys.command]]
key = "prefix+g"
type = "plugin_action"
command = "devookim.herdr-glow.dismiss"
description = "dismiss glow"
```

## Try it out

Preview each status's glow and toast with your current `config.toml`. This doesn't touch real pane
state. A status with `pulse = 0` and `toast = false` only shows a "no glow, no toast" toast.

```sh
herdr plugin action invoke devookim.herdr-glow.demo-blocked
herdr plugin action invoke devookim.herdr-glow.demo-done
herdr plugin action invoke devookim.herdr-glow.demo-working
herdr plugin action invoke devookim.herdr-glow.demo-idle
```

## Click the toast

The toast stays for 4 seconds by default (`[toast] duration`). Click it to jump to that agent's pane (`herdr agent focus`; turn off with `[toast] click = false`).
Clicking the body also brings Herdr's host terminal app forward after switching panes. The terminal is identified using its inherited bundle identifier or executable path.
Successful navigation also fades out active glows. A glow watching for inactivity can return after the configured idle threshold when you step away again.
The **X** on the right dismisses the toast and fades out active glows without focusing Herdr. It works even when click navigation is disabled or no pane is associated with the toast. Inactivity monitoring continues, so the glow can return after the configured idle threshold when you step away again.
The toast's rim fills clockwise from the top center over its configured duration, then the toast fades out when the rim is full. Hovering anywhere on the toast, including X, brightens the rim and pauses both the gauge and dismissal timer. Clickable areas show a hand pointer. Leaving resumes the remaining time.
Demo toasts are clickable too and jump to the agent pane you're on, so you can try the click and hover effects.

## How it works

The plugin subscribes to Herdr's `pane.agent_status_changed`, `pane.closed`, and
`pane.exited` events. `bin/on-status-changed.sh` tracks which panes are blocked and
starts or stops `bin/glow`, a single-file Swift/AppKit helper (`src/glow.swift`). When a pane newly turns blocked or done it also shows `bin/toast` (`src/toast.swift`), which looks up the agent and workspace names with `herdr agent get` and `herdr workspace get`.

`glow` only runs while an agent is blocked. It draws a transparent, click-through
window with gradient edges, polls the system idle time once a second, and exits when
the hook sends it a signal. It needs no extra permissions. While running it uses
about 40 MB of memory and no measurable CPU.

## Customize

Open the settings popup with the `settings` action. Edit each status's pulse, idle
threshold, toast toggle and color, plus the shared glow and toast options, then
click **Save** to write `config.toml`. **Cancel** or closing the window discards edits.

The popup uses Korean when Korean is the preferred macOS language, and English
otherwise. Close and reopen the popup after changing the system language.

Click a status's color well to open the macOS color palette, choose a red, blue,
orange or green preset beside it, or enter a hex code directly. The color well
and hex code stay in sync; changes are written to the config file only on **Save**.

```sh
herdr plugin action invoke devookim.herdr-glow.settings
```

To open it with a shortcut, add this to Herdr's `config.toml`:

```toml
[[keys.command]]
key = "prefix+shift+g"
type = "plugin_action"
command = "devookim.herdr-glow.settings"
description = "Herdr Glow settings"
```

Invoking the action again brings the existing window forward. Saving preserves
comments and unrelated settings. If the file changes externally while the window
is open, reopen Settings to load those changes before saving.

You can also edit the file directly.

Put a `config.toml` in the plugin's config directory (`herdr plugin config-dir devookim.herdr-glow`,
usually `~/.config/herdr/plugins/config/devookim.herdr-glow/`). Write one section per status
(`blocked`, `done`, `working`, `idle`); anything you leave out uses the default.
Changes apply from the next event.

```toml
[done]
pulse = 3      # pulse for 3 s
idle = 0       # never come back on idle

[blocked]
pulse = 5      # pulse for 5 s
idle = 15      # come back after 15 s without input

[idle]
pulse = 2
toast = true
color = "8E8E93"

[glow]
width = 60
screen = "active"   # "active" = only the display under the mouse, "all" = every display

[toast]
duration = 4   # seconds the toast stays
click = true   # clicking it jumps to the pane
```

| Key | Meaning |
| --- | --- |
| `pulse` | Pulse length in seconds when a pane enters the status. `0` = no glow |
| `idle` | While the status lasts, glow again after this many seconds without input. `0` = never |
| `toast` | Show the toast (`true` / `false`) |
| `color` | Glow and toast dot color (`RRGGBB`) |
| `[glow] width` | Glow thickness in points |
| `[glow] screen` | Which displays glow. `active` lights only the display under the mouse when the glow starts, `all` lights every display. Default `active` |
| `[toast] duration` | Seconds the toast stays. Default `4` |
| `[toast] click` | Click the toast to jump to its pane (`true` / `false`). Default `true` |

| Status | `pulse` | `idle` | `toast` | `color` |
| --- | --- | --- | --- | --- |
| `blocked` | `5.6` | `30` | `true` | `FF8A1F` |
| `done` | `5.6` | `0` | `true` | `34C759` |
| `working` | `0` | `0` | `false` | `0A84FF` |
| `idle` | `0` | `0` | `false` | `8E8E93` |

When several statuses have `idle` above 0, priority is `blocked` → `done` → `working` → `idle`.

You can also run `glow` by hand. Stop it with `Ctrl+C` or `pkill glow`.

```sh
bin/glow --duration 0 --width 60
```

After editing `src/*.swift`, rebuild with:

```sh
swiftc -O src/glow.swift -o bin/glow && swiftc -O src/toast.swift -o bin/toast && swiftc -O src/settings.swift -o bin/settings
```

## Limitations

- macOS only. The overlay uses AppKit.
- The glow shows on the displays connected when it starts. With the default `screen = "active"` only the display under the mouse lights up.
- By default only `blocked` (orange) and `done` (green) react; see [Customize](#customize) to change any status. If another glow is already on, a new pulse is skipped and only the toast shows.

## License

MIT
