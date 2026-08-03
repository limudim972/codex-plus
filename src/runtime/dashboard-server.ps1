param(
    [Parameter(Mandatory)][string]$DashboardRoot,
    [int]$Port = 3000,
    [AllowEmptyString()][string]$LauncherKey
)

$ErrorActionPreference = 'SilentlyContinue'
$sessionsRoot = Join-Path $env:USERPROFILE '.codex\sessions'
$sessionIndexPath = Join-Path $env:USERPROFILE '.codex\session_index.jsonl'
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")

function Get-ThreadIdFromFileName {
    param([string]$Name)
    $match = [regex]::Match($Name, '(?<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})', 'IgnoreCase')
    if ($match.Success) { return $match.Groups['id'].Value }
    return [System.IO.Path]::GetFileNameWithoutExtension($Name)
}

function Get-EventPayload {
    param($Object)
    if ($Object.payload -is [pscustomobject]) { return $Object.payload }
    if ($Object.event_msg -is [pscustomobject]) { return $Object.event_msg }
    return $null
}

function Get-ModelFromEvent {
    param($Object)
    $payload = Get-EventPayload $Object
    if ($payload -and $payload.type -eq 'turn_context' -and $payload.model) { return ([string]$payload.model).ToLowerInvariant() }
    return $null
}

function Get-EffortFromEvent {
    param($Object)
    $payload = Get-EventPayload $Object
    if ($payload -and $payload.type -eq 'turn_context' -and $payload.effort) { return [string]$payload.effort }
    return $null
}

function Get-TokenEvent {
    param($Object)
    $payload = Get-EventPayload $Object
    if ($Object.event_msg -and $Object.event_msg.type -eq 'token_count') {
        return [pscustomobject]@{ Input = [double]$Object.event_msg.input_tokens; Cached = [double]$Object.event_msg.cached_input_tokens; Output = [double]$Object.event_msg.output_tokens; Reasoning = 0; Absolute = $false }
    }
    if (-not $payload -or $payload.type -ne 'token_count') { return $null }
    $info = $payload.info
    if ($info.total_token_usage) {
        $t = $info.total_token_usage
        return [pscustomobject]@{ Input = [double]$t.input_tokens; Cached = [double]$t.cached_input_tokens; Output = [double]$t.output_tokens; Reasoning = [double]$t.reasoning_output_tokens; Absolute = $true }
    }
    if ($info.last_token_usage) {
        $t = $info.last_token_usage
        return [pscustomobject]@{ Input = [double]$t.input_tokens; Cached = [double]$t.cached_input_tokens; Output = [double]$t.output_tokens; Reasoning = [double]$t.reasoning_output_tokens; Absolute = $false }
    }
    return $null
}

function Get-Credits {
    param([string]$Model, [double]$Uncached, [double]$Cached, [double]$Output)
    $inRate = 125; $cacheRate = 12.5; $outRate = 750
    $name = ([string]$Model).ToLowerInvariant()
    if ($name -match 'gpt-5\.6[- ]terra') { $inRate = 62.5; $cacheRate = 6.25; $outRate = 375 }
    elseif ($name -match 'gpt-5\.6[- ]luna') { $inRate = 25; $cacheRate = 2.5; $outRate = 150 }
    elseif ($name -match 'gpt-5\.4[- ]mini') { $inRate = 18.75; $cacheRate = 1.875; $outRate = 113 }
    elseif ($name -match 'gpt-5\.4') { $inRate = 62.5; $cacheRate = 6.25; $outRate = 375 }
    return [pscustomobject]@{
        Total = ($Uncached / 1e6) * $inRate + ($Cached / 1e6) * $cacheRate + ($Output / 1e6) * $outRate
        Uncached = ($Uncached / 1e6) * $inRate
        Cached = ($Cached / 1e6) * $cacheRate
        Output = ($Output / 1e6) * $outRate
    }
}

