#!/usr/bin/env python3
"""Extract all prefab names from DST's scripts/prefabs/*.lua.

Usage: extract_prefab_names.py <path-to-scripts/prefabs-dir>

Handles both direct constructors  Prefab("name", ...)  and factory patterns
where the file builds  Prefab(name, ...)  from a parameter and passes literal
names at the tail return, either as  MakeThing("name")  or  {name = "name"}.
Prints a sorted, deduplicated list to stdout. See PREFAB_LIST.md for caveats.
"""
import re
import sys
import glob
import os

direct_re = re.compile(r'Prefab\(\s*"([A-Za-z0-9_]+)"', re.S)
call_re = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)\(\s*"([a-z0-9_]+)"')
named_re = re.compile(r'\bname\s*=\s*"([a-z0-9_]+)"')
factory_re = re.compile(r'Prefab\(\s*[a-z_][A-Za-z0-9_.]*\s*[,)]')
NONPREFAB = {"require", "unpack", "Asset", "print", "pairs", "ipairs",
             "STRINGS", "GetString", "Prefab"}


def extract(prefabs_dir):
    names = set()
    for path in glob.glob(os.path.join(prefabs_dir, "*.lua")):
        with open(path, encoding="utf-8", errors="replace") as f:
            src = f.read()
        for m in direct_re.finditer(src):
            names.add(m.group(1))
        if factory_re.search(src):
            idx = src.rfind("\nreturn")
            if idx == -1 and src.startswith("return"):
                idx = 0
            if idx != -1:
                tail = src[idx:]
                for fn, lit in call_re.findall(tail):
                    if fn not in NONPREFAB:
                        names.add(lit)
                for lit in named_re.findall(tail):
                    names.add(lit)
    # drop suffix fragments the tail heuristic occasionally picks up
    return sorted(n for n in names if not n.startswith("_"))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    for name in extract(sys.argv[1]):
        print(name)
