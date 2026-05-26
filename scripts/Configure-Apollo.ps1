param(
  [Parameter(Mandatory = $true)]
  [string]$BaseUrl,

  [Parameter(Mandatory = $true)]
  [string]$Username,

  [Parameter(Mandatory = $true)]
  [string]$Password,

  [string[]]$ClientNames = @(),
  [int]$ClientPermission = 119480064,
  [switch]$TrustCertificate
)

$ErrorActionPreference = 'Stop'

if ($TrustCertificate) {
  add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
  public bool CheckValidationResult(
    ServicePoint srvPoint, X509Certificate certificate,
    WebRequest request, int certificateProblem) {
    return true;
  }
}
"@
  [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

function Get-OptionalProperty {
  param(
    [object]$Object,
    [string]$Name,
    [object]$Default
  )

  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Invoke-ApolloJson {
  param(
    [string]$Method = 'GET',
    [string]$Path,
    [object]$Body = $null
  )

  $uri = '{0}/{1}' -f $BaseUrl.TrimEnd('/'), $Path.TrimStart('/')
  $params = @{
    Method = $Method
    Uri = $uri
    WebSession = $session
    ContentType = 'application/json'
  }

  if ($null -ne $Body) {
    $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
  }

  Invoke-RestMethod @params
}

Invoke-ApolloJson -Method POST -Path '/api/login' -Body @{
  username = $Username
  password = $Password
} | Out-Null

Invoke-ApolloJson -Method POST -Path '/api/config' -Body @{
  address_family = 'ipv4'
  origin_web_ui_allowed = 'lan'
  headless_mode = 'enabled'
  isolated_virtual_display_option = 'enabled'
  dd_configuration_option = 'ensure_primary'
  dd_resolution_option = 'auto'
  dd_refresh_rate_option = 'auto'
  dd_config_revert_delay = 3000
  dd_config_revert_on_disconnect = 'enabled'
} | Out-Null

$apps = Invoke-ApolloJson -Path '/api/apps'
foreach ($app in $apps.apps) {
  if ($app.name -eq 'Steam Big Picture') {
    $app.PSObject.Properties.Remove('cmd')
    $app | Add-Member -Force -NotePropertyName 'virtual-display' -NotePropertyValue $true
    $app | Add-Member -Force -NotePropertyName 'auto-detach' -NotePropertyValue $true
    $app | Add-Member -Force -NotePropertyName 'wait-all' -NotePropertyValue $false
    $app | Add-Member -Force -NotePropertyName 'exit-timeout' -NotePropertyValue 5
    $app | Add-Member -Force -NotePropertyName 'detached' -NotePropertyValue @(
      'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Apollo\scripts\Launch-GameStreamApp.ps1"'
    )
    $app | Add-Member -Force -NotePropertyName 'prep-cmd' -NotePropertyValue @(
      @{
        do = ''
        elevated = $false
        undo = 'steam://close/bigpicture'
      }
    )

    Invoke-ApolloJson -Method POST -Path '/api/apps' -Body $app | Out-Null
  }
}

if ($ClientNames.Count -gt 0) {
  $clients = Invoke-ApolloJson -Path '/api/clients/list'
  foreach ($client in $clients.named_certs) {
    if ($ClientNames -notcontains $client.name) { continue }

    Invoke-ApolloJson -Method POST -Path '/api/clients/update' -Body @{
      uuid = $client.uuid
      name = $client.name
      display_mode = (Get-OptionalProperty -Object $client -Name 'display_mode' -Default '')
      allow_client_commands = $true
      enable_legacy_ordering = (Get-OptionalProperty -Object $client -Name 'enable_legacy_ordering' -Default $true)
      always_use_virtual_display = $true
      perm = $ClientPermission
      do = (Get-OptionalProperty -Object $client -Name 'do' -Default @())
      undo = (Get-OptionalProperty -Object $client -Name 'undo' -Default @())
    } | Out-Null
  }
}

try {
  Invoke-ApolloJson -Method POST -Path '/api/restart' -Body @{} | Out-Null
} catch {
  Write-Host 'Apollo restart requested; connection may close during restart.'
}

Write-Host 'Apollo configuration applied.'
