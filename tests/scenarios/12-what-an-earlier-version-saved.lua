-- The first version's saved list is brought up to date: its guesses go, real
-- kills stay, names are joined, and nothing in it can trip the new code up.
WarDrumDB = {
	shown = true, pos = {"LEFT", "LEFT", 40, 120},
	players = {
		-- listed by the first version because he had you targeted (you had attacked him)
		["Player-1-OLD"] = {name = "Kalsb", realm = "Xyz", class = "ROGUE", level = 36, attacks = 1, kills = 0, first = 1, last = 5, near = 123},
		-- really killed you; saved without a "your kills" count
		["Player-1-KIL"] = {name = "Real", realm = "Killer", class = "MAGE", level = 40, attacks = 2, kills = 1, first = 1, last = 9},
	},
	log = {}, backfilled = {someone = true},
}
for i = 1, 900 do WarDrumDB.log[i] = "old line " .. i end
start()

assert(db.version == 2 and db.backfilled == nil, "the saved data should be marked as brought up to date")
assert(db.players["Player-1-OLD"] == nil, "the first version's guess should be gone")
local k = db.players["Player-1-KIL"]
assert(k and k.name == "Real Killer" and k.realm == nil and k.mine == 0 and k.kills == 1, "a real kill should stay, with the name joined")
assert(#db.log <= 600, "the record should be trimmed to its new length: " .. #db.log)
assert(db.pos == nil or #db.pos == 2, "the old saved position should be converted or dropped")
assert(list.rows[1].name.txt == "Real Killer" and list.rows[1].kills.txt:find("1x", 1, true), "the row is wrong")

-- seeing and pointing at them works (the first version's entries lacked some counts)
plate("nameplate1", enemy("Player-1-KIL", "Real", {second = "Killer", class = "MAGE", level = 41, onMe = false, fighting = false}))
tick(1)
assert(k.level == 41 and said("Real Killer|r is near (killed you 1x).") == 1, "a carried-over player should be recognised")
list.rows[1].scripts.OnEnter(list.rows[1])
assert(table.concat(GameTooltip.lines, " / "):find("Killed you 1 time", 1, true), "the tooltip failed on a carried-over player")
noProblems()

-- loading the same data again changes nothing more
fire("ADDON_LOADED", "WarDrum")
assert(count(db.players) == 1 and db.players["Player-1-KIL"].kills == 1, "a second load changed the list")
