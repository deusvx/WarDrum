-- Getting your own back: a listed player you were fighting dies with you on them.
start()

-- he attacks, you have him targeted, he dies: your kill, once
units.target = enemy("Player-1-AAA", "Stabby", {second = "Pants"})
fire("PLAYER_TARGET_CHANGED")
fightStarts()
tick(1)
local e = db.players["Player-1-AAA"]
units.target.dead, units.target.onMe = true, false
tick(1)
assert(e.mine == 1, "your kill wasn't counted")
tick(3)
assert(e.mine == 1, "your kill was counted twice")
meter.Current = {hit("Stabby Pants", "ROGUE", 300)}
fightEnds()

-- a mage attacks; the fight ends with her still standing. Honor for something else is not her death
now = now + 300
units.target = enemy("Player-1-BBB", "Frosty", {second = "Bolt", class = "MAGE"})
fire("PLAYER_TARGET_CHANGED")
fightStarts()
tick(1)
local m = db.players["Player-1-BBB"]
meter.Current = {hit("Frosty Bolt", "MAGE", 300)}
fightEnds()
fire("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 11 Honor.")
assert(m.mine == 0, "honor while she is alive in front of you must not count as killing her")

-- honor arrives while the game won't say whether she is dead: she was your target and had just attacked you
units.target.dead = SECRET
fire("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 11 Honor.")
assert(m.mine == 1, "honor right after fighting your listed target should count as your kill")
fire("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 11 Honor.")
assert(m.mine == 1, "one kill, one count")

-- she attacks again and gets away; you target something else; honor then is nobody's
now = now + 300
units.target.dead = false
fightStarts()
tick(1)
meter.Current = {hit("Frosty Bolt", "MAGE", 350)}
fightEnds()
units.target = nil
fire("PLAYER_TARGET_CHANGED")
fire("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 20 Honor.")
assert(m.mine == 1, "honor with someone else targeted was put down as killing her")

-- a listed player lying dead nearby who was never your target: not your kill
plate("nameplate5", enemy("Player-1-BBB", "Frosty", {second = "Bolt", class = "MAGE", dead = true, onMe = false}))
tick(1)
assert(m.mine == 1, "someone else's kill was counted as yours")
noProblems()
