-- The list itself: newest first, a set number of rows, scrolling, the tooltip,
-- removing a player, sample players, moving it.
WarDrumDB = {version = 2, players = {}}
for i = 1, 12 do
	WarDrumDB.players["Player-1-" .. i] = {guid = "Player-1-" .. i, name = "Ganker " .. i, class = (i % 2 == 0) and "ROGUE" or "MAGE",
		level = 30 + i, attacks = i, kills = i % 3, mine = (i == 11) and 1 or 0, first = 1, last = i, zone = "Tanaris"}
end
start()
assert(list.count.txt == "(12)", "the title should count everyone on the list")
assert(list.rows[1].name.txt == "Ganker 12" and list.rows[1].level.txt == "42", "the newest attacker should be on top")
assert(list.rows[10].shown and not list.rows[11].shown, "ten rows show by default")
assert(list.h == 24 + 10 * 16, "the list should be as tall as its rows")
assert(list.rows[1].kills.txt == "" and list.rows[2].kills.txt:find("2x", 1, true), "kills show as a count, and not at all when there are none")
assert(list.mark.shown, "with more players than rows there should be a scroll marker")

-- the mouse wheel scrolls, and stops at both ends
list.scripts.OnMouseWheel(list, -1)
assert(list.rows[1].name.txt == "Ganker 11", "one notch down should scroll one row")
for _ = 1, 10 do list.scripts.OnMouseWheel(list, -1) end
assert(list.rows[1].name.txt == "Ganker 10" and list.rows[10].name.txt == "Ganker 1", "scrolling should stop at the end")
for _ = 1, 10 do list.scripts.OnMouseWheel(list, 1) end
assert(list.rows[1].name.txt == "Ganker 12", "scrolling should stop at the top")

-- pointing at a row tells the story
local row = list.rows[2]
row.scripts.OnEnter(row)
local tip = table.concat(GameTooltip.lines, " / ")
assert(GameTooltip.lines[1] == "Ganker 11", "the tooltip should be headed by the name")
assert(tip:find("Attacked you 11 times", 1, true) and tip:find("Killed you 2 times", 1, true) and tip:find("You killed them 1 time", 1, true), "the tooltip's counts are wrong: " .. tip)
assert(tip:find("in Tanaris", 1, true) and tip:find("Shift + right-click to remove", 1, true), "the tooltip should say where and how to remove: " .. tip)
row.scripts.OnLeave(row)

-- right-click does nothing by itself; with Shift it removes that player
click(row)
assert(db.players["Player-1-11"], "a plain right-click must not remove anyone")
shift = true
click(row)
shift = false
assert(db.players["Player-1-11"] == nil and list.count.txt == "(11)" and list.rows[2].name.txt == "Ganker 10", "Shift + right-click should remove that player")

-- fewer rows than players fit: no marker
db.settings.rows = 20
list.Apply()
assert(list.rows[11].shown and not list.rows[12].shown and not list.mark.shown, "with room for everyone there is nothing to scroll")
db.settings.rows = nil
list.Apply()

-- the x hides it and says how to get it back
chat = {}
click(list.close)
assert(not list.shown and db.shown == false and said("/wd") == 1, "closing the list should say how to show it again")
slash("show")
assert(list.shown, "/wd show should bring it back")

-- sample players: for setting the list up before anyone has attacked you. Nothing is saved
slash("demo")
assert(list.count.txt == "(sample)" and list.rows[1].name.txt == "Stabby Pants" and list.rows[1].near.shown, "/wd demo should show sample players")
assert(list.rows[2].level.txt == "??" and list.rows[7].shown and not list.rows[8].shown, "the sample list is wrong")
assert(count(db.players) == 11, "sample players must not be saved")
list.rows[1].scripts.OnEnter(list.rows[1])
assert(table.concat(GameTooltip.lines, " / "):find("A sample player", 1, true), "a sample row should say that it is one: " .. table.concat(GameTooltip.lines, " / ") .. " key=" .. tostring(list.rows[1].key))
shift = true
click(list.rows[1])
shift = false
assert(list.rows[1].name.txt == "Stabby Pants", "a sample row can't be removed")
slash("demo")
assert(list.rows[1].name.txt == "Ganker 12" and list.count.txt == "(11)", "/wd demo again should bring the real list back")

-- moving it: by the title or by a row; its top-left corner is what is remembered
local moved = 0
list.StartMoving = function() moved = moved + 1 end
list.GetLeft = function() return 300 end
list.GetTop = function() return 500 end
list.scripts.OnDragStart(list)
list.scripts.OnDragStop(list)
assert(moved == 1 and db.pos[1] == 300 and db.pos[2] == 500, "dragging should remember the top-left corner")
local p = list.points[#list.points]
assert(p[1] == "TOPLEFT" and p[3] == "BOTTOMLEFT" and p[4] == 300 and p[5] == 500, "the list should hang from its top-left corner")
list.rows[1].scripts.OnDragStart(list.rows[1])
assert(moved == 2, "the rows cover the list: dragging one should move it too")
-- a bigger list stays where it is: the corner is kept, in screen units
db.settings.scale = 1.5
list.Apply()
p = list.points[#list.points]
assert(p[4] == 200 and math.abs(p[5] - 500 / 1.5) < 0.01, "changing the size moved the list")
-- locked: it doesn't move
db.settings.lock = true
list.scripts.OnDragStart(list)
list.rows[1].scripts.OnDragStart(list.rows[1])
assert(moved == 2, "Lock in place should stop the drag")
slash("reset")
p = list.points[#list.points]
assert(db.pos == nil and p[3] == "LEFT", "/wd reset should put it back where it started")

-- emptied: one line, saying so
slash("clear")
assert(list.empty.shown and list.h == 40 and list.count.txt == "" and not list.rows[1].shown, "the empty list should be one line tall")
noProblems()
