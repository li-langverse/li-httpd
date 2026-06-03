#!/usr/bin/env python3
"""SQL migration subset parser → sensitive JSONPath hints for leak_censor setup."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

SENSITIVE_COLUMN_NAMES = frozenset(
    {
        "password",
        "password_hash",
        "secret",
        "secret_value",
        "token",
        "api_key",
        "private_key",
        "ssn",
        "access_token",
        "refresh_token",
    }
)

CREATE_TABLE_RE = re.compile(
    r"create\s+table\s+(?:if\s+not\s+exists\s+)?([`\"']?)(\w+)\1\s*\(",
    re.IGNORECASE,
)
ALTER_ADD_RE = re.compile(
    r"alter\s+table\s+(?:if\s+exists\s+)?([`\"']?)(\w+)\1\s+add\s+(?:column\s+)?([`\"']?)(\w+)\3",
    re.IGNORECASE,
)
LI_CENSOR_RE = re.compile(r"--\s*li:censor\b", re.IGNORECASE)


@dataclass
class SchemaCatalog:
    """Sensitive columns discovered from migrations."""

    json_paths: list[str] = field(default_factory=list)
    header_deny: list[str] = field(default_factory=list)
    sources: list[str] = field(default_factory=list)


def _table_json_paths(table: str, column: str) -> list[str]:
    t = table.strip().lower()
    c = column.strip().lower()
    return [
        f"$.{t}[*].{c}",
        f"$.{t}.{c}",
        f"$.{c}",
    ]


def _is_sensitive(table: str, column: str, marked: bool) -> bool:
    if marked:
        return True
    col = column.strip().lower()
    if col in SENSITIVE_COLUMN_NAMES:
        return True
    for hint in SENSITIVE_COLUMN_NAMES:
        if hint in col:
            return True
    return False


def _parse_create_block(sql: str, table: str, start: int) -> list[tuple[str, bool]]:
    """Return (column, li_censor_marked) from CREATE TABLE (...)."""
    depth = 0
    cols: list[tuple[str, bool]] = []
    i = start
    n = len(sql)
    line_marked = False
    col_buf: list[str] = []
    while i < n:
        ch = sql[i]
        if ch == "(":
            depth += 1
            if depth == 1:
                i += 1
                continue
        elif ch == ")":
            depth -= 1
            if depth == 0:
                break
        if depth == 1:
            if ch == "\n":
                chunk = "".join(col_buf).strip()
                col_buf = []
                if LI_CENSOR_RE.search(chunk):
                    line_marked = True
                if chunk and not chunk.startswith("--"):
                    parts = chunk.split()
                    if parts and parts[0].lower() not in (
                        "primary",
                        "foreign",
                        "unique",
                        "check",
                        "constraint",
                    ):
                        col_name = parts[0].strip("`\"'")
                        if col_name:
                            cols.append((col_name, line_marked))
                line_marked = False
                i += 1
                continue
            col_buf.append(ch)
        i += 1
    return cols


def parse_sql_file(path: Path) -> SchemaCatalog:
    text = path.read_text(encoding="utf-8")
    return parse_sql_text(text, source=str(path.name))


def parse_sql_text(text: str, source: str = "") -> SchemaCatalog:
    catalog = SchemaCatalog()
    sql = text
    for m in CREATE_TABLE_RE.finditer(sql):
        table = m.group(2)
        cols = _parse_create_block(sql, table, m.end() - 1)
        for col, marked in cols:
            if _is_sensitive(table, col, marked):
                for p in _table_json_paths(table, col):
                    if p not in catalog.json_paths:
                        catalog.json_paths.append(p)
                if source and source not in catalog.sources:
                    catalog.sources.append(source)

    for m in ALTER_ADD_RE.finditer(sql):
        table = m.group(2)
        col = m.group(4)
        window_start = max(0, m.start() - 80)
        marked = LI_CENSOR_RE.search(sql[window_start : m.start()]) is not None
        if _is_sensitive(table, col, marked):
            for p in _table_json_paths(table, col):
                if p not in catalog.json_paths:
                    catalog.json_paths.append(p)
            if source and source not in catalog.sources:
                catalog.sources.append(source)

    catalog.header_deny.append("x-internal-api-key")
    return catalog


def load_applied_manifest(manifest_path: Path) -> list[str]:
    """Return migration basenames listed in migrations_applied.toml."""
    data: dict[str, Any] = tomllib.loads(manifest_path.read_text(encoding="utf-8"))
    applied = data.get("applied")
    if applied is None:
        block = data.get("migrations")
        if isinstance(block, dict):
            applied = block.get("applied")
    if not isinstance(applied, list):
        raise ValueError(
            f"{manifest_path}: expected applied = [\"001_init.sql\", ...] or [migrations] applied = [...]"
        )
    out: list[str] = []
    for item in applied:
        name = Path(str(item).strip()).name
        if name:
            out.append(name)
    return out


def parse_migrations_dir(
    migrations_dir: Path,
    applied_only: list[str] | None = None,
) -> SchemaCatalog:
    merged = SchemaCatalog()
    if not migrations_dir.is_dir():
        return merged
    allowed = {Path(n).name for n in applied_only} if applied_only else None
    for path in sorted(migrations_dir.glob("*.sql")):
        if allowed is not None and path.name not in allowed:
            continue
        part = parse_sql_file(path)
        for p in part.json_paths:
            if p not in merged.json_paths:
                merged.json_paths.append(p)
        for h in part.header_deny:
            if h not in merged.header_deny:
                merged.header_deny.append(h)
        merged.sources.extend(part.sources)
    return merged


def agent_route_default_paths() -> list[str]:
    return ["$.choices[*].message.tool_calls[*].raw_stderr"]


def merge_catalog(base: SchemaCatalog) -> SchemaCatalog:
    out = SchemaCatalog(
        json_paths=list(base.json_paths),
        header_deny=list(base.header_deny),
        sources=list(base.sources),
    )
    for p in agent_route_default_paths():
        if p not in out.json_paths:
            out.json_paths.append(p)
    return out
