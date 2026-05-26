# Apollo Steam Deckless

Run Steam Big Picture from a Windows PC on a phone or tablet through Apollo and Moonlight, without manually changing monitors every time.

This project solves one focused problem:

> A Windows gaming PC has a physical monitor, but a Moonlight client should get its own correctly sized virtual display, and Steam Big Picture should open on that streamed display.

It is useful for:

- Playing Steam games from a phone or tablet on the same LAN.
- Reusing the same Apollo setup on another Windows PC.
- Running a Windows gaming host where the physical monitor is not the streaming target.

## What It Configures

- Enables Apollo virtual-display mode.
- Makes the streamed virtual display the primary display during a session.
- Forces paired clients to use virtual displays.
- Grants paired clients the permission needed to launch apps.
- Replaces Apollo's Steam Big Picture entry with a launcher that starts Steam and moves Steam windows to the streamed display.

## Requirements

- Windows 10/11 host.
- Apollo installed and reachable through its Web UI.
- Steam installed on the Windows host.
- Moonlight-compatible client.
- PowerShell 5.1 or later.

## Files

```text
scripts/
  Configure-Apollo.ps1      Configure Apollo API settings, app entry, and client permissions.
  Launch-GameStreamApp.ps1  Start Steam Big Picture and move Steam windows to the stream display.

examples/
  apollo-steam-big-picture-app.json  Example Apollo app entry.
  windows-host.example.json          Placeholder host config shape.
```

## Quick Start

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
