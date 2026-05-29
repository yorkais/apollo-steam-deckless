param(
  [string]$AdapterName = '',
  [string]$AdapterDescriptionPattern = '(Wi-Fi|Wireless|802\.11|Ethernet|Realtek|Intel)',
  [int]$SleepAfterMinutesOnAc = 30,
  [int]$DisplayOffMinutesOnAc = 10,
  [switch]$DisableWakePassword,
  [switch]$DisableHybridSleep,
  [switch]$DisablePatternWake,
  [string[]]$PowerRequestOverrideProcessNames = @()
)

$ErrorActionPreference = 'Stop'

function Get-StreamingWakeAdapter {
  if (-not [string]::IsNullOrWhiteSpace($AdapterName)) {
    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
    return $adapter
  }

  $adapters = Get-NetAdapter |
    Where-Object {
      $_.Status -eq 'Up' -and
      ($_.InterfaceDescription -match $AdapterDescriptionPattern -or $_.Name -match $AdapterDescriptionPattern)
    } |
    Sort-Object InterfaceMetric, InterfaceIndex

  $selected = $adapters | Select-Object -First 1
  if (-not $selected) {
    throw "No active network adapter matched pattern: $AdapterDescriptionPattern"
  }

  return $selected
}

function Set-AdvancedPropertyIfPresent {
  param(
    [string]$Name,
    [string]$RegistryKeyword,
    [object]$RegistryValue
  )

  $property = Get-NetAdapterAdvancedProperty -Name $Name -RegistryKeyword $RegistryKeyword -ErrorAction SilentlyContinue
  if ($property) {
    Set-NetAdapterAdvancedProperty -Name $Name -RegistryKeyword $RegistryKeyword -RegistryValue $RegistryValue -NoRestart -ErrorAction SilentlyContinue
  }
}

$adapter = Get-StreamingWakeAdapter

Write-Host ('Selected adapter: {0} ({1}) {2}' -f $adapter.Name, $adapter.InterfaceDescription, $adapter.MacAddress)

Set-AdvancedPropertyIfPresent -Name $adapter.Name -RegistryKeyword '*WakeOnMagicPacket' -RegistryValue 1
Set-AdvancedPropertyIfPresent -Name $adapter.Name -RegistryKeyword '*PMARPOffload' -RegistryValue 1
Set-AdvancedPropertyIfPresent -Name $adapter.Name -RegistryKeyword '*PMNSOffload' -RegistryValue 1
Set-AdvancedPropertyIfPresent -Name $adapter.Name -RegistryKeyword '*PMWiFiRekeyOffload' -RegistryValue 1
Set-AdvancedPropertyIfPresent -Name $adapter.Name -RegistryKeyword '*DeviceSleepOnDisconnect' -RegistryValue 0

if ($DisablePatternWake) {
  Set-AdvancedPropertyIfPresent -Name $adapter.Name -RegistryKeyword '*WakeOnPattern' -RegistryValue 0
}

powercfg /deviceenablewake $adapter.InterfaceDescription | Out-Null

if ($DisableHybridSleep) {
  powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP HYBRIDSLEEP 0 | Out-Null
  powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP HYBRIDSLEEP 0 | Out-Null
}

if ($SleepAfterMinutesOnAc -ge 0) {
  powercfg /change standby-timeout-ac $SleepAfterMinutesOnAc | Out-Null
}

if ($DisplayOffMinutesOnAc -ge 0) {
  powercfg /change monitor-timeout-ac $DisplayOffMinutesOnAc | Out-Null
}

powercfg /change hibernate-timeout-ac 0 | Out-Null

if ($DisableWakePassword) {
  powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 0 | Out-Null
  powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 0 | Out-Null

  $desktop = 'HKCU:\Control Panel\Desktop'
  Set-ItemProperty -Path $desktop -Name ScreenSaveActive -Value '0'
  Set-ItemProperty -Path $desktop -Name ScreenSaverIsSecure -Value '0'
  Set-ItemProperty -Path $desktop -Name ScreenSaveTimeOut -Value '0'

  $systemPolicy = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
  if (Test-Path $systemPolicy) {
    New-ItemProperty -Path $systemPolicy -Name InactivityTimeoutSecs -PropertyType DWord -Value 0 -Force | Out-Null
  }
}

foreach ($processName in $PowerRequestOverrideProcessNames) {
  if ([string]::IsNullOrWhiteSpace($processName)) { continue }
  powercfg /requestsoverride PROCESS $processName SYSTEM | Out-Null
}

powercfg /setactive SCHEME_CURRENT | Out-Null

Write-Host ''
Write-Host 'Wake-capable devices:'
powercfg /devicequery wake_armed

Write-Host ''
Write-Host 'Power requests:'
powercfg /requests

Write-Host ''
Write-Host 'Adapter wake properties:'
Get-NetAdapterAdvancedProperty -Name $adapter.Name |
  Where-Object { $_.RegistryKeyword -match 'Wake|PM|DeviceSleep' -or $_.DisplayName -match 'Wake|Magic|Pattern|ARP|NS|sleep|power' } |
  Select-Object DisplayName, DisplayValue, RegistryKeyword, RegistryValue |
  Format-Table -AutoSize

Write-Host ''
Write-Host 'Wake-on-LAN configuration applied.'
