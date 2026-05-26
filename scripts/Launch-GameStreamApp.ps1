param(
  [string]$ExecutablePath = '',
  [string]$ExecutableArguments = '-start steam://open/bigpicture',
  [string[]]$ProcessNames = @('steam', 'steamwebhelper'),
  [int]$WaitSeconds = 30,
  [string]$LogPath = 'C:\Program Files\Apollo\config\gamestream-launcher.log',
  [switch]$PreferPrimaryDisplay
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-LauncherLog($message) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $message
  Add-Content -Path $LogPath -Value $line
}

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class GameStreamWin32 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
'@

Add-Type -AssemblyName System.Windows.Forms

function Find-SteamExecutable {
  $candidates = @(
    $ExecutablePath,
    'C:\Program Files (x86)\Steam\steam.exe',
    'C:\Program Files\Steam\steam.exe',
    'D:\Steam\steam.exe',
    'D:\App\Steam\steam.exe'
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) { return $candidate }
  }

  return ''
}

function Get-TargetScreen {
  $screens = [System.Windows.Forms.Screen]::AllScreens
  if ($PreferPrimaryDisplay) {
    $primary = $screens | Where-Object { $_.Primary } | Select-Object -First 1
    if ($primary) { return $primary }
  }

  $nonPrimary = $screens |
    Where-Object { -not $_.Primary } |
    Sort-Object { $_.Bounds.X } -Descending |
    Select-Object -First 1

  if ($nonPrimary) { return $nonPrimary }
  return $screens | Select-Object -First 1
}

function Get-ManagedWindows {
  $processIds = Get-Process -Name $ProcessNames -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id

  if (-not $processIds) { return @() }

  $windows = New-Object System.Collections.Generic.List[object]
  [GameStreamWin32]::EnumWindows({
    param($hWnd, $lParam)

    if (-not [GameStreamWin32]::IsWindowVisible($hWnd)) { return $true }

    [uint32]$pid = 0
    [void][GameStreamWin32]::GetWindowThreadProcessId($hWnd, [ref]$pid)
    if ($processIds -notcontains [int]$pid) { return $true }

    $titleBuilder = New-Object System.Text.StringBuilder 512
    [void][GameStreamWin32]::GetWindowText($hWnd, $titleBuilder, $titleBuilder.Capacity)
    $title = $titleBuilder.ToString()

    $windows.Add([pscustomobject]@{
      Handle = $hWnd
      Pid = [int]$pid
      Title = $title
    })

    return $true
  }, [IntPtr]::Zero) | Out-Null

  return $windows
}

$resolvedExecutablePath = Find-SteamExecutable

Write-LauncherLog 'launcher started'

$screenSummary = [System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
  '{0} primary={1} bounds={2}' -f $_.DeviceName, $_.Primary, $_.Bounds.ToString()
}
Write-LauncherLog ('screens: ' + ($screenSummary -join ' | '))

if ($resolvedExecutablePath) {
  Write-LauncherLog "starting $resolvedExecutablePath $ExecutableArguments"
  Start-Process -FilePath $resolvedExecutablePath -ArgumentList $ExecutableArguments
} else {
  Write-LauncherLog 'starting steam://open/bigpicture via shell'
  Start-Process 'steam://open/bigpicture'
}

$screen = Get-TargetScreen
$bounds = $screen.Bounds
Write-LauncherLog ('target screen: {0} primary={1} bounds={2}' -f $screen.DeviceName, $screen.Primary, $bounds.ToString())

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$moved = 0

do {
  Start-Sleep -Milliseconds 500
  $windows = Get-ManagedWindows
  foreach ($window in $windows) {
    [void][GameStreamWin32]::ShowWindow($window.Handle, 9)
    [void][GameStreamWin32]::SetWindowPos(
      $window.Handle,
      [IntPtr]::Zero,
      $bounds.X,
      $bounds.Y,
      $bounds.Width,
      $bounds.Height,
      0x0040
    )

    $moved += 1
    Write-LauncherLog ('moved window pid={0} title="{1}" to {2},{3} {4}x{5}' -f $window.Pid, $window.Title, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
  }
} while ((Get-Date) -lt $deadline)

Write-LauncherLog "launcher finished, move attempts=$moved"
