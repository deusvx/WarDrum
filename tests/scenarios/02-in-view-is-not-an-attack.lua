-- Enemy players who are merely around, friendly players and creatures never get listed.
start()

-- an enemy rogue's nameplate appears; he even has you targeted, but nobody is fighting
plate("nameplate3", enemy("Player-1-AAA", "Stabby", {second = "Pants", fighting = false}))
tick(1)
assert(next(db.players) == nil, "an enemy merely in view should not be listed")
assert(frames[1].shown, "with an enemy player in view the scanner should be awake")
assert(logged("seen: nameplate3"), "seeing him should be written to the record")

-- you fight a scorpid next to him and a friendly mage: still nobody
plate("nameplate4", {player = true, hostile = false, guid = "Player-1-FFF", name = "Buddy", class = "MAGE", level = 30, onMe = true, fighting = true})
plate("nameplate5", {player = false, hostile = true, guid = "Creature-0-1", name = "Scorpid", onMe = true, fighting = true})
fightStarts()
tick(3)
meter.Current = {hit("Scorpid", "WARRIOR", 300, true)}
fightEnds()
assert(next(db.players) == nil, "a fight with a creature should list nobody")
assert(list.empty.shown and list.h == 40, "the empty list should stay one line tall")

-- everyone leaves: the scanner goes back to sleep
unplate("nameplate3")
unplate("nameplate4")
unplate("nameplate5")
tick(70)
assert(not frames[1].shown, "a minute after the last enemy player the scanner should be asleep again")
noProblems()
