"""Do the tests have teeth? Breaks one rule at a time in a copy of the addon and checks that
the scenarios notice.

Usage: python mutate.py"""
import io, os, shutil, subprocess, sys, tempfile

tests = os.path.dirname(os.path.abspath(__file__))
addon = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(tests)
src = io.open(os.path.join(addon, "WarDrum.lua"), encoding="utf-8").read()
MUTATIONS = [
    ("own faction listed from the meter", ' and name ~= myName and not ownSide[name] then', ' and name ~= myName then'),
    ("yourself listed from the meter", ' and name ~= "" and name ~= myName and', ' and name ~= "" and'),
    ("battlegrounds count", '\treturn kind == "pvp" or kind == "arena"', '\treturn false'),
    ("same session counted twice", 'local fresh = signature ~= db.lastSession', 'local fresh = true'),
    ("struck-first ignored", "if (rawKey and started[rawKey]) or (info.name and startedName[info.name]) then return end", ""),
    ("struck-first ignored by the meter", '\t\t\tif startedName[name] then\n\t\t\t\tLog("not listed: you attacked " .. name .. " first")\n\t\t\telse\n\t\t\t\tDamagedBy(name, f.class, f.amount)\n\t\t\tend', '\t\t\tDamagedBy(name, f.class, f.amount)'),
    ("warned every time", "local WARN_AGAIN = 60", "local WARN_AGAIN = 0"),
    ("warned about corpses", 'if Opt("alert") and not info.dead and (', 'if Opt("alert") and ('),
    ("warned right after an attack", "\tnearAt[key] = GetTime()\n\twarnedAt[key] = GetTime()\n", ""),
    ("hidden meter line touched", "\t\tspell = Plain(spell)\n", ""),
    ("any dead listed player is your kill", "if info.dead and key == lastTargetKey and", "if info.dead and"),
    ("honor always your kill", "if e and not alive and e.lastAttack", "if e and e.lastAttack"),
    ("death outside a fight credited", "local thisFight = found ~= nil and ((inCombat and signature ~= db.lastSession) or (not inCombat and now - fightEndedAt < 5))", "local thisFight = found ~= nil"),
    ("fallback kill never put right", "if death and not death.settled and death.at >= fightStartedAt then", "if false then"),
    ("never taken back", 'if not hidden and Opt("onlyDamage") then', "if false then"),
    ("taken back although the meter was hidden", 'if not hidden and Opt("onlyDamage") then', 'if Opt("onlyDamage") then'),
    ("attack counted every scan", "if not counted[key] and (not e.lastAttack or now - e.lastAttack >= ATTACK_AGAIN) then", "if true then"),
    ("meter name makes a second entry", "\t\tfor _, e in pairs(db.players) do FillFromGUID(e) end -- (names and classes the game hid during the fight)\n\t\tTidy()\n\t\tSettle()", "\t\tSettle()"),
    ("first version's guesses kept", "if e.kills == 0 and not e.confirmed then db.players[key] = nil end", ""),
    ("/wd alone does nothing", 'if cmd == "" or cmd == "options" or', 'if cmd == "options" or'),
    ("/wd hide shows the list", 'ShowWindow(cmd == "show")', 'ShowWindow(true)'),
    ("unreadable meter asked forever", "if not again and C_Timer and C_Timer.After then", "if C_Timer and C_Timer.After then"),
    ("scale moves the list", "pos[1] / s, pos[2] / s)", "pos[1], pos[2])"),
    ("lock ignored", 'local function dragStart() if not Opt("lock") then w:StartMoving() end end', "local function dragStart() w:StartMoving() end"),
    ("sample players saved", "\tif demo then\n\t\tfor i, e in ipairs(SAMPLE) do list[i] = {e = e} end\n\t\treturn list\n\tend\n", '\tif demo then for i, e in ipairs(SAMPLE) do db.players["s" .. i] = e end end\n'),
]
missed = 0
for name, old, new in MUTATIONS:
    if src.count(old) != 1:
        print("?? %-45s the text to change was found %d times" % (name, src.count(old)))
        missed += 1
        continue
    d = tempfile.mkdtemp()
    io.open(os.path.join(d, "WarDrum.lua"), "w", encoding="utf-8").write(src.replace(old, new))
    r = subprocess.run([sys.executable, "-I", os.path.join(tests, "harness.py"), d], capture_output=True, text=True)
    shutil.rmtree(d)
    failed = [l.split()[1] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if failed:
        print("caught  %-45s by %s" % (name, ", ".join(f[:2] for f in failed)))
    else:
        print("MISSED  %-45s" % name)
        missed += 1
print("%d of %d broken rules were noticed" % (len(MUTATIONS) - missed, len(MUTATIONS)))