function Get-MessageText {
    param($Object)
    $payload = Get-EventPayload $Object
    if ($Object.type -eq 'response_item' -and $payload.type -eq 'message' -and $payload.content -is [array]) {
        $text = @($payload.content | Where-Object { $_.type -eq 'output_text' -and $_.text } | ForEach-Object { $_.text }) -join "`n"
        if ($text.Trim()) { return $text.Trim() }
    }
    if ($payload.type -eq 'agent_message' -and $payload.message) { return ([string]$payload.message).Trim() }
    if ($payload.type -eq 'task_complete' -and $payload.last_agent_message) { return ([string]$payload.last_agent_message).Trim() }
    return $null
}

function Get-DateTimeFromJsonTimestamp {
    param($Value)
    try { return [DateTime]::Parse([string]$Value).ToLocalTime() } catch { return $null }
}

function Get-PeriodBounds {
    param([string]$Period)
    $now = [DateTime]::Now
    switch ($Period) {
        'today' { return @($now.Date, $now.Date.AddDays(1).AddTicks(-1)) }
        'last_7_days' { return @($now.Date.AddDays(-6), $now.Date.AddDays(1).AddTicks(-1)) }
        'last_30_days' { return @($now.Date.AddDays(-29), $now.Date.AddDays(1).AddTicks(-1)) }
        'current_5_hour' { return @($now.AddHours(-5), $now) }
        'previous_5_hour' { return @($now.AddHours(-10), $now.AddHours(-5)) }
        'all_time' { return @([DateTime]::MinValue, $now) }
        'current_week' { return @($now.Date.AddDays(-6), $now) }
        default { return @($now.Date.AddDays(-13), $now.Date.AddDays(-6).AddTicks(-1)) }
    }
}

function Get-TitleIndex {
    $result = @{}
    if (-not (Test-Path -LiteralPath $sessionIndexPath)) { return $result }
    foreach ($line in Get-Content -LiteralPath $sessionIndexPath -ErrorAction SilentlyContinue) {
        try { $obj = $line | ConvertFrom-Json } catch { continue }
        if ($obj.id -and $obj.thread_name) { $result[[string]$obj.id] = [string]$obj.thread_name }
    }
    return $result
}

function Get-SessionFilesInRange {
    param([DateTime]$Start, [DateTime]$End)
    $scanStart = if ($Start -eq [DateTime]::MinValue) { [DateTime]::Now.Date.AddYears(-1) } else { $Start.Date }
    $scanEnd = [Math]::Min($End.Ticks, [DateTime]::Now.Ticks)
    $cursor = $scanStart
    $files = @()
    while ($cursor.Ticks -le $scanEnd) {
        $dayRoot = Join-Path $sessionsRoot (Join-Path $cursor.ToString('yyyy') (Join-Path $cursor.ToString('MM') $cursor.ToString('dd')))
        if (Test-Path -LiteralPath $dayRoot) { $files += @(Get-ChildItem -LiteralPath $dayRoot -Filter *.jsonl -File -ErrorAction SilentlyContinue) }
        $cursor = $cursor.AddDays(1)
    }
    return $files
}

