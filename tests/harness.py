"""Runs War Drum against a tiny stand-in for the game, one scenario at a time.

Each scenario starts from scratch: fakegame.lua, then the addon itself, then the
scenario file. A scenario passes when it runs to its end without an error.

Usage:  python harness.py [addon folder] [part of a scenario's name]
Needs:  pip install lupa   (WoW runs Lua 5.1, so does this)
"""
import os
import sys

from lupa.lua51 import LuaRuntime

here = os.path.dirname(os.path.abspath(__file__))
addon = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.dirname(here)
only = sys.argv[2] if len(sys.argv) > 2 else ""


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def run(scenario):
    lua = LuaRuntime(unpack_returned_tuples=True)
    load = lua.eval(
        "function(src, name) local f, e = loadstring(src, name) if not f then error(e, 0) end return f() end"
    )
    load(read(os.path.join(here, "fakegame.lua")), "@fakegame.lua")
    load(read(os.path.join(addon, "WarDrum.lua")), "@WarDrum.lua")
    load(read(os.path.join(here, "scenarios", scenario)), "@" + scenario)


names = sorted(n for n in os.listdir(os.path.join(here, "scenarios")) if n.endswith(".lua") and only in n)
failed = 0
for name in names:
    try:
        run(name)
        print("ok    " + name[:-4])
    except Exception as problem:  # a failed assert, or an error inside the addon
        failed += 1
        print("FAIL  " + name[:-4])
        print("      " + str(problem).replace("\n", "\n      "))
print("passed %d, failed %d" % (len(names) - failed, failed))
sys.exit(1 if failed or not names else 0)
