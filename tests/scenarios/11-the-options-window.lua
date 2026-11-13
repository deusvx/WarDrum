-- /wd (the options window): every setting has a control, changes the list at once, and explains itself.
WarDrumDB = {version = 2, players = {
	["Player-1-AAA"] = {guid = "Player-1-AAA", name = "Stabby Pants", class = "ROGUE", level = 36, attacks = 2, kills = 2, mine = 0, first = 1, last = 1},
}}
start()
slash("hide") -- (the list is hidden: opening the settings brings it back, since they change it)
assert(not list.shown)
local o, c = options()
assert(o.shown and list.shown, "/wd should open the settings and show the list")
assert(UISpecialFrames[1] == "WarDrumOptionsFrame", "Escape should close the settings")
assert(o.h > 500 and o.h < 600, "the window should be as tall as its settings: " .. tostring(o.h))
for _, key in ipairs({"width", "scale", "alpha", "rows", "showLevel", "showClass", "lock", "onlyDamage", "skipBG", "alert", "sound"}) do
	assert(c[key], "no control for " .. key)
end
assert(c.width.value.txt == "200" and c.scale.value.txt == "100%" and c.alpha.value.txt == "90%" and c.rows.value.txt == "10", "the controls should show the defaults")
assert(next(db.settings) == nil, "opening the settings must not change any")

-- a switch: the class column goes, in the list and in the preview. Clicking anywhere on its row works too
click(c.showClass.widget)
assert(db.settings.showClass == false and not list.rows[1].class.shown and not o.preview[1].class.shown, "Show class didn't switch the column off")
c.showClass.scripts.OnMouseUp(c.showClass, "LeftButton")
assert(db.settings.showClass == true and list.rows[1].class.shown, "clicking the row should switch it back")
c.showClass.scripts.OnMouseUp(c.showClass, "RightButton")
assert(db.settings.showClass == true, "a right-click on the row should do nothing")
click(c.showLevel.widget)
assert(not list.rows[1].level.shown and list.rows[1].class.shown, "Show level should only switch the level off")
click(c.showLevel.widget)

-- sliders: they snap to their step, the arrows move one step and stop at the ends
c.width.widget.scripts.OnValueChanged(c.width.widget, 183)
assert(db.settings.width == 185 and list.width == 185 and c.width.value.txt == "185", "the width slider should snap to its step and resize the list")
click(c.width.up)
assert(db.settings.width == 190, "the up arrow should add a step")
for _ = 1, 40 do click(c.width.down) end
assert(db.settings.width == 160, "the down arrow went past the narrowest")
c.scale.widget.scripts.OnValueChanged(c.scale.widget, 1.2)
assert(list.scale == 1.2 and c.scale.value.txt == "120%", "Size should scale the list")
click(c.alpha.down)
assert(db.settings.alpha == 0.85 and c.alpha.value.txt == "85%", "Background should move in clean steps from its default")
c.alpha.widget.scripts.OnValueChanged(c.alpha.widget, 0.5)
assert(list.bg.rgba[4] == 0.5 and c.alpha.value.txt == "50%", "Background should set how solid the list is")
c.rows.widget.scripts.OnValueChanged(c.rows.widget, 3)
assert(db.settings.rows == 3, "Rows shown didn't set")

-- the help panel explains the setting under the mouse
c.alert.scripts.OnEnter(c.alert)
assert(o.helpTitle.txt == "Warn me" and o.helpText.txt:find("chat line", 1, true), "no help for the setting under the mouse")
c.alert.scripts.OnLeave(c.alert)
assert(o.helpTitle.txt == "War Drum", "the help should go back to its resting text")
for key, row in pairs(c) do
	row.scripts.OnEnter(row)
	assert(o.helpTitle.txt == row.def.name and #o.helpText.txt > 20, "no help text for " .. key)
	row.scripts.OnLeave(row)
end

-- the preview: three sample players, the first one nearby
assert(o.preview[1].name.txt == "Stabby Pants" and o.preview[1].kills.txt:find("2x", 1, true) and o.preview[1].near.shown, "the preview's first row is wrong")
assert(o.preview[2].level.txt == "??" and not o.preview[2].near.shown, "the preview's second row is wrong")

-- the two buttons: sample players on and off; emptying the list asks first
local demoButton, emptyButton = o.buttons[1], o.buttons[2]
assert(demoButton.text.txt == "Show sample players" and emptyButton.text.txt == "Empty the list", "the buttons are mislabelled")
click(demoButton)
assert(list.count.txt == "(sample)" and demoButton.text.txt == "Hide sample players", "the button should show sample players")
demoButton.scripts.OnEnter(demoButton)
assert(o.helpTitle.txt == "Hide sample players" and o.helpText.txt:find("made-up", 1, true), "the button should explain itself")
demoButton.scripts.OnLeave(demoButton)
click(demoButton)
assert(list.count.txt == "(1)" and demoButton.text.txt == "Show sample players", "and hide them again")
click(emptyButton)
assert(#popups == 1 and popups[1].text == "Empty the list?" and next(db.players) ~= nil, "Empty the list should ask first")
popups[1].data()
assert(next(db.players) == nil and list.empty.shown, "saying yes should empty the list")

-- the three bars on the list open and close the settings
click(list.menu)
assert(not o.shown, "the list's menu button should close the open settings")
click(list.menu)
assert(o.shown, "and open them again")
noProblems()