function Get-ThreadData {
    param([string]$Period)
    $bounds = Get-PeriodBounds $Period
    $start = $bounds[0]; $end = $bounds[1]
    $titleIndex = Get-TitleIndex
    $threads = @{}
    foreach ($file in @(Get-SessionFilesInRange $start $end)) {
        $threadId = Get-ThreadIdFromFileName $file.Name
        $state = [ordered]@{ id=$threadId; input=0; cached=0; output=0; reasoning=0; effort=$null; model=$null; models=@(); messages=@(); firstPrim=$null; lastPrim=$null; firstSec=$null; lastSec=$null; updated=$null; jsonlCredits=0; jsonlUncached=0; jsonlCached=0; jsonlOutput=0; previousInput=0; previousCached=0; previousOutput=0; previousReasoning=0 }
        foreach ($line in Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue) {
            try { $obj = $line | ConvertFrom-Json } catch { continue }
            $timestamp = Get-DateTimeFromJsonTimestamp $obj.timestamp
            if (-not $timestamp -or $timestamp -lt $start -or $timestamp -gt $end) { continue }
            if (-not $state.updated -or $timestamp -gt $state.updated) { $state.updated = $timestamp }
            $model = Get-ModelFromEvent $obj
            if ($model) { $state.model = $model; if ($state.models -notcontains $model) { $state.models += $model } }
            $effort = Get-EffortFromEvent $obj
            if ($effort) { $state.effort = $effort }
            $tokens = Get-TokenEvent $obj
            if ($tokens) {
                if ($tokens.Absolute) {
                    $di = [Math]::Max(0, $tokens.Input - $state.previousInput); $dc = [Math]::Max(0, $tokens.Cached - $state.previousCached); $do = [Math]::Max(0, $tokens.Output - $state.previousOutput); $dr = [Math]::Max(0, $tokens.Reasoning - $state.previousReasoning)
                    $state.previousInput = $tokens.Input; $state.previousCached = $tokens.Cached; $state.previousOutput = $tokens.Output; $state.previousReasoning = $tokens.Reasoning
                } else { $di = $tokens.Input; $dc = $tokens.Cached; $do = $tokens.Output; $dr = $tokens.Reasoning }
                $state.input += $di; $state.cached += $dc; $state.output += $do; $state.reasoning += $dr
                $credits = Get-Credits $state.model ([Math]::Max(0, $di - $dc)) $dc $do
                $state.jsonlCredits += $credits.Total; $state.jsonlUncached += $credits.Uncached; $state.jsonlCached += $credits.Cached; $state.jsonlOutput += $credits.Output
            }
            $message = Get-MessageText $obj
            if ($message) { $state.messages += [ordered]@{ type=([string]$obj.type); timestamp=([string]$obj.timestamp); text=$message } }
            $payload = Get-EventPayload $obj
            $limits = if ($payload) { $payload.rate_limits } else { $null }
            if ($limits) {
                if ($limits.primary.used_percent -ne $null) { if ($state.firstPrim -eq $null) { $state.firstPrim = $limits.primary.used_percent }; $state.lastPrim = $limits.primary.used_percent }
                if ($limits.secondary.used_percent -ne $null) { if ($state.firstSec -eq $null) { $state.firstSec = $limits.secondary.used_percent }; $state.lastSec = $limits.secondary.used_percent }
            }
        }
        if ($state.input + $state.output -le 0) { continue }
        $calculated = Get-Credits $state.model ([Math]::Max(0, $state.input - $state.cached)) $state.cached $state.output
        $updated = if ($state.updated) { $state.updated } else { $file.LastWriteTime }
        $threads[$threadId] = [ordered]@{
            id=$threadId; title=if ($titleIndex.ContainsKey($threadId)) { $titleIndex[$threadId] } else { $null }; title_jsonl=if ($titleIndex.ContainsKey($threadId)) { $titleIndex[$threadId] } else { $null }; tokens_used=($state.input + $state.output); input_tokens=$state.input; cached_tokens=$state.cached; uncached_tokens=([Math]::Max(0, $state.input - $state.cached)); output_tokens=$state.output; reasoning_tokens=$state.reasoning; effort=if ($state.effort) { $state.effort } else { '-' }; first_prim=$state.firstPrim; last_prim=$state.lastPrim; first_sec=$state.firstSec; last_sec=$state.lastSec; updated_at=([DateTimeOffset]$updated).ToUnixTimeMilliseconds(); reset_week=('Week ending ' + $updated.ToString('MMM dd')); model=$state.model; model_jsonl=$state.model; models_jsonl=$state.models; messages_jsonl=$state.messages; credits=$calculated.Total; uncached_credits=$calculated.Uncached; cached_credits=$calculated.Cached; output_credits=$calculated.Output; credits_jsonl=$state.jsonlCredits; uncached_credits_jsonl=$state.jsonlUncached; cached_credits_jsonl=$state.jsonlCached; output_credits_jsonl=$state.jsonlOutput
        }
    }
    $data = @($threads.Values | Sort-Object updated_at -Descending)
    $totalTokens = 0
    foreach ($item in $data) { $totalTokens += [double]$item.tokens_used }
    return [ordered]@{ success=$true; data=$data; total_tokens=$totalTokens; start_date=$start.ToString('o'); end_date=$end.ToString('o') }
}

