#!/usr/bin/env bash
# Fail if lic C runtime config loader gained strcmp keys beyond the frozen set.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FREEZE="$ROOT/data/c-runtime-config-keys.freeze"
LIC_RT="${LIC_ROOT:-/workspace/lic}/runtime/li_rt_net.c"

fail() { echo "lint-frozen-c-config-keys: $*" >&2; exit 1; }

test -f "$FREEZE" || fail "missing freeze file: $FREEZE"
test -f "$LIC_RT" || fail "missing C loader (set LIC_ROOT): $LIC_RT"

mapfile -t frozen < <(grep -vE '^\s*#' "$FREEZE" | grep -vE '^\s*$' | sort -u)
mapfile -t live < <(python3 - "$LIC_RT" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
start = text.find("int32_t httpd_load_runtime_config_i")
if start < 0:
    raise SystemExit("httpd_load_runtime_config_i not found")
end = text.find("\nint32_t ", start + 20)
if end < 0:
    end = len(text)
chunk = text[start:end]
keys = sorted(set(re.findall(r'strcmp\(key,\s*"([^"]+)"\)', chunk)))
for k in keys:
    print(k)
PY
)

extra=()
for k in "${live[@]}"; do
  if ! printf '%s\n' "${frozen[@]}" | grep -qxF "$k"; then
    extra+=("$k")
  fi
done

missing=()
for k in "${frozen[@]}"; do
  if ! printf '%s\n' "${live[@]}" | grep -qxF "$k"; then
    missing+=("$k")
  fi
done

if (( ${#extra[@]} > 0 )); then
  echo "lint-frozen-c-config-keys: new C config keys (add in Li, not C):" >&2
  printf '  %s\n' "${extra[@]}" >&2
  exit 1
fi
if (( ${#missing[@]} > 0 )); then
  echo "lint-frozen-c-config-keys: frozen keys removed from C loader (update freeze file):" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

echo "lint-frozen-c-config-keys: OK (${#live[@]} keys)"
