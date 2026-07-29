function Get-CodexPlusDebugPort {
    param(
        [int]$Port = 0
    )

    if ($Port -gt 0) {
        return $Port
    }

    $processes = Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match '--remote-debugging-port=\d+' -and
            $_.CommandLine -match '(?i)Codex Plus\\profile'
        } |
        Sort-Object CreationDate -Descending

    foreach ($process in $processes) {
        $match = [regex]::Match([string]$process.CommandLine, '--remote-debugging-port=(\d+)')
        if (-not $match.Success) { continue }

        $candidatePort = [int]$match.Groups[1].Value
        try {
            $pages = Invoke-RestMethod -Uri "http://127.0.0.1:$candidatePort/json/list" -UseBasicParsing
            $pageList = if ($pages -is [System.Array]) { $pages } else { $pages.value }
            if (@($pageList | Where-Object { $_.type -eq 'page' -and $_.url -like 'app://*' }).Count -gt 0) {
                return $candidatePort
            }
        } catch {
        }
    }

    throw 'No running Codex Plus DevTools port was found. Pass -Port explicitly when multiple windows are open.'
}
