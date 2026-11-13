-- A player on the list comes into view: a chat line and the war drum, at most once a minute each.
WarDrumDB = {version = 2, players = {
	["Player-1-AAA"] = {guid = "Player-1-AAA", name = "Stabby Pants", class = "ROGUE", level = 36, attacks = 2, kills = 2, mine = 0, first = 1, last = 1},
	["name:Far Shooter"] = {name = "Far Shooter", class = "HUNTER", attacks = 1, kills = 0, mine = 0, first = 1, last = 2, confirmed = true},
}}
start()
local function stabby(more)
	local u = enemy("Player-1-AAA", "Stabby", {second = "Pants", onMe = false, fighting = false})
	for k, v in pairs(more or {}) do u[k] = v end
	return u
end

plate("nameplate1", stabby())
assert(said("Stabby Pants|r is near (killed you 2x).") == 1, "no chat line when a listed player came into view")
assert(#sounds == 1 and sounds[1]:find("WarDrum.ogg", 1, true), "the war drum should play, once")
tick(1)
assert(list.rows[2].name.txt == "Stabby Pants" and list.rows[2].near.shown and list.anyNear, "his row should be marked as nearby")

-- he stays in view, leaves and comes back within the minute: no more noise
tick(30)
unplate("nameplate1")
tick(25)
plate("nameplate1", stabby())
assert(said("is near") == 1 and #sounds == 1, "warned again within a minute")
-- over a minute later he is back: warned again
unplate("nameplate1")
tick(70)
plate("nameplate1", stabby())
assert(said("is near") == 2 and #sounds == 2, "he came back after a minute: that deserves a warning")

-- a player the meter named but who was never seen is recognised by name alone
chat, sounds = {}, {}
plate("nameplate2", enemy("Player-1-FAR", "Far", {second = "Shooter", class = "HUNTER", onMe = false, fighting = false}))
assert(said("Far Shooter|r is near.") == 1 and #sounds == 1, "a player listed by name should be recognised")
assert(db.players["Player-1-FAR"] and db.players["name:Far Shooter"] == nil, "and now be kept under his id")

-- switched off: silence. The sound setting greys out, since it does nothing then
local o, c = options()
click(c.alert.widget)
assert(db.settings.alert == false and c.sound.alpha == 0.4, "Warn me off should grey out the sound")
chat, sounds = {}, {}
unplate("nameplate1")
unplate("nameplate2")
tick(130)
plate("nameplate1", stabby())
tick(1)
assert(said("is near") == 0 and #sounds == 0, "warned although the warning is switched off")
assert(list.rows[2].near.shown, "the nearby mark still shows")
click(c.alert.widget)
assert(c.sound.alpha == 1, "Warn me on should light the sound up again")

-- the sound: the arrows step through war drum, raid warning and none (playing each); clicking the name plays it
sounds = {}
click(c.sound.next)
assert(db.settings.sound == "WARNING" and c.sound.widget.text.txt == "Raid warning" and sounds[1] == 8959, "the next arrow should pick and play the raid warning")
click(c.sound.next)
assert(db.settings.sound == "NONE" and #sounds == 1 and c.sound.widget.text.txt == "No sound", "No sound should be silent")
click(c.sound.prev)
click(c.sound.prev)
assert(db.settings.sound == "DRUM", "the previous arrow should step back to the war drum")
sounds = {}
click(c.sound.widget)
assert(#sounds == 1 and sounds[1]:find("WarDrum", 1, true), "clicking the sound's name should play it")

-- a corpse is no threat, and in a battleground nobody is announced
chat, sounds = {}, {}
unplate("nameplate1")
tick(130)
plate("nameplate1", stabby({dead = true}))
assert(said("is near") == 0 and #sounds == 0, "warned about a dead player")
unplate("nameplate1")
tick(130)
instance = "pvp"
plate("nameplate1", stabby())
tick(1)
assert(said("is near") == 0 and #sounds == 0, "warned in a battleground")
noProblems()
