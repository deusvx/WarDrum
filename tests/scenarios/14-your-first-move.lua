-- Who started it? By the time the game says a fight has begun, the player you jumped is already
-- fighting back, so your own first move has to be noticed before that.
start()
harmful[19434] = true -- (Aimed Shot)

-- 1. As it happened in the game: a warlock busy with a creature. You open on her; three seconds later
--    the fight starts and she is on you. She damages you for 1602. Your fight, not hers.
units.target = enemy("Player-1-WLK", "Mala", {second = "Espina", class = "WARLOCK", level = 34, onMe = false, fighting = true})
fire("PLAYER_TARGET_CHANGED")
fire("UNIT_SPELLCAST_SENT", "player", "Mala Espina", "cast-1", 19434)
now = now + 3.5
units.target.onMe = true
fightStarts()
tick(3)
assert(next(db.players) == nil, "a player you opened on must not show for fighting back")
meter.Current = {hit("Mala Espina", "WARLOCK", 1602)}
fightEnds()
assert(next(db.players) == nil, "nor be listed from the damage meter")
assert(logged("your move (a harmful spell)") and logged("you struck first: Mala Espina") and logged("not listed: you attacked Mala Espina first"),
	"the record should say why")

-- 2. A spell that harms nobody (an aspect, a heal) is not a first move: she attacks, she is listed.
now = now + 100
units.target = enemy("Player-1-GNK", "Real", {second = "Ganker", onMe = false, fighting = true})
fire("PLAYER_TARGET_CHANGED")
fire("UNIT_SPELLCAST_SENT", "player", "Tk Deadeye", "cast-2", 13165)
now = now + 2
units.target.onMe = true
fightStarts()
tick(1)
meter.Current = {hit("Real Ganker", "ROGUE", 700)}
fightEnds()
assert(db.players["Player-1-GNK"] and db.players["Player-1-GNK"].attacks == 1, "a harmless spell must not excuse an attacker")

-- 3. A move long ago is forgotten: you shot at him, nothing came of it, half a minute later he jumps you.
now = now + 100
units.target = enemy("Player-1-LAT", "Late", {second = "Comer", onMe = false, fighting = true})
fire("PLAYER_TARGET_CHANGED")
fire("UNIT_SPELLCAST_SENT", "player", "Late Comer", "cast-3", 19434)
now = now + 30
units.target.onMe = true
fightStarts()
tick(1)
meter.Current = {hit("Late Comer", "ROGUE", 650)}
fightEnds()
assert(db.players["Player-1-LAT"] and db.players["Player-1-LAT"].attacks == 1, "a move 30 seconds ago should not make the fight yours")

-- 4. They already had you targeted when you fired: they were coming for you. Listed.
now = now + 100
units.target = enemy("Player-1-EYE", "Eyeing", {second = "You", onMe = true, fighting = false})
fire("PLAYER_TARGET_CHANGED")
fire("UNIT_SPELLCAST_SENT", "player", "Eyeing You", "cast-4", 19434)
now = now + 1
units.target.fighting = true
fightStarts()
tick(1)
meter.Current = {hit("Eyeing You", "ROGUE", 640)}
fightEnds()
assert(db.players["Player-1-EYE"] and db.players["Player-1-EYE"].attacks == 1, "someone already targeting you is not a victim")

-- 5. Auto Shot, a swing and your pet are first moves too.
for i, event in ipairs({"START_AUTOREPEAT_SPELL", "PLAYER_ENTER_COMBAT", "PET_ATTACK_START"}) do
	now = now + 100
	local guid, second = "Player-1-V" .. i, "Number" .. i
	units.target = enemy(guid, "Victim", {second = second, onMe = false, fighting = true})
	fire("PLAYER_TARGET_CHANGED")
	fire(event)
	now = now + 4
	units.target.onMe = true
	fightStarts()
	tick(1)
	meter.Current = {hit("Victim " .. second, "ROGUE", 500 + i)}
	fightEnds()
	assert(db.players[guid] == nil, event .. " at a player who was not on you should make the fight yours")
end

-- 6. A move in the middle of another fight starts nothing: you are fighting a creature, send your pet at a
--    passing player, the fight ends. Later he attacks you: his fight.
now = now + 100
units.target = nil
fire("PLAYER_TARGET_CHANGED")
fightStarts()
units.target = enemy("Player-1-PAS", "Passer", {second = "By", onMe = false, fighting = false})
fire("PLAYER_TARGET_CHANGED")
fire("PET_ATTACK_START")
tick(1)
meter.Current = {hit("Some Boar", "x", 80, true)}
fightEnds()
now = now + 3
units.target.onMe, units.target.fighting = true, true
fightStarts()
tick(1)
meter.Current = {hit("Passer By", "ROGUE", 630)}
fightEnds()
assert(db.players["Player-1-PAS"] and db.players["Player-1-PAS"].attacks == 1, "a move made during another fight should not carry over")

-- 7. What the game hides is never touched: a cast whose details are hidden is simply not a first move.
now = now + 100
units.target = enemy("Player-1-HID", "Hidden", {second = "Cast", onMe = false, fighting = true})
fire("PLAYER_TARGET_CHANGED")
fire("UNIT_SPELLCAST_SENT", SECRET, SECRET, SECRET, SECRET)
fire("UNIT_SPELLCAST_SENT", "player", SECRET, SECRET, SECRET)
now = now + 2
units.target.onMe = true
fightStarts()
tick(1)
meter.Current = {hit("Hidden Cast", "ROGUE", 610)}
fightEnds()
assert(db.players["Player-1-HID"] and db.players["Player-1-HID"].attacks == 1, "a hidden cast must not count as your first move")
noProblems()
