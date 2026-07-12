function Get-CodexStateSqlitePath {
    Join-Path $env:USERPROFILE '.codex\state_5.sqlite'
}

function Get-CodexDevSqlitePath {
    Join-Path $env:USERPROFILE '.codex\sqlite\codex-dev.db'
}

function Get-CodexRecentThreadSnapshot {
    $pythonCommand = Get-Command -Name python -ErrorAction SilentlyContinue
    $stateDbPath = Get-CodexStateSqlitePath
    $devDbPath = Get-CodexDevSqlitePath
    if (-not $pythonCommand -or -not (Test-Path -LiteralPath $stateDbPath)) {
        return @()
    }

    $script = @'
import json
import sqlite3
import sys

state_db_path = sys.argv[1]
dev_db_path = sys.argv[2] if len(sys.argv) > 2 else ''
state_conn = sqlite3.connect(state_db_path)
state_cur = state_conn.cursor()

state_rows = state_cur.execute(
    """
    SELECT
        id,
        title,
        cwd,
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

display_titles = {}
if dev_db_path:
    try:
        dev_conn = sqlite3.connect(dev_db_path)
        dev_cur = dev_conn.cursor()
        for thread_id, display_title, source_kind, source_detail in dev_cur.execute(
            """
            SELECT
                thread_id,
                display_title,
                source_kind,
                source_detail
            FROM local_thread_catalog
            WHERE host_id = 'local'
              AND missing_candidate = 0
              AND thread_id IS NOT NULL
              AND TRIM(thread_id) != ''
            """
        ).fetchall():
            display_titles[str(thread_id).strip().lower()] = {
                "display_title": display_title,
                "source_kind": source_kind,
                "source_detail": source_detail,
            }
    except Exception:
        display_titles = {}

def normalize_cwd(value):
    if not value:
        return value
    if value.startswith("\\\\?\\"):
        value = value[4:]
    return value.replace("/", "\\")

print(json.dumps([
    {
        "id": thread_id,
        "title": (display_titles.get(str(thread_id).strip().lower(), {}) or {}).get("display_title") or title,
        "display_title": (display_titles.get(str(thread_id).strip().lower(), {}) or {}).get("display_title") or title,
        "cwd": normalize_cwd(cwd),
        "source_kind": (display_titles.get(str(thread_id).strip().lower(), {}) or {}).get("source_kind") or '',
        "source_detail": (display_titles.get(str(thread_id).strip().lower(), {}) or {}).get("source_detail") or '',
        "last_modified_ms": int(updated_at_ms or created_at_ms or 0),
    }
    for thread_id, title, cwd, created_at_ms, updated_at_ms in state_rows
], ensure_ascii=True))
'@

    try {
        $raw = @($script) | & $pythonCommand.Source - $stateDbPath $devDbPath
        if ($raw) {
            $parsed = $raw | ConvertFrom-Json
            return @($parsed)
        }
    } catch {
    }
    return @()
}

function Get-CodexProjectTimestampSnapshot {
    $stateDbPath = Get-CodexStateSqlitePath
    if (-not (Test-Path -LiteralPath $stateDbPath)) {
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
        $raw = @($script) | & $pythonCommand.Source - $stateDbPath
        if (-not $raw) {
            return @()
        }

        $parsed = $raw | ConvertFrom-Json
        return @($parsed)
    } catch {
        return @()
    }
}
