-- You die. Everyone who damaged you in that fight gets the kill.
start()

-- 1. The damage meter can be read as you die: it names them, seen or not
plate("nameplate2", enemy("Player-1-DDD", "Sneaky", {second = "Pete"}))
fightStarts()
tick(1)
local e = db.players["Player-1-DDD"]
meter.Current = {hit("Sneaky Pete", "ROGUE", 900), hit("Far Shooter", "HUNTER", 400), hit("Fang", "HUNTER", 90, false, true), hit("Scorpid", "WARRIOR", 50, true)}
fire("PLAYER_DEAD")
fire("PLAYER_DEAD")
local far = db.players["name:Far Shooter"]
assert(e.kills == 1 and e.attacks == 1, "the rogue on you should have one kill, counted once")
assert(far and far.kills == 1 and far.attacks == 1 and far.class == "HUNTER", "the hunter you never saw damaged you too: his kill as well")
assert(count(db.players) == 2, "pets and creatures don't get kills")
assert(logged("KILLED BY Sneaky Pete (the damage meter"), "the record should say where the kill came from")
assert(list.rows[1].kills.txt:find("1x", 1, true) and list.rows[2].kills.txt:find("1x", 1, true), "the list should show the kills")
fightEnds()
assert(e.kills == 1 and e.attacks == 1 and far.kills == 1 and far.attacks == 1, "the end of the fight must not count anything twice")

-- 2. The meter can't be read as you die: whoever was on you gets the kill for now,
--    and the meter puts it right when the fight is over
now = now + 300
plate("nameplate4", enemy("Player-1-GGG", "Looker", {class = "MAGE"}))
meter.Current = nil
fightStarts()
tick(1)
local looker = db.players["Player-1-GGG"]
assert(looker, "a mage targeting you in the fight shows at once")
fire("PLAYER_DEAD")
assert(e.kills == 2 and looker.kills == 1 and far.kills == 1, "with the meter unreadable the kill goes to those seen on you")
meter.Current = {hit("Sneaky Pete", "ROGUE", 500), hit("Far Shooter", "HUNTER", 800)}
fightEnds()
assert(e.kills == 2, "the rogue did damage you: his kill stands")
assert(far.kills == 2, "the hunter did too: he gets the kill after all")
assert(db.players["Player-1-GGG"] == nil, "the mage never damaged you: kill and listing are taken back")

-- 3. Much later you fall off a cliff: nobody's kill
unplate("nameplate2")
unplate("nameplate4")
now = now + 300
fire("PLAYER_DEAD")
assert(e.kills == 2 and far.kills == 2 and logged("not in a fight"), "a death outside a fight must not be pinned on the last attackers")

-- 4. A creature kills you while an enemy player only watches: nobody's kill, and the watcher comes off
now = now + 300
plate("nameplate6", enemy("Player-1-HHH", "Watcher", {class = "MAGE"}))
meter.Current = {hit("Scorpid", "WARRIOR", 2000, true)}
fightStarts()
tick(1)
assert(db.players["Player-1-HHH"], "the watcher shows while he has you targeted")
fire("PLAYER_DEAD")
fightEnds()
assert(db.players["Player-1-HHH"] == nil and e.kills == 2 and far.kills == 2, "dying to a creature is nobody's kill")
noProblems()
