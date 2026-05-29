# Steam Deckless Streaming Toolkit

Run Steam from a Windows or Linux host on a phone or tablet through
Moonlight-compatible streaming, without turning the host into a dedicated game
console.

This project covers two related host setups:

- **Windows + Apollo:** give Moonlight clients their own Apollo virtual display,
  then launch Steam Big Picture on that streamed display.
- **Linux + Sunshine:** run Sunshine from one isolated directory on an existing
  Linux workstation or server, keeping research or work environments separate
  from game-streaming state.

It is useful for:

- Playing Steam games from a phone or tablet.
- Reusing the same streaming setup on another host.
- Keeping the physical monitor separate from the streamed display on Windows.
- Adding Sunshine to a Linux machine without replacing the base OS.

## Windows Apollo Host

Use this when the host is Windows and Apollo is installed.

### What It Configures

- Enables Apollo virtual-display mode.
- Makes the streamed virtual display the primary display during a session.
- Forces paired clients to use virtual displays.
- Grants paired clients the permission needed to launch apps.
- Replaces Apollo's Steam Big Picture entry with a launcher that starts Steam and moves Steam windows to the streamed display.

### Requirements

- Windows 10/11 host.
- Apollo installed and reachable through its Web UI.
- Steam installed on the Windows host.
- Moonlight-compatible client.
- PowerShell 5.1 or later.

### Files

```text
scripts/
  Configure-Apollo.ps1      Configure Apollo API settings, app entry, and client permissions.
  Configure-WakeForStreaming.ps1
                             Configure Wake-on-LAN and sleep behavior for streaming.
  Launch-GameStreamApp.ps1  Start Steam Big Picture and move Steam windows to the stream display.
  Send-WakePacket.ps1       Send a Wake-on-LAN magic packet from PowerShell.
  setup-linux-sunshine-appimage.sh
                             Create an isolated Sunshine AppImage runtime on Linux.

examples/
  apollo-steam-big-picture-app.json  Example Apollo app entry.
  windows-host.example.json          Placeholder host config shape.
  linux-host.example.env             Placeholder Linux host config shape.
```

### Quick Start

Copy the launcher into Apollo's scripts directory on the Windows host:

```powershell
Copy-Item .\scripts\Launch-GameStreamApp.ps1 "C:\Program Files\Apollo\scripts\Launch-GameStreamApp.ps1" -Force
```

Run the configurator:

```powershell
.\scripts\Configure-Apollo.ps1 `
  -BaseUrl "https://127.0.0.1:47990" `
  -Username "apollo-user" `
  -Password "<apollo-web-ui-password>" `
  -ClientNames "Phone","Tablet" `
  -TrustCertificate
```

Pair clients in Moonlight or another compatible client first, then rerun the same command with their Apollo client names.

## Linux Sunshine Host

Use this when the host is Linux and the base system must stay intact.

This path does **not** install Sunshine as a system package. It creates an
isolated AppImage runtime under one directory, redirects Sunshine state through
`HOME` and XDG environment variables, and leaves the host OS and research
directories alone.

```bash
./scripts/setup-linux-sunshine-appimage.sh \
  --base-dir "$HOME/game-stream" \
  --display :0
```

Set Sunshine Web UI credentials:

```bash
$HOME/game-stream/bin/sunshine-set-creds stream-admin '<new-password>'
```

Start and inspect Sunshine:

```bash
$HOME/game-stream/bin/start-sunshine
$HOME/game-stream/bin/status-game-stream
```

Enable Moonlight keyboard, mouse, and gamepad input once:

```bash
sudo "$HOME/game-stream/bin/fix-sunshine-input-permissions.sh" "$USER"
```

For details, see [Linux Sunshine Host](docs/linux-sunshine-host.md).

## Optional Sleep And Wake Setup

For a couch or mobile workflow, the host can sleep most of the time and wake when Moonlight sends a Wake-on-LAN packet.

Run PowerShell as administrator on the Windows host:

```powershell
.\scripts\Configure-WakeForStreaming.ps1 `
  -AdapterDescriptionPattern "Wi-Fi|Wireless|Ethernet|Intel|Realtek" `
  -SleepAfterMinutesOnAc 30 `
  -DisplayOffMinutesOnAc 10 `
  -DisableHybridSleep `
  -DisablePatternWake
```

