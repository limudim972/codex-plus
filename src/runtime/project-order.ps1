function Get-CodexStateSqlitePath {
    Join-Path $env:USERPROFILE '.codex\state_5.sqlite'
}

function Get-CodexDevSqlitePath {
    Join-Path $env:USERPROFILE '.codex\sqlite\codex-dev.db'
}

function Get-CodexRecentThreadSnapshot {
    $stateDbPath = Get-CodexStateSqlitePath
    $pythonCommand = Get-Command -Name python -ErrorAction SilentlyContinue
    if ($pythonCommand -and (Test-Path -LiteralPath $stateDbPath)) {
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
        source,
        created_at_ms,
        updated_at_ms
    FROM threads
    WHERE archived = 0
      AND title IS NOT NULL
      AND TRIM(title) != ''
      AND cwd IS NOT NULL
      AND TRIM(cwd) != ''
    ORDER BY
        COALESCE(NULLIF(updated_at_ms, 0), NULLIF(created_at_ms, 0), 0) DESC,
        updated_at_ms DESC,
        created_at_ms DESC,
        title ASC
    LIMIT 12
    """
).fetchall()

def normalize_cwd(value):
    if not value:
        return value
    if value.startswith("\\\\?\\"):
        value = value[4:]
    return value.replace("/", "\\")

print(json.dumps([
    {
        "id": thread_id,
        "title": title,
        "display_title": title,
        "cwd": normalize_cwd(cwd),
        "source_kind": source,
        "source_detail": source,
        "last_modified_ms": int(updated_at_ms or created_at_ms or 0),
    }
    for thread_id, title, cwd, source, created_at_ms, updated_at_ms in rows
], ensure_ascii=True))
'@

        try {
            $raw = @($script) | & $pythonCommand.Source - $stateDbPath
            if ($raw) {
                $parsed = $raw | ConvertFrom-Json
                return @($parsed)
            }
        } catch {
        }
    }

    $dbPath = Get-CodexDevSqlitePath
    if (-not (Test-Path -LiteralPath $dbPath)) {
        return @()
    }

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

function Get-CodexProjectTimestampSnapshot {
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
        cwd,
        MAX(COALESCE(NULLIF(updated_at_ms, 0), NULLIF(created_at_ms, 0), 0)) AS last_modified_ms
    FROM threads
    WHERE archived = 0
      AND cwd IS NOT NULL
      AND TRIM(cwd) != ''
    GROUP BY cwd
    """
).fetchall()

def normalize_cwd(value):
    if not value:
        return ''
    if value.startswith("\\\\?\\"):
        value = value[4:]
    return value.replace("/", "\\").rstrip("\\").lower()

project_timestamps = {}
for cwd, last_modified_ms in rows:
    normalized_cwd = normalize_cwd(cwd)
    if not normalized_cwd:
        continue
    timestamp_ms = int(last_modified_ms or 0)
    if timestamp_ms <= 0:
        continue
    current = project_timestamps.get(normalized_cwd, 0)
    if timestamp_ms > current:
        project_timestamps[normalized_cwd] = timestamp_ms

print(json.dumps([
    {
        "cwd": cwd,
        "last_modified_ms": last_modified_ms,
    }
    for cwd, last_modified_ms in sorted(project_timestamps.items(), key=lambda item: (-item[1], item[0]))
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
