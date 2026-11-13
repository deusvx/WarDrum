-- After a fight the game's own damage meter says who damaged you. That settles
-- who belongs on the list.
start()

-- A mage has you targeted through a fight but never damages you: shown during the fight, taken off after
units.target = enemy("Player-1-CCC", "Victim", {class = "MAGE", level = 30})
fire("PLAYER_TARGET_CHANGED")
fightStarts()
tick(2)
assert(db.players["Player-1-CCC"] and db.players["Player-1-CCC"].attacks == 1, "someone targeting you in a fight should show at once")
meter.Current = {hit("Scorpid", "WARRIOR", 300, true)}
fightEnds()
assert(db.players["Player-1-CCC"] == nil and logged("taken back: Victim"), "a player who never damaged you should come off the list after the fight")

-- A rogue you never saw damages you. So do his pet, a creature, and (says the meter) you yourself:
-- only he is listed, once, by name and class
units = {}
now = now + 100
fightStarts()
tick(1)
meter.Current = {hit("Sneaky Pete", "ROGUE", 400), hit("Sneaky Pete", "ROGUE", 250), hit("Fang", "HUNTER", 90, false, true),
	hit("Scorpid", "WARRIOR", 50, true), hit("Tk Deadeye", "HUNTER", 30)}
fightEnds()
local sp = db.players["name:Sneaky Pete"]
assert(sp and count(db.players) == 1, "only the rogue belongs on the list, got " .. count(db.players))
assert(sp.attacks == 1 and sp.class == "ROGUE" and sp.confirmed and sp.level == nil, "the unseen attacker's entry is wrong")
assert(list.rows[1].name.txt == "Sneaky Pete" and list.rows[1].level.txt == "" and list.rows[1].class.txt == "Rogue", "his row is wrong")

-- Later he walks into view: the same entry gets his id and level (a unit's two-part name comes in two pieces)
chat, sounds = {}, {}
plate("nameplate2", enemy("Player-1-DDD", "Sneaky", {second = "Pete", level = 38, onMe = false, fighting = false}))
tick(1)
assert(db.players["name:Sneaky Pete"] == nil and db.players["Player-1-DDD"] == sp, "seeing him should move his entry under his id")
assert(sp.level == 38 and sp.attacks == 1 and count(db.players) == 1, "and fill in his level, nothing else")
assert(said("Sneaky Pete|r is near.") == 1 and #sounds == 1, "a player listed by name alone is still recognised when he shows up")

-- A fight that leaves no trace in the meter (it still shows the last one) must not count the last one again
now = now + 100
fightStarts()
tick(1)
fightEnds()
assert(sp.attacks == 1, "the same meter session was counted twice")

-- With "only players who damaged you" off, someone who merely targeted you stays
db.settings.onlyDamage = false
now = now + 100
units.target = enemy("Player-1-GGG", "Looker", {class = "MAGE", level = 30})
fire("PLAYER_TARGET_CHANGED")
fightStarts()
tick(1)
meter.Current = {hit("Scorpid", "WARRIOR", 120, true)}
fightEnds()
assert(db.players["Player-1-GGG"], "with the setting off, a player who only targeted you should stay")
noProblems()
