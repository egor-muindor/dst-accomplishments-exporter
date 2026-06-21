#!/usr/bin/env bash
# Continuously merge shard partials into one unified file (>= once/min).
# Usage: acm_merge_loop.sh <mod_dir> <cluster_root> <out_file> [period_seconds]
set -euo pipefail
MOD_DIR="${1:?mod dir}"; ROOT="${2:?cluster root}"; OUT="${3:?out file}"; PERIOD="${4:-30}"
eval "$(luarocks path 2>/dev/null || true)"   # put the dkjson rocks tree on LUA_PATH
export LUA_PATH="${MOD_DIR}/scripts/?.lua;${MOD_DIR}/tools/?.lua;${LUA_PATH:-;;}"
while true; do
  lua "${MOD_DIR}/tools/acm_merge.lua" --root "${ROOT}" --out "${OUT}" || echo "[acm] merge failed" >&2
  sleep "${PERIOD}"
done
