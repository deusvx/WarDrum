-- During a fight the game may hide names, levels, even ids. Nothing hidden may be
-- touched (the stand-in raises an error if it is), and whatever was hidden is
-- filled in once it can be read.
start()

-- a mage whose name, class and level are hidden: listed by her id, filled in after the fight
plate("nameplate7", enemy("Player-1-BBB", SECRET, {second = SECRET, class = SECRET, level = SECRET, fighting = SECRET, dead = SECRET}))
fightStarts()
tick(1)
local m = db.players["Player-1-BBB"]
assert(m and m.attacks == 1 and m.name == nil and m.level == nil and m.class == nil, "a half-hidden attacker should still be listed by her id")
assert(list.rows[1].name.txt == "Unknown player", "an unnamed attacker should show as unknown")
known = {{guid = "Player-1-BBB", name = "Frosty", second = "Bolt", class = "MAGE"}}
meter.Current = {hit("Frosty Bolt", "MAGE", 500)}
fightEnds()
tick(1)
assert(m.name == "Frosty Bolt" and m.class == "MAGE", "hidden details should be filled in after the fight")
assert(count(db.players) == 1 and m.attacks == 1 and m.confirmed, "the meter's name for her must land on the same entry, not a second one")
assert(list.rows[1].name.txt == "Frosty Bolt" and list.rows[1].class.txt == "Mage", "the row should show what is known now")

-- everything hidden, even the id: nothing to list, but written down (once, not every half second)
now = now + 100
unplate("nameplate7")
plate("nameplate8", enemy(SECRET, SECRET, {second = SECRET, class = SECRET, level = SECRET}))
meter.Current = {}
fightStarts()
tick(8)
assert(count(db.players) == 1 and logged("nothing readable"), "a fully hidden player can't be listed")
local lines = 0
for _, l in ipairs(db.log) do if l:find("nothing readable", 1, true) then lines = lines + 1 end end
assert(lines == 1, "the record should not fill up with the same line: " .. lines)

-- the meter half hidden: it proves nothing, so nobody is taken off
plate("nameplate9", enemy("Player-1-EEE", "Maybe", {class = "MAGE"}))
tick(1)
assert(db.players["Player-1-EEE"], "a mage on you shows at once")
meter.Current = {{totalAmount = 100, combatSpellDetails = SECRET}, SECRET, {totalAmount = SECRET, combatSpellDetails = {unitName = SECRET, isMob = SECRET, isPet = SECRET}}}
fightEnds()
assert(db.players["Player-1-EEE"], "with the meter hidden, a player seen on you should stay listed")

-- the meter hidden altogether: asked again a moment later, then left alone
now = now + 100
unplate("nameplate8")
unplate("nameplate9")
plate("nameplate10", enemy("Player-1-JJJ", "Perhaps", {class = "MAGE"}))
meter.Current = SECRET
fightStarts()
tick(1)
local asked = meterAsked
fightEnds()
tick(3)
assert(meterAsked == asked + 2, "an unreadable meter should be asked once more, not over and over: " .. (meterAsked - asked))
assert(db.players["Player-1-JJJ"], "with the meter unreadable, a player seen on you should stay listed")

-- a hidden pet flag is not "not a pet"
now = now + 100
unplate("nameplate10")
meter.Current = {{totalAmount = 50, combatSpellDetails = {unitName = "Fang", unitClassFilename = "HUNTER", isMob = false, isPet = SECRET}}}
fightStarts()
tick(1)
fightEnds()
assert(db.players["name:Fang"] == nil, "something that may be a pet must not be listed as a player")
noProblems()
