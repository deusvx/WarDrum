-- An enemy player on you in a fight shows at once: name in class color, level, class.
-- One fight is one attack, however long it lasts.
start()
plate("nameplate3", enemy("Player-1-AAA", "Stabby", {second = "Pants"}))
fightStarts()
tick(3)
local e = db.players["Player-1-AAA"]
assert(e and e.attacks == 1 and e.kills == 0, "the attacker wasn't listed")
assert(e.name == "Stabby Pants" and e.class == "ROGUE" and e.level == 36 and e.zone == "Tanaris", "his details are wrong")
assert(count(db.players) == 1, "only the attacker belongs on the list")

local row = list.rows[1]
assert(row.shown and row.name.txt == "Stabby Pants" and row.level.txt == "36" and row.class.txt == "Rogue", "the row should show name, level and class")
assert(row.name.color[2] == 0.96 and row.class.color[2] == 0.96, "name and class should be in the class color")
assert(row.kills.txt == "", "no kills yet: that column stays empty")
assert(row.near.shown and row.wash.shown and list.anyNear and not list.empty.shown, "a listed player in view should be marked as nearby")
assert(list.count.txt == "(1)", "the title should count the players")
assert(said("is near") == 0 and #sounds == 0, "someone who just attacked you needs no 'is near' warning")

-- a long fight, with him on you all the way: still one attack
tick(45)
assert(e.attacks == 1, "one fight should count as one attack")
meter.Current = {hit("Stabby Pants", "ROGUE", 700)}
fightEnds()
assert(e.attacks == 1 and e.confirmed, "the damage meter confirming him must not count a second attack")

-- five minutes later he is back, a level higher: that is a new attack
now = now + 300
units.nameplate3.level = 37
fightStarts()
tick(2)
assert(e.attacks == 2 and e.level == 37, "a new fight should count again and update the level")
meter.Current = {hit("Stabby Pants", "ROGUE", 300)}
fightEnds()
assert(e.attacks == 2, "still two")

-- he walks off: the nearby mark goes out by itself
unplate("nameplate3")
tick(25)
assert(not list.rows[1].near.shown and not list.anyNear, "the nearby mark should fade once he is gone")
noProblems()
