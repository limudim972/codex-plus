function Get-CodexStateSqlitePath {
    Join-Path $env:USERPROFILE '.codex\state_5.sqlite'
}

function Get-CodexProjectOrderSnapshot {
    $dbPath = Get-CodexStateSqlitePath
    if (-not (Test-Path -LiteralPath $dbPath)) {
        return @()
    }

    $pythonCommand = Get-Command -Name python -ErrorAction SilentlyContinue
    if (-not $pythonCommand) {
        return @()
    }

    $script = @'
import json
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
cur = conn.cursor()

rows = cur.execute(
    """
    SELECT cwd, MAX(
        CASE
            WHEN updated_at_ms IS NOT NULL AND updated_at_ms > 0 THEN updated_at_ms
            WHEN updated_at IS NOT NULL AND updated_at > 0 THEN updated_at * 1000
            ELSE 0
        END
    ) AS last_modified_ms
    FROM threads
    WHERE cwd IS NOT NULL AND TRIM(cwd) != ''
    GROUP BY cwd
    ORDER BY last_modified_ms DESC, cwd ASC
    """
).fetchall()

def normalize_cwd(value):
    if not value:
        return value
    if value.startswith("\\\\?\\"):
        return value[4:]
    return value

print(json.dumps([
    {"cwd": normalize_cwd(cwd), "last_modified_ms": last_modified_ms}
    for cwd, last_modified_ms in rows
], ensure_ascii=True))
'@

    try {
        $raw = @($script) | & $pythonCommand.Source - $dbPath
        if (-not $raw) {
            return @()
        }

        $parsed = $raw | ConvertFrom-Json
        return @($parsed)
    } catch {
        return @()
    }
}

function Get-CodexRecentThreadSnapshot {
    $dbPath = Get-CodexStateSqlitePath
    if (-not (Test-Path -LiteralPath $dbPath)) {
        return @()
    }

    $pythonCommand = Get-Command -Name python -ErrorAction SilentlyContinue
    if (-not $pythonCommand) {
        return @()
    }

    $script = @'
import json
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
cur = conn.cursor()

rows = cur.execute(
    """
    SELECT
        id,
        title,
        cwd,
        CASE
            WHEN updated_at_ms IS NOT NULL AND updated_at_ms > 0 THEN updated_at_ms
            WHEN updated_at IS NOT NULL AND updated_at > 0 THEN updated_at * 1000
            ELSE 0
        END AS last_modified_ms
    FROM threads
    WHERE archived = 0
      AND title IS NOT NULL
      AND TRIM(title) != ''
    ORDER BY last_modified_ms DESC, title ASC
    LIMIT 12
    """
).fetchall()

def normalize_cwd(value):
    if not value:
        return value
    if value.startswith("\\\\?\\"):
        return value[4:]
    return value

print(json.dumps([
    {
        "id": thread_id,
        "title": title,
        "cwd": normalize_cwd(cwd),
        "last_modified_ms": last_modified_ms,
    }
    for thread_id, title, cwd, last_modified_ms in rows
], ensure_ascii=True))
'@

    try {
        $raw = @($script) | & $pythonCommand.Source - $dbPath
        if (-not $raw) {
            return @()
        }

        $parsed = $raw | ConvertFrom-Json
        return @($parsed)
    } catch {
        return @()
    }
}
