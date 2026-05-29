# Linux Sunshine Host

Use this path when the host is a Linux workstation or server that must keep its
existing operating system and research environment intact.

The setup script creates an AppImage-based Sunshine runtime in one directory. It
does not install Steam, Sunshine, Flatpak, gamescope, GPU drivers, or desktop
packages. The optional input-permission helper is the only step that uses sudo.

## What This Does

- Keeps Sunshine state, cache, logs, temporary files, and future Steam data under
  one isolated directory.
- Starts Sunshine against an existing X11 display.
- Provides start, stop, status, and credential helper commands.
- Provides a sudo helper for Moonlight keyboard, mouse, and gamepad input.

## What This Does Not Do

- It does not change the base Linux distribution.
- It does not create a virtual monitor by itself.
- It does not open firewall, router, VPN, or campus-network ports.
- It does not make Windows-only anti-cheat games work on Linux.

For a headless Linux host, provide a display first with a real monitor, an HDMI
dummy plug, or your own virtual-display setup. The script then captures that
display through Sunshine.

## Quick Start

On the Linux host:

```bash
./scripts/setup-linux-sunshine-appimage.sh \
  --base-dir "$HOME/game-stream" \
  --display :0
```

Set Sunshine Web UI credentials:

```bash
$HOME/game-stream/bin/sunshine-set-creds stream-admin '<new-password>'
```

Start Sunshine:

```bash
$HOME/game-stream/bin/start-sunshine
```

Enable Moonlight input once:

```bash
sudo "$HOME/game-stream/bin/fix-sunshine-input-permissions.sh" "$USER"
```

The user may need to log out and back in after being added to the `input` group.
Restart Sunshine after that:

```bash
$HOME/game-stream/bin/stop-sunshine
$HOME/game-stream/bin/start-sunshine
```

## Web UI Through SSH

If only SSH is reachable from the client machine, forward the Web UI:

```bash
ssh -L 127.0.0.1:47990:127.0.0.1:47990 linux-host
```

Then open:

```text
https://127.0.0.1:47990
```

This tunnel is only for the Web UI. Moonlight streaming still needs the Sunshine
streaming ports to be reachable, or it needs a VPN or port-forwarding layer that
carries the game stream.

## Finding The Display

Useful checks:

```bash
loginctl list-sessions
loginctl show-session <session-id> -p Name -p Type -p State -p Display -p TTY
ls -la /tmp/.X11-unix
DISPLAY=:0 xrandr --query
DISPLAY=:1 xrandr --query
```

Use the display that shows the monitor or dummy display you want Moonlight to
see.

## Steam Isolation

Use the directory created by the setup script as the Steam library location:

```text
$HOME/game-stream/steam-library
```

Steam itself may still need system libraries or a package-manager install,
depending on the distribution. Keep the game library and Proton compat data
inside the isolated runtime to avoid mixing game state with research projects.

## Troubleshooting

`Unable to create virtual mouse` or `Unable to create virtual keyboard`

Run the input-permission helper with sudo, then log out and back in:

```bash
sudo "$HOME/game-stream/bin/fix-sunshine-input-permissions.sh" "$USER"
```

`Configuration UI available at https://localhost:47990`, but the phone cannot connect

The host is running Sunshine, but the network path is missing. Open the Sunshine
ports on a trusted network, or use a VPN/jump network that supports Moonlight
streaming. An SSH tunnel to `47990` only exposes the management UI.

Blank or wrong display

The selected X11 display is not the one attached to the monitor or dummy output.
Check `xrandr` and rerun setup with a different `--display` value.

## Security

Do not expose Sunshine's Web UI to untrusted networks. Use strong credentials,
pair only your own Moonlight clients, and keep real hostnames, addresses, and
logs out of public repositories.
