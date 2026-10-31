# Zephyrus Duo keyboard plugin — working plan

Work through this in separate sessions. Update the checkboxes in [Status](#status) before you stop, including a line under [Session notes](#session-notes) that says what changed and what to do next.

Session 1 is in the tree: `bin/zephyrus-duo-keyboard`, `systemd/zephyrus-duo-keyboard.service`, and `tests/dock-osk.sh`. The bar card, README, and manifest are still the upstream Z13 plugin. Do not enable the user service, and do not run `omarchy plugin enable`, until Session 4.

## How to resume

1. Read this file. Do not re-investigate the machine unless a fact in [Measured on this machine](#measured-on-this-machine) looks stale (connector names move with the GPU mux; re-run `zephyrus-duo-panels`).
2. Do the next unchecked session. A session may finish more than one block if the checks pass. Do not start Session 4 until Sessions 1–3 are checked.
3. Leave `~/.config/hypr/` alone. Rotation, panel power, and touch mapping stay in the scripts named below.
4. Do not commit unless asked.

## Decisions already made

- Rotation is not this plugin's job. `~/.local/bin/zephyrus-duo-rotate` and `~/.config/hypr/local/Zephyrus.lua` already turn both panels.
- The plugin is renamed so it can sit next to upstream `alanroman117.tablet-mode` (the ROG Flow Z13 plugin). It must not share that id, the `tablet-mode` command, or the `omarchy-tablet-mode` unit.
- Lifting the magnetic keyboard does not show the on-screen keyboard. This desk uses a Corne with both panels up. Seating the keyboard hides it.
- Touch tweaks stay off. `oled-gap-shift` animates `gaps_out`.

## What this plugin will do

An Omarchy bar widget and a user service that show the already-installed `wvkbd-deskus` keyboard on the bottom panel.

- Docked means USB product `1ce6` is present (`0b05:1ce6`), the same test as `zephyrus-duo-dock`. That is the keyboard seated on the bottom panel. Lifted, that id is absent and the keyboard is Bluetooth instead.
- `1ce6` appears: hide the on-screen keyboard. The existing dock script is what powers the bottom panel off. This plugin does not.
- `1ce6` disappears: do not change visibility, unless `show_keyboard=true`. The default is `false`, so a lift leaves the keyboard hidden. `show_keyboard=true` is the one-line switch that shows it on every lift. Implement that flag. Do not turn it on.
- `zephyrus-duo-keyboard on`, `off`, and `osk show|hide|toggle` change visibility until the next time `1ce6` appears, which hides it. They do not rotate anything.
- Pin `wvkbd-deskus --output` to the bottom connector from `zephyrus-duo-panels`. If `bottom` is empty (booted while docked, so the panel was never detected), use `top`. After a Hyprland reload, if the keyboard was visible, show it again on the current bottom connector.
- The floating button is on both internal screens, and only while the keyboard is lifted.

Never use USB id `0b05:1a30` (Z13 keyboard) or `0b05:193b` (ITE embedded controller, always present). The Bluetooth modalias `usb:v0B05p1CE7` is not the dock id. The dock id is `1ce6`.

## What this plugin will not do

- No `monitor-sensor` and no `ClaimAccelerometer`. `zephyrus-duo-rotate` already holds `net.hadess.SensorProxy`.
- No `hl.monitor` and no `hl.device`. No rotation, rotation lock, or calibrate.
- No logind sleep delay lock and no `systemd-inhibit`. Hiding the on-screen keyboard on suspend is fine. Do not release or restart the accelerometer.
- No changes to `gaps_out`, `gaps_in`, or `extend_border_grab_area`.
- No edits under `~/.config/hypr/`. Do not change `Zephyrus.lua`.

`restore` / `ExecStopPost` only hide and stop `wvkbd`. They must not unrotate or restore gap records. Those code paths have to be unreachable, not merely unused by the widget.

## Measured on this machine

Checked 2026-10-31. Re-check connector names before Session 4.

- Machine: ASUS ROG Zephyrus Duo GX651AX (2026). Intel Panther Lake + NVIDIA RTX 5090 Max-Q. Omarchy `4.0.0.r7481`, Hyprland `0.57.0`.
- Panels: two Samsung ATNA60HR07-0, 2880×1800 @ 120 Hz, scale 2. `zephyrus-duo-panels` printed `top=eDP-1 bottom=eDP-2 top_backlight=intel_backlight bottom_backlight=card0-eDP-2-backlight`. Layout while `normal`: top `0x0`, bottom `0x900`.
- Orientation file: `$XDG_RUNTIME_DIR/zephyrus-duo-orientation` contained `normal`.
- `1ce6` was not on the USB bus. Bluetooth device `Zephyrus Duo Keyboard` `C9:1B:81:3C:4C:6E` was paired and disconnected. The Corne was connected.
- Touch, already mapped by `Zephyrus.lua`: `elan9008:00-04f3:451d` (+ stylus) on the top panel, `elan9009:00-04f3:451e` (+ stylus) on the bottom. Do not map them again.
- Installed and idle: `iio-sensor-proxy`, `wvkbd-deskus` 0.20-7 (`--output` works). Not installed: this plugin. No `~/.config/omarchy/tablet-mode.conf`.
- `zephyrus-duo-rotate` was running (Python, claims the sensor proxy). Also launched from `Zephyrus.lua`: `zephyrus-duo-dock`, `zephyrus-duo-brightness-sync`, `zephyrus-duo-power-hint`, `oled-gap-shift`.

`Zephyrus.lua` layouts, for context only (do not reimplement):

| Orientation | Transform | Top | Bottom |
|---|---|---|---|
| `normal` | 0 | `0x0` | `0x900` |
| `bottom-up` | 2 | `0x900` | `0x0` |
| `left-up` | 1 | `900x0` | `0x0` |
| `right-up` | 3 | `0x0` | `900x0` |

Docked forces the laptop layout and disables the bottom panel. A dock or a lift runs `hyprctl reload`. A rotation while lifted also runs `hyprctl reload`. The on-screen keyboard has to be re-shown after those reloads or it vanishes when the machine turns.

## Names

Omarchy plugin ids match `^[A-Za-z0-9][A-Za-z0-9._-]*$` and must not start with `omarchy.`.

| | Z13 (do not keep) | This fork |
|---|---|---|
| Plugin id | `alanroman117.tablet-mode` | `brogers.zephyrus-duo-keyboard` |
| Display name | Tablet Mode (ROG Flow Z13) | Zephyrus Duo Keyboard |
| Command | `tablet-mode` | `zephyrus-duo-keyboard` |
| User service | `omarchy-tablet-mode.service` | `zephyrus-duo-keyboard.service` |
| Settings | `~/.config/omarchy/tablet-mode.conf` | `~/.config/omarchy/zephyrus-duo-keyboard.conf` |
| Runtime dir | `$XDG_RUNTIME_DIR/omarchy-tablet-mode` | `$XDG_RUNTIME_DIR/zephyrus-duo-keyboard` |
| State dir | `~/.local/state/omarchy-tablet-mode` | `~/.local/state/zephyrus-duo-keyboard` |
| Theme hook | `hooks/theme-set.d/tablet-mode.sh` | `hooks/theme-set.d/zephyrus-duo-keyboard.sh` |
| IPC / `moduleName` | `alanroman117.tablet-mode` | `brogers.zephyrus-duo-keyboard` |
| Layer namespace | `tablet-mode-keyboard-button` | `zephyrus-duo-keyboard-button` |

Manifest `author` becomes `brogers`. Keep the MIT license and Alan Roman's copyright. Credit the Z13 plugin as the source in the README.

Menu markers, `PLUGIN_ID`, and the widget `ipcTarget` follow the new id. Rename `bin/tablet-mode` to `bin/zephyrus-duo-keyboard` and `systemd/omarchy-tablet-mode.service` to `systemd/zephyrus-duo-keyboard.service`. Nothing is installed under the old names on this machine, so there is no config to migrate.

Default config written by enable:

```
enabled=true
keyboard=0b05:1ce6
auto_rotate=false
show_keyboard=false
touch_tweaks=false
```

`keyboard=0b05:1ce6` means seated while that id is on the bus. It does not mean "detached, so enter tablet mode."

## Status

- [x] Session 1 — Daemon no longer touches displays or the accelerometer
- [x] Session 2 — Bar card matches the new behavior
- [x] Session 3 — README and manifest describe this fork
- [x] Session 4 — Live check on this session's machine

## Session 1 — Daemon no longer touches displays or the accelerometer

Files: `bin/tablet-mode` (rename), `systemd/omarchy-tablet-mode.service` (rename). A small fixture script under `tests/` is new.

Rename the identifiers in the table above inside the script and the unit. Then make these paths unreachable from the daemon and from the command line:

- `start_reader sensor`, `sensor_sync` claiming the sensor, `cmd__sensor_reader`
- `inhibit_take` and any `systemd-inhibit` sleep lock
- `rotate_to`, `unrotate`, `map_touch`, `unmap_touch`, `reapply` when it calls those
- `tweaks_apply`, `tweaks_restore`
- commands `rotate`, `lock`, `calibrate` (refuse with a short message that names `zephyrus-duo-rotate`)

Dock handling replaces `enter_tablet` / `enter_laptop`:

- USB reader stays. `on_usb_settled`: if `1ce6` is present, `osk_hide`. If it is absent, hide or show only according to `show_keyboard`. Do not call `hyprctl eval` with `hl.monitor` or `hl.device`.
- `osk_output` is `bottom` from `eval "$(zephyrus-duo-panels)"`, else `top`. Refuse a name that is not a connector token (`^[A-Za-z0-9._-]+$`).
- On `configreloaded`, if the keyboard was visible, `osk_show` again on the resolved output. Nothing else.
- `restore_live` stops `wvkbd` only.
- `doctor` checks: `wvkbd-deskus` is installed, `zephyrus-duo-panels` returns a top panel, `zephyrus-duo-rotate` is running, this process has no `monitor-sensor` child, and `keyboard` is `0b05:1ce6`. It prints seated or lifted, and the output it would pin to.
- `status --json` includes `dock` (`seated` or `lifted`) and `osk_output`.

The script can already be sourced (`BASH_SOURCE` guard) and it already honors `TABLET_MODE_DRYRUN`, `TABLET_MODE_LOG`, `TABLET_MODE_USB_DEVICES`, `TABLET_MODE_CONF`, and `TABLET_MODE_RUN_DIR`. Add `tests/dock-osk.sh` that:

- points `TABLET_MODE_USB_DEVICES` at a fake sysfs tree
- with dry-run on, a transition to `1ce6` present logs an OSK hide and no `eval hl.monitor` or `eval hl.device`
- a transition to `1ce6` absent does not log an OSK show when `show_keyboard=false`
- the same transition logs an OSK show when `show_keyboard=true`

Done when `tests/dock-osk.sh` exits 0, `rg` of the daemon's event path shows no live call to `rotate_to`, `map_touch`, `tweaks_apply`, or `inhibit_take`, and the service has not been enabled.

## Session 2 — Bar card matches the new behavior

File: `Widget.qml`.

- `moduleName`, `ipcTarget`, and `IpcHandler.target` are `brogers.zephyrus-duo-keyboard`.
- `cli` resolves `bin/zephyrus-duo-keyboard`. `runDir` is `$XDG_RUNTIME_DIR/zephyrus-duo-keyboard`.
- Remove the rotation lock, the turn-the-screen control, and Calibrate.
- Keep the on-screen keyboard switch, dock status (seated or lifted), Check (`doctor`), and Turn off (`disable`).
- Floating button: both `eDP` bars, only while `status` says the keyboard is lifted and the daemon is running. Namespace `zephyrus-duo-keyboard-button`.
- Menu entries: drop Tablet Mode and Rotation Lock. Keep On-screen Keyboard and the plugin on/off entry, under the new command name. The menu block markers must not contain the old `tablet-mode` marker strings, or `menu_remove` from a future Z13 install could eat this block.

Done when the QML no longer references `alanroman117`, `bin/tablet-mode`, rotation, or calibrate, and `omarchy plugin validate` on this repo exits 0. Do not enable the plugin yet.

## Session 3 — README and manifest describe this fork

Files: `manifest.json`, `README.md`.

- `id` is `brogers.zephyrus-duo-keyboard`. Name and description match the table above. `author` is `brogers`. `entryPoints.barWidget` stays `Widget.qml`.
- Rewrite the README for this fork: GX651AX, `0b05:1ce6`, `zephyrus-duo-panels`, `wvkbd-deskus`, and the command `zephyrus-duo-keyboard`. Say in the first screen that screen rotation is `zephyrus-duo-rotate`, not this plugin.
- Drop Z13 install instructions, calibrate, and the claim that detaching the keyboard turns the screen.
- Keep the GPL note on `packaging/wvkbd-deskus/*.patch` and the MIT note for the plugin. The packaging recipe can stay; `wvkbd-deskus` is already installed, and `install` should still be able to rebuild it.

Done when `omarchy plugin validate` exits 0 and the README does not tell anyone to run `tablet-mode rotate` or to set `keyboard=0b05:1a30`.

## Session 4 — Live check on this machine

Only after Sessions 1–3 are checked. This is the first session that may write under `~/.config/omarchy/` and `~/.config/systemd/user/`.

1. Re-run `zephyrus-duo-panels` and `cat "$XDG_RUNTIME_DIR/zephyrus-duo-orientation"`. If the orientation is not `normal`, do not reload Hyprland as a test. Say so and stop.
2. `omarchy plugin add` from this repo, or enable the already-copied plugin, then `zephyrus-duo-keyboard enable`.
3. Confirm `pgrep -af zephyrus-duo-rotate` still shows the Python rotator, and `pgrep -u "$USER" -x monitor-sensor` is empty.
4. `hyprctl monitors -j` still shows the two panels at the positions from the orientation file, with the same transforms as before enable. This plugin must not have moved them.
5. `zephyrus-duo-keyboard osk show` puts a `wvkbd` layer on the bottom connector only (`hyprctl layers -j`, namespace `wvkbd`). `osk hide` removes it.
6. With the keyboard visible, `hyprctl reload`. Panels come back from `Zephyrus.lua` (same positions and transforms). The on-screen keyboard comes back on the bottom connector.
7. `zephyrus-duo-keyboard doctor` reports lifted, `0b05:1ce6`, and that output.
8. `zephyrus-duo-keyboard disable` stops `wvkbd` and leaves the panels where `Zephyrus.lua` put them.

Do not seat or lift the magnetic keyboard as part of this. The USB watch is covered by the fixture. A live dock check is optional and only if the person at the machine wants it: seating should hide the on-screen keyboard, and `zephyrus-duo-dock` should still be what disables the bottom panel.

## Risks to remember

- `hyprctl reload` from the rotator runs on every orientation change while the keyboard is lifted. Re-show the on-screen keyboard after `configreloaded`, and write no layout rules in that handler.
- If `zephyrus-duo-panels` is wrong after a mux change, the keyboard follows the wrong panel. `doctor` prints the names it resolved.
- `general:gaps_out` is a shared value. Any `hl.config` of gaps from this plugin will flatten `oled-gap-shift` until its next step.
- Widget types used today (`Panel`, `BarIconButton`, `KeyboardPanel`, `ToggleSwitch`, `ButtonGroup`, `moduleWidgets`, `bar.run`) exist on Omarchy `4.0.0.r7481`. If a later session is on a different Omarchy build, re-check those names before editing `Widget.qml`.

## Session notes

- 2026-10-31: Plan written from the approved review. No code changes. Next session starts at Session 1.
- 2026-10-31: Session 1. Renamed the daemon to `zephyrus-duo-keyboard` and the unit to `zephyrus-duo-keyboard.service`. A seated `0b05:1ce6` hides wvkbd; a lift shows it only when `show_keyboard=true` (left false). Rotation, touch mapping, gap tweaks, the accelerometer, and the sleep inhibitor are not reachable. `tests/dock-osk.sh` exits 0. `doctor` reports lifted and `eDP-2`. The service was not enabled. Next: Session 2, the bar card.
- 2026-10-31: Session 2. `Widget.qml` talks to `brogers.zephyrus-duo-keyboard` and `bin/zephyrus-duo-keyboard`. The card shows seated or lifted, the on-screen keyboard switch, Check, and Turn off. The floating button is on each `eDP` bar only while the daemon is running and the keyboard is lifted (`zephyrus-duo-keyboard-button`). Menu markers were already the new command, with On-screen Keyboard and the plugin on/off entry. `omarchy plugin validate` exits 0. The plugin was not enabled. Next: Session 3, README and manifest.
- 2026-10-31: Session 3. `manifest.json` id is `brogers.zephyrus-duo-keyboard`, name Zephyrus Duo Keyboard, author `brogers`. README describes the GX651AX fork: `0b05:1ce6`, `zephyrus-duo-panels`, `wvkbd-deskus`, and `zephyrus-duo-keyboard`. The first screen says rotation is `zephyrus-duo-rotate`. `omarchy plugin validate` exits 0. The plugin was not enabled. Next: Session 4, live check on this machine. Re-run `zephyrus-duo-panels` first, and stop if the orientation is not `normal`.
- 2026-10-31: Session 4. Orientation was `normal`; panels `top=eDP-1` `bottom=eDP-2`. Installed this working tree at `~/.config/omarchy/plugins/brogers.zephyrus-duo-keyboard` (a git clone would have missed uncommitted Sessions 1–3) and ran `zephyrus-duo-keyboard enable`. Rotator still the Python process; no `monitor-sensor`. Panels stayed at `0x0` / `0x900`, transform 0, through enable, `osk show` (layer `wvkbd` on `eDP-2` only), `osk hide`, and `hyprctl reload` (keyboard came back on `eDP-2`). `doctor`: lifted, `0b05:1ce6`, output `eDP-2`. `disable` stopped wvkbd and left the panels. No live seat/lift. After the check, `disable --full` removed the bar icon, menu entries, hook, unit, config, and `~/.local/bin` link, and the installed copy was deleted. Nothing from this plugin is enabled on the machine.
