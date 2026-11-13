-- /wd and its words.
WarDrumDB = {version = 2, players = {
	["Player-1-A"] = {guid = "Player-1-A", name = "Frosty Bolt", class = "MAGE", level = 30, attacks = 1, kills = 0, mine = 0, first = 1, last = 1},
	["Player-1-B"] = {guid = "Player-1-B", name = "Stabby Pants", class = "ROGUE", level = 36, attacks = 2, kills = 1, mine = 0, first = 1, last = 2},
}}
start()

-- remove by name, however it is typed
chat = {}
slash("remove frosty bolt")
assert(db.players["Player-1-A"] == nil and db.players["Player-1-B"] and said("removed") == 1, "/wd remove didn't remove by name")
assert(list.count.txt == "(1)" and list.rows[1].name.txt == "Stabby Pants", "the list should show the change at once")
chat = {}
slash("remove nobody")
assert(said("nobody called nobody") == 1, "/wd remove should say when there is no such player")

-- the record: /wd dump writes down what the game's damage meter and death recap hold
deaths = {{name = "Tk Deadeye", deathRecapID = 3}}
recaps[3] = {{sourceName = "Stabby Pants", amount = 500}}
slash("dump")
assert(logged("meter on request") and logged("game: C_DamageMeter"), "/wd dump wrote nothing")
assert(logged("recap id 3") and logged("sourceName=Stabby Pants"), "/wd dump should follow a death to its recap")

-- clear, reset, and anything else lists the commands
chat = {}
slash("clear")
assert(next(db.players) == nil and said("list emptied") == 1 and list.empty.shown, "/wd clear didn't empty the list")
slash("reset")
assert(said("moved back") == 1, "/wd reset should say what it did")
chat = {}
slash("what")
assert(said("/wd show") == 1 and said("/wd demo") == 1 and said("/wd remove") == 1 and said("/wd clear") == 1 and said("/wd reset") == 1, "the help should list every command")
-- /wd on its own opens the settings, and closes them again
slash("")
assert(WarDrumOptionsFrame and WarDrumOptionsFrame.shown, "/wd on its own should open the settings")
slash("")
assert(not WarDrumOptionsFrame.shown, "/wd again should close them")
slash("OPTIONS")
assert(WarDrumOptionsFrame and WarDrumOptionsFrame.shown, "commands should not care about capitals")

-- the game's addon menu by the minimap: click for the list, right-click for the settings
WarDrum_OnAddonCompartmentClick(nil, "LeftButton")
assert(not list.shown, "a click in the addon menu should hide the list")
WarDrum_OnAddonCompartmentClick(nil, "LeftButton")
assert(list.shown, "and show it again")
WarDrum_OnAddonCompartmentClick(nil, "RightButton")
assert(not WarDrumOptionsFrame.shown, "a right-click should toggle the settings")
noProblems()
