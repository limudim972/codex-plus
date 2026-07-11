function Get-CodexStateSqlitePath {
    Join-Path $env:USERPROFILE '.codex\state_5.sqlite'
}

function Get-CodexDevSqlitePath {
    Join-Path $env:USERPROFILE '.codex\sqlite\codex-dev.db'
}

function Get-CodexRecentThreadSnapshot {
    $dbPath = Get-CodexDevSqlitePath
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
        thread_id,
        display_title,
        cwd,
        source_kind,
        source_detail,
        CASE
            WHEN source_updated_at IS NOT NULL AND source_updated_at > 0 THEN CAST(source_updated_at * 1000 AS INTEGER)
            WHEN source_created_at IS NOT NULL AND source_created_at > 0 THEN CAST(source_created_at * 1000 AS INTEGER)
            ELSE 0
        END AS last_modified_ms
    FROM local_thread_catalog
    WHERE host_id = 'local'
      AND missing_candidate = 0
      AND display_title IS NOT NULL
      AND TRIM(display_title) != ''
    ORDER BY last_modified_ms DESC, observation_sequence DESC, display_title ASC
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
        "title": display_title,
        "display_title": display_title,
        "cwd": normalize_cwd(cwd),
        "source_kind": source_kind,
        "source_detail": source_detail,
        "last_modified_ms": last_modified_ms,
    }
    for thread_id, display_title, cwd, source_kind, source_detail, last_modified_ms in rows
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
