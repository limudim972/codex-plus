param(
    [Parameter(Mandatory)]
    [int]$Port,
    [string]$Expression = 'document.title',
    [string]$Title,
    [string]$Url,
    [string]$Id
)

function Get-CodexDevToolsPage {
    param(
        [Parameter(Mandatory)][int]$Port,
        [string]$Title,
        [string]$Url,
        [string]$Id
    )

    $list = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -UseBasicParsing
    $pages = if ($list -is [System.Array]) { $list } else { $list.value }
    $page = $pages |
        Where-Object { $_.type -eq 'page' -and $_.url -like 'app://*' } |
        Where-Object { [string]::IsNullOrWhiteSpace($Title) -or $_.title -eq $Title } |
        Where-Object { [string]::IsNullOrWhiteSpace($Url) -or $_.url -eq $Url } |
        Where-Object { [string]::IsNullOrWhiteSpace($Id) -or $_.id -eq $Id } |
        Select-Object -First 1
    if (-not $page) {
        $filter = if ($Id) { " id '$Id'" } elseif ($Title) { " title '$Title'" } elseif ($Url) { " URL '$Url'" } else { '' }
        throw "No debugger target found on port $Port$filter"
    }
    return $page
}

function Invoke-CodexDevToolsExpression {
    param(
        [Parameter(Mandatory)][string]$WebSocketDebuggerUrl,
        [Parameter(Mandatory)][string]$Expression
    )

    $client = [System.Net.WebSockets.ClientWebSocket]::new()
    try {
        $client.ConnectAsync([Uri]$WebSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null

        $command = @{
            id = 1
            method = 'Runtime.evaluate'
            params = @{
                expression = $Expression
                awaitPromise = $true
                returnByValue = $true
            }
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

            $text = [Text.Encoding]::UTF8.GetString($message.ToArray())
            if ([string]::IsNullOrWhiteSpace($text)) {
                continue
            }

            $payload = $text | ConvertFrom-Json
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

$page = Get-CodexDevToolsPage -Port $Port -Title $Title -Url $Url -Id $Id
$response = Invoke-CodexDevToolsExpression -WebSocketDebuggerUrl $page.webSocketDebuggerUrl -Expression $Expression
$response | ConvertTo-Json -Depth 20
