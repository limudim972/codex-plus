param(
    [int]$Port = 0,
    [string]$Title,
    [string]$Id
)

. (Join-Path $PSScriptRoot 'resolve-codex-plus-port.ps1')
$resolvedPort = Get-CodexPlusDebugPort -Port $Port
$list = Invoke-RestMethod -Uri "http://127.0.0.1:$resolvedPort/json/list" -UseBasicParsing
$pages = if ($list -is [System.Array]) { $list } else { $list.value }
$page = $pages |
    Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl -and $_.url -like 'app://*' } |
    Where-Object { [string]::IsNullOrWhiteSpace($Title) -or $_.title -eq $Title } |
    Where-Object { [string]::IsNullOrWhiteSpace($Id) -or $_.id -eq $Id } |
    Select-Object -First 1
if (-not $page) { throw 'No live Codex page target found.' }
$ws = $page.webSocketDebuggerUrl
$client = [System.Net.WebSockets.ClientWebSocket]::new()
$client.ConnectAsync([Uri]$ws, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
$expr = 'JSON.stringify({ plus: !!window.__CODEX_PLUS_SIDEBAR_PAGING, badge: !!window.__CODEX_PLUS_CONTEXT_BADGE, pagerCount: document.querySelectorAll(''[data-codex-plus-sidebar-pager]'').length, tasksLoaded: Array.from(document.querySelectorAll(''[role="list"]'')).find(el => { const label = (el.getAttribute(''aria-label'') || '''').trim(); return label === ''Tasks'' || label === ''Chats''; })?.getAttribute(''data-codex-plus-sidebar-loaded'') || null })'
$cmd = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expr; awaitPromise = $true; returnByValue = $true } }
$json = $cmd | ConvertTo-Json -Depth 20 -Compress
$bytes = [Text.Encoding]::UTF8.GetBytes($json)
$client.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
$buf = New-Object byte[] 16384
$recv = [ArraySegment[byte]]::new($buf)
$msg = New-Object System.Collections.Generic.List[byte]
$res = $client.ReceiveAsync($recv, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
if($res.Count -gt 0){ $msg.AddRange([byte[]]$buf[0..($res.Count-1)]) }
while(-not $res.EndOfMessage){
  $res = $client.ReceiveAsync($recv, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
  if($res.Count -gt 0){ $msg.AddRange([byte[]]$buf[0..($res.Count-1)]) }
}
$client.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,'done',[Threading.CancellationToken]::None).GetAwaiter().GetResult()
$client.Dispose()
[Text.Encoding]::UTF8.GetString($msg.ToArray())