If a known background remote-control helper prevents sleep, add a request override only after reviewing `powercfg /requests`:

```powershell
.\scripts\Configure-WakeForStreaming.ps1 `
  -PowerRequestOverrideProcessNames "RemoteControlHelper.exe"
```

To allow a sleeping-but-unlocked desktop to resume directly into Steam, you may also use:

```powershell
.\scripts\Configure-WakeForStreaming.ps1 `
  -DisableWakePassword
```

This is a security tradeoff. It does not unlock an already locked Windows session and it does not remove the account password. It only asks Windows not to require a new sign-in after waking from sleep. For this workflow, unlock the host locally once, leave Steam or Big Picture ready, then let the host sleep.

To test Wake-on-LAN from another PowerShell machine:

```powershell
.\scripts\Send-WakePacket.ps1 `
  -MacAddress "00-11-22-33-44-55" `
  -Targets "192.0.2.255","255.255.255.255"
```

Moonlight clients can also send Wake-on-LAN. If a phone or tablet cannot wake the host but another machine on the same network can, the Wi-Fi or LAN may be blocking client broadcast packets. In that case, use a small always-on machine on the same LAN as a wake relay.

## Apollo Settings Applied

```ini
headless_mode = enabled
isolated_virtual_display_option = enabled
dd_configuration_option = ensure_primary
dd_resolution_option = auto
dd_refresh_rate_option = auto
dd_config_revert_on_disconnect = enabled
origin_web_ui_allowed = lan
```

The Steam Big Picture app entry is changed to a detached launcher:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Apollo\scripts\Launch-GameStreamApp.ps1"
```

## Steam Location

The launcher checks common Steam paths and falls back to `steam://open/bigpicture`.

For a custom Steam path, run:

```powershell
.\scripts\Launch-GameStreamApp.ps1 `
  -ExecutablePath "E:\Games\Steam\steam.exe" `
  -ExecutableArguments "-start steam://open/bigpicture"
```

## Troubleshooting

`permission denied`

The client is paired but does not have launch permission. Run `Configure-Apollo.ps1` with that client name.

Empty streamed desktop

Steam probably opened on the physical monitor. Confirm `dd_configuration_option = ensure_primary` and that the Steam Big Picture app entry launches `Launch-GameStreamApp.ps1`.

Wrong aspect ratio

Change the client resolution first. If needed, set a per-client `display_mode` in Apollo.

Host wakes into the Windows lock screen

Wake-on-LAN can wake the host, but it cannot unlock Windows. If the session was locked before sleep, it will still be locked after wake. Unlock the host locally once, leave the desktop session active, and let it sleep without pressing `Win+L`.

Host does not sleep

Run:

```powershell
powercfg /requests
```

Streaming, audio, remote-control, update, or browser helper processes can block sleep. Review the output before adding any `powercfg /requestsoverride` rule.

Host does not wake from Moonlight

Confirm the network adapter is armed:

```powershell
powercfg /devicequery wake_armed
```

Then test the wake packet from another machine:

```powershell
.\scripts\Send-WakePacket.ps1 -MacAddress "00-11-22-33-44-55"
```

If direct broadcast fails on a managed Wi-Fi network, use a wake relay on the same LAN or connect the Windows host by Ethernet.

Logs:

```text
C:\Program Files\Apollo\config\gamestream-launcher.log
C:\Program Files\Apollo\config\sunshine.log
```

## Security

Do not commit Apollo credentials, hostnames, private IPs, or logs from a real machine.

Expose Apollo's Web UI only on trusted networks.

## License

MIT