function Get-Summary {
    $latest = Get-ChildItem -LiteralPath $sessionsRoot -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $primary = @{}; $secondary = @{}
    if ($latest) {
        foreach ($line in Get-Content -LiteralPath $latest.FullName -ErrorAction SilentlyContinue) {
            try { $obj = $line | ConvertFrom-Json } catch { continue }
            $payload = Get-EventPayload $obj
            if ($payload.rate_limits) { $p=$payload.rate_limits.primary; $s=$payload.rate_limits.secondary; if ($p) { $primary=@{ used_percent=$p.used_percent; resets_at=$p.resets_at } }; if ($s) { $secondary=@{ used_percent=$s.used_percent; resets_at=$s.resets_at } } }
        }
    }
    $files = @(Get-ChildItem -LiteralPath $sessionsRoot -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue)
    return [ordered]@{ success=$true; data=[ordered]@{ primary_window=$primary; secondary_window=$secondary; reset_credits=@{ ok=$false; available_count=$null; credits_returned=$null; next_available_reset=$null; next_available_reset_local=$null }; local_usage=@{ sessions_scanned=$files.Count; threads_seen=@($files | ForEach-Object { Get-ThreadIdFromFileName $_.Name } | Sort-Object -Unique).Count } } }
}

function Write-Response {
    param($Context, [int]$StatusCode, [string]$ContentType, [byte[]]$Bytes)
    $Context.Response.StatusCode = $StatusCode; $Context.Response.ContentType = $ContentType; $Context.Response.ContentLength64 = $Bytes.Length; $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length); $Context.Response.Close()
}

try {
    $listener.Start()
    while ($true) {
        $context = $listener.GetContext()
        try {
            $path = $context.Request.Url.AbsolutePath
            if ($path -eq '/api/summary') { $body = (Get-Summary | ConvertTo-Json -Depth 20 -Compress); Write-Response $context 200 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($body)); continue }
            if ($path -eq '/api/threads') { $period = $context.Request.QueryString['period']; if (-not $period) { $period='last_week' }; $body = (Get-ThreadData $period | ConvertTo-Json -Depth 20 -Compress); Write-Response $context 200 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($body)); continue }
            $relative = if ($path -eq '/') { 'index.html' } else { $path.TrimStart('/') }
            $file = [IO.Path]::GetFullPath((Join-Path $DashboardRoot $relative)); $root = [IO.Path]::GetFullPath($DashboardRoot)
            if (-not $file.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-Response $context 404 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('Not found')); continue }
            $types = @{ '.html'='text/html; charset=utf-8'; '.css'='text/css; charset=utf-8'; '.js'='application/javascript; charset=utf-8'; '.png'='image/png'; '.jpg'='image/jpeg' }
            $type = if ($types.ContainsKey([IO.Path]::GetExtension($file))) { $types[[IO.Path]::GetExtension($file)] } else { 'application/octet-stream' }
            Write-Response $context 200 $type ([IO.File]::ReadAllBytes($file))
        } catch { try { Write-Response $context 500 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($_.Exception.Message)) } catch {} }
    }
} finally { if ($listener.IsListening) { $listener.Stop() }; $listener.Close() }
