-- A fresh install: the list opens, empty, and nothing runs while nobody is around.
start()
assert(list and list.shown, "the list should open by itself the first time")
assert(list.empty.shown and next(db.players) == nil, "the list should start empty")
assert(list.width == 200, "the list should be slim (200 wide) by default")
tick(2)
assert(not frames[1].shown, "with no enemy players about, the scanner should be asleep")

-- /wd hide and /wd show hide and show it, and remember
slash("hide")
assert(not list.shown and db.shown == false, "/wd hide should hide the list")
slash("show")
assert(list.shown and db.shown == true, "/wd show should show it again")

-- anything else explains the commands
chat = {}
slash("help")
assert(said("/wd show") == 1 and said("/wd remove") == 1 and said("/wd clear") == 1, "/wd help should list the commands")
noProblems()
