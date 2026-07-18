param(
    [Parameter(Mandatory)]
    [int]$Port,
    [Parameter(Mandatory)]
    [double]$X,
    [Parameter(Mandatory)]
    [double]$Y
)

function Get-CodexDevToolsPage {
    param([Parameter(Mandatory)][int]$Port)

    $list = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -UseBasicParsing
    $pages = if ($list -is [System.Array]) { $list } else { $list.value }
    $page = $pages | Where-Object { $_.type -eq 'page' -and $_.url -like 'app://*' } | Select-Object -First 1
    if (-not $page) {
        throw "No debugger target found on port $Port"
    }
    return $page
}

function Invoke-CodexDevToolsCommand {
    param(
        [Parameter(Mandatory)][string]$WebSocketDebuggerUrl,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)]$Params
    )

    $client = [System.Net.WebSockets.ClientWebSocket]::new()
    try {
        $client.ConnectAsync([Uri]$WebSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null

        $command = @{
            id = 1
            method = $Method
            params = $Params
        } | ConvertTo-Json -Depth 20 -Compress

        $bytes = [Text.Encoding]::UTF8.GetBytes($command)
        $client.SendAsync(
            [ArraySegment[byte]]::new($bytes),
            [System.Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            [Threading.CancellationToken]::None
        ).GetAwaiter().GetResult() | Out-Null

        $buffer = New-Object byte[] 65536
        $segment = [ArraySegment[byte]]::new($buffer)
        while ($true) {
            $message = New-Object System.Collections.Generic.List[byte]
            $result = $client.ReceiveAsync($segment, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
            if ($result.Count -gt 0) {
                $message.AddRange([byte[]]$buffer[0..($result.Count - 1)])
            }

            while (-not $result.EndOfMessage) {
                $result = $client.ReceiveAsync($segment, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
                if ($result.Count -gt 0) {
                    $message.AddRange([byte[]]$buffer[0..($result.Count - 1)])
                }
            }

            $payload = [Text.Encoding]::UTF8.GetString($message.ToArray()) | ConvertFrom-Json
            if ($payload.id -eq 1) {
                return $payload
            }
        }
    } finally {
        if ($client.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $client.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                'done',
                [Threading.CancellationToken]::None
            ).GetAwaiter().GetResult() | Out-Null
        }
        $client.Dispose()
    }
}

$page = Get-CodexDevToolsPage -Port $Port
Invoke-CodexDevToolsCommand -WebSocketDebuggerUrl $page.webSocketDebuggerUrl -Method 'Input.dispatchMouseEvent' -Params @{
    type = 'mouseMoved'
    x = $X
    y = $Y
} | Out-Null

Write-Output "Dispatched mouse move to ($X, $Y) on port $Port."
