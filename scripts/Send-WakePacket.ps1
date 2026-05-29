param(
  [Parameter(Mandatory = $true)]
  [string]$MacAddress,

  [string[]]$Targets = @('255.255.255.255'),
  [int[]]$Ports = @(9, 7),
  [int]$Repeat = 6,
  [int]$DelayMilliseconds = 350
)

$ErrorActionPreference = 'Stop'

$cleanMac = ($MacAddress -replace '[-:\s]', '').ToUpperInvariant()
if ($cleanMac.Length -ne 12 -or $cleanMac -notmatch '^[0-9A-F]{12}$') {
  throw "Invalid MAC address: $MacAddress"
}

$macBytes = for ($index = 0; $index -lt 12; $index += 2) {
  [Convert]::ToByte($cleanMac.Substring($index, 2), 16)
}

$packet = New-Object byte[] (6 + (16 * $macBytes.Length))
for ($index = 0; $index -lt 6; $index++) {
  $packet[$index] = 0xFF
}

for ($repeatIndex = 0; $repeatIndex -lt 16; $repeatIndex++) {
  [Array]::Copy($macBytes, 0, $packet, 6 + ($repeatIndex * $macBytes.Length), $macBytes.Length)
}

$client = [System.Net.Sockets.UdpClient]::new()
$client.EnableBroadcast = $true

try {
  for ($round = 1; $round -le $Repeat; $round++) {
    foreach ($target in $Targets) {
      foreach ($port in $Ports) {
        [void]$client.Send($packet, $packet.Length, $target, $port)
      }
    }

    Write-Host ('Sent wake packet round {0} to {1}' -f $round, $MacAddress)
    Start-Sleep -Milliseconds $DelayMilliseconds
  }
} finally {
  $client.Dispose()
}
