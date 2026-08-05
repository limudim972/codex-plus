param(
  [int]$Port = 3001,
  [string]$Serial
)

$adbArgs = @()
if ($Serial) {
  $adbArgs += @('-s', $Serial)
}

$deviceLines = @(adb @adbArgs devices)
$connectedDevices = @($deviceLines | Where-Object { $_ -match '^\S+\s+device\s*$' })

if ($connectedDevices.Count -eq 0) {
  throw 'No authorized Android device is connected.'
}

if (-not $Serial -and $connectedDevices.Count -gt 1) {
  throw 'Multiple authorized Android devices are connected. Provide -Serial explicitly.'
}

if (-not $Serial) {
  $Serial = ($connectedDevices[0] -split '\s+')[0]
  $adbArgs = @('-s', $Serial)
}

& adb @adbArgs reverse "tcp:$Port" "tcp:$Port"
if ($LASTEXITCODE -ne 0) {
  throw "Failed to create ADB reverse mapping for port $Port."
}

[pscustomobject]@{
  Serial = $Serial
  Port = $Port
  Mapping = "device tcp:$Port -> computer tcp:$Port"
}
