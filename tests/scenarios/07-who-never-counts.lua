-- Duels, battlegrounds, and players you attacked first are not ganks.
start()

-- 1. A duel: your own faction is hostile for a while and damages you. Never listed.
units.target = enemy("Player-1-DUE", "Duel", {second = "Buddy", faction = "Alliance"})
fire("PLAYER_TARGET_CHANGED")
fightStarts()
tick(2)
assert(next(db.players) == nil, "a duel partner must not show during the duel")
meter.Current = {hit("Duel Buddy", "ROGUE", 800)}
fire("PLAYER_DEAD")
fightEnds()
assert(next(db.players) == nil, "a duel partner must not be listed from the damage meter either")

-- 2. A battleground: everyone attacks you there. Nothing is listed, counted or announced.
units = {}
instance = "pvp"
now = now + 100
plate("nameplate1", enemy("Player-1-BG1", "Flag", {second = "Runner"}))
fightStarts()
tick(2)
meter.Current = {hit("Flag Runner", "ROGUE", 900)}
fire("PLAYER_DEAD")
fightEnds()
assert(next(db.players) == nil and logged("in a battleground"), "battleground fights should not be listed")
-- ...and that fight is not picked up later, back outside
instance = "none"
unplate("nameplate1")
now = now + 100
fightStarts()
tick(1)
fightEnds()
assert(next(db.players) == nil, "the battleground's last fight was counted after leaving it")
-- with "Not in battlegrounds" switched off they do count
db.settings.skipBG = false
instance = "pvp"
now = now + 100
plate("nameplate1", enemy("Player-1-BG1", "Flag", {second = "Runner"}))
fightStarts()
tick(1)
meter.Current = {hit("Flag Runner", "ROGUE", 500)}
fightEnds()
assert(db.players["Player-1-BG1"] and db.players["Player-1-BG1"].attacks == 1, "with the setting off, battleground attackers should be listed")
slash("clear")
unplate("nameplate1")
instance = "none"
db.settings.skipBG = nil

-- 3. You jump a mage who is minding her own business. She fights back and even wins. Your fight, not hers.
now = now + 100
units.target = enemy("Player-1-VIC", "Poor", {second = "Victim", class = "MAGE", onMe = false, fighting = false})
fire("PLAYER_TARGET_CHANGED")
fightStarts()
units.target.onMe, units.target.fighting = true, true
tick(3)
assert(next(db.players) == nil, "a player you attacked first must not show for fighting back")
meter.Current = {hit("Poor Victim", "MAGE", 600)}
fire("PLAYER_DEAD")
fightEnds()
assert(next(db.players) == nil, "nor be listed or credited from the damage meter")
assert(logged("you struck first") and logged("not listed: you attacked Poor Victim first"), "the record should say why")

-- ...but when she comes for you later, that is hers
now = now + 100
fightStarts()
tick(1)
meter.Current = {hit("Poor Victim", "MAGE", 700)}
fightEnds()
local v = db.players["Player-1-VIC"]
assert(v and v.attacks == 1 and v.kills == 0, "the next fight, started by her, should count")
noProblems()
