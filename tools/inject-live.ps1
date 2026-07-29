param(
    [int]$Port = 0,
    [string]$Title,
    [string]$Id
)

. (Join-Path $PSScriptRoot 'resolve-codex-plus-port.ps1')
. 'C:\Users\Noam\AppData\Local\Codex Plus\runtime\src\codex\rtl-payload.ps1'
. 'C:\Users\Noam\AppData\Local\Codex Plus\runtime\src\codex\context-badge.ps1'
. 'C:\Users\Noam\AppData\Local\Codex Plus\runtime\src\codex\sidebar-paging.ps1'

$resolvedPort = Get-CodexPlusDebugPort -Port $Port
$list = Invoke-RestMethod -Uri "http://127.0.0.1:$resolvedPort/json/list" -UseBasicParsing
$pages = if ($list -is [System.Array]) { $list } else { $list.value }
$page = $pages |
    Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl -and $_.url -like 'app://*' } |
    Where-Object { [string]::IsNullOrWhiteSpace($Title) -or $_.title -eq $Title } |
    Where-Object { [string]::IsNullOrWhiteSpace($Id) -or $_.id -eq $Id } |
    Select-Object -First 1
if (-not $page) { throw 'No live Codex page target found.' }

$payload = Get-CodexPlusPayloadBundle
$client = [System.Net.WebSockets.ClientWebSocket]::new()
$client.ConnectAsync([Uri]$page.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
$cmd = @{
    id = 1
    method = 'Runtime.evaluate'
    params = @{
        expression = $payload
        awaitPromise = $true
        returnByValue = $true
    }
}

$json = $cmd | ConvertTo-Json -Depth 20 -Compress
$bytes = [Text.Encoding]::UTF8.GetBytes($json)
$client.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()

$buf = New-Object byte[] 65536
$recv = [ArraySegment[byte]]::new($buf)
$msg = New-Object System.Collections.Generic.List[byte]
$res = $client.ReceiveAsync($recv, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
if ($res.Count -gt 0) { $msg.AddRange([byte[]]$buf[0..($res.Count - 1)]) }
while (-not $res.EndOfMessage) {
    $res = $client.ReceiveAsync($recv, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    if ($res.Count -gt 0) { $msg.AddRange([byte[]]$buf[0..($res.Count - 1)]) }
}

$client.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [Threading.CancellationToken]::None).GetAwaiter().GetResult()
$client.Dispose()

$result = [Text.Encoding]::UTF8.GetString($msg.ToArray())
Write-Host $result
