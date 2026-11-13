-- A tiny stand-in for the game, just enough for War Drum to run outside it.
-- Each scenario gets a fresh copy: this file, then WarDrum.lua, then the scenario.
--
-- SECRET stands for a value the game hides during a fight: touching it in any way
-- (comparing, printing, joining) is an error here, exactly as it is in the game.

SECRET = setmetatable({}, {
	__tostring = function() error("touched a hidden value") end,
	__eq = function() error("compared a hidden value") end,
	__concat = function() error("joined a hidden value") end,
	__lt = function() error("compared a hidden value") end,
	__le = function() error("compared a hidden value") end,
	__add = function() error("did sums with a hidden value") end,
	__index = function() error("looked inside a hidden value") end,
})
function issecretvalue(v) return rawequal(v, SECRET) end

-- the clock: GetTime() is the game's uptime, time() the wall clock
now = 1000
function GetTime() return now end
date, time = os.date, function() return 5000 + now end
timers = {}
C_Timer = {After = function(seconds, fn) timers[#timers + 1] = {at = now + seconds, fn = fn} end}
C_AddOns = {GetAddOnMetadata = function(_, field) if field == "Version" then return "test" end end}

-- units: units.target = {player = true, hostile = true, guid = ..., name = ..., second = ..., class = ..., level = ...,
--                        faction = "Horde", onMe = true, fighting = true, dead = false}
units, me, myFaction = {}, "Player-1-ME", "Alliance"
known = {}          -- what GetPlayerInfoByGUID remembers: {guid = ..., name = ..., class = ...}
fighting = false    -- InCombatLockdown()
shift = false       -- IsShiftKeyDown()
instance = "none"   -- "none", "pvp" (a battleground), "arena", "party" ...
zone = "Tanaris"
local function U(u) return units[u] end
function UnitExists(u) return U(u) ~= nil end
function UnitIsPlayer(u) return U(u) and U(u).player end
function UnitIsEnemy(_, u) return U(u) and U(u).hostile end
function UnitCanAttack(_, u) return U(u) and U(u).hostile end
function UnitGUID(u) if u == "player" then return me end return U(u) and U(u).guid end
function UnitName(u)
	if u == "player" then return "Tk", "Deadeye" end
	local x = U(u)
	if not x then return nil end
	return x.name, x.second
end
function UnitClass(u) return "x", U(u) and U(u).class end
function UnitLevel(u) return U(u) and U(u).level end
function UnitFactionGroup(u)
	if u == "player" then return myFaction end
	local x = U(u)
	if not x then return nil end
	if x.faction ~= nil then return x.faction end
	return "Horde"
end
function UnitIsUnit(a, b)
	local base = a:match("^(.-)target$")
	if base and b == "player" then return U(base) and U(base).onMe end
	return false
end
function UnitAffectingCombat(u) return U(u) and U(u).fighting end
function UnitIsDeadOrGhost(u) return U(u) and U(u).dead end
function GetPlayerInfoByGUID(g)
	for _, v in pairs(known) do
		if v.guid == g then return "x", v.class, "r", "R", 2, v.name, v.second or "" end
	end
end
function GetRealZoneText() return zone end
function InCombatLockdown() return fighting end
function IsShiftKeyDown() return shift end
function IsInInstance() return instance ~= "none", instance end

RAID_CLASS_COLORS = {
	ROGUE = {r = 1, g = 0.96, b = 0.41}, MAGE = {r = 0.25, g = 0.78, b = 0.92},
	WARRIOR = {r = 0.78, g = 0.61, b = 0.43}, HUNTER = {r = 0.67, g = 0.83, b = 0.45},
	WARLOCK = {r = 0.53, g = 0.53, b = 0.93}, DRUID = {r = 1, g = 0.49, b = 0.04},
	PRIEST = {r = 1, g = 1, b = 1}, PALADIN = {r = 0.96, g = 0.55, b = 0.73}, SHAMAN = {r = 0, g = 0.44, b = 0.87},
}
LOCALIZED_CLASS_NAMES_MALE = {ROGUE = "Rogue", MAGE = "Mage", WARRIOR = "Warrior", HUNTER = "Hunter", WARLOCK = "Warlock",
	DRUID = "Druid", PRIEST = "Priest", PALADIN = "Paladin", SHAMAN = "Shaman"}

-- what the addon says and plays
chat, sounds = {}, {}
function PlaySoundFile(file) sounds[#sounds + 1] = file return true end
function PlaySound(id) sounds[#sounds + 1] = id return true end
SOUNDKIT = {RAID_WARNING = 8959}
DEFAULT_CHAT_FRAME = {AddMessage = function(_, m) chat[#chat + 1] = m end}
SlashCmdList = {}
UISpecialFrames = {}
popups, StaticPopupDialogs = {}, {}
function StaticPopup_Show(which, text, _, data) popups[#popups + 1] = {which = which, text = text, data = data} end

-- the game's damage meter: meter.Current / meter.Overall = list of hit(...) lines
Enum = {
	DamageMeterType = {DamageTaken = 7, Deaths = 9},
	DamageMeterSessionType = {Overall = 0, Current = 1, Expired = 2},
}
meter = {Current = {}, Overall = {}}
meterAsked = 0
local sessionName = {[0] = "Overall", [1] = "Current", [2] = "Expired"}
C_DamageMeter = {
	GetCombatSessionSourceFromType = function(session, kind, guid)
		meterAsked = meterAsked + 1
		if kind ~= 7 then return {combatSpells = {}, totalAmount = 0} end
		assert(guid == me, "asked the meter about somebody else")
		local spells = meter[sessionName[session]]
		if spells == nil then return nil end
		local total = 0
		if not issecretvalue(spells) then
			for _, s in ipairs(spells) do
				if not issecretvalue(s) and not issecretvalue(s.totalAmount) then total = total + s.totalAmount end
			end
		end
		return {combatSpells = spells, totalAmount = total}
	end,
	GetCombatSessionFromType = function(session, kind)
		if kind == 9 then return {combatSources = deaths or {}} end
		return {combatSources = {}}
	end,
}
function hit(name, class, amount, mob, pet)
	return {totalAmount = amount, spellID = 6603,
		combatSpellDetails = {unitName = name, unitClassFilename = class, isMob = mob or false, isPet = pet or false, amount = amount}}
end
-- the death recap: recaps[id] = list of events
recaps = {}
C_DeathRecap = {
	HasRecapEvents = function(id) return recaps[id] ~= nil end,
	GetRecapEvents = function(id) return recaps[id] end,
	GetRecapMaxHealth = function() return 3000 end,
}

-- frames, textures and texts: they remember what they were told, nothing more
local function obj(kind)
	local o = {kind = kind, shown = true, scripts = {}, events = {}, points = {}}
	local methods = {
		SetScript = function(s, k, f) s.scripts[k] = f end,
		GetScript = function(s, k) return s.scripts[k] end,
		RegisterEvent = function(s, e) s.events[e] = true end,
		RegisterUnitEvent = function(s, e) s.events[e] = true end,
		Show = function(s) s.shown = true end,
		Hide = function(s) s.shown = false end,
		SetShown = function(s, v) s.shown = v and true or false end,
		IsShown = function(s) return s.shown end,
		SetText = function(s, t) s.txt = t end,
		GetText = function(s) return s.txt end,
		SetTextColor = function(s, r, g, b) s.color = {r, g, b} end,
		SetVertexColor = function(s, r, g, b, a) s.vertex = {r, g, b, a} end,
		SetHeight = function(s, h) s.h = h end,
		SetWidth = function(s, v) s.width = v end,
		GetWidth = function(s) return s.width or 0 end,
		GetHeight = function(s) return s.h or 0 end,
		SetScale = function(s, v) s.scale = v end,
		GetScale = function(s) return s.scale or 1 end,
		SetAlpha = function(s, v) s.alpha = v end,
		SetSize = function(s, a, b) s.width, s.h = a, b end,
		SetValue = function(s, v) s.value = v end,
		GetValue = function(s) return s.value end,
		SetMinMaxValues = function(s, a, b) s.min, s.max = a, b end,
		SetColorTexture = function(s, r, g, b, a) s.rgba = {r, g, b, a} end,
		SetTexture = function(s, t) s.texture = t end,
		SetPoint = function(s, ...) s.points[#s.points + 1] = {...} end,
		ClearAllPoints = function(s) s.points = {} end,
		GetPoint = function() return "LEFT", nil, "LEFT", 1, 2 end,
		GetThumbTexture = function() return nil end,
		CreateFontString = function() return obj("text") end,
		CreateTexture = function() return obj("texture") end,
		AddLine = function(s, t) s.lines = s.lines or {} s.lines[#s.lines + 1] = t end,
	}
	-- (any other method of the game's, SetThis or EnableThat, is accepted and does nothing; a field never set is nil)
	return setmetatable(o, {__index = function(_, k)
		if methods[k] then return methods[k] end
		if type(k) == "string" and k:match("^%u") then return function() end end
		return nil
	end})
end
frames = {}
function CreateFrame(kind, name)
	local f = obj(kind)
	if name then _G[name] = f end
	frames[#frames + 1] = f
	return f
end
UIParent = obj("Frame")
GameTooltip = obj("GameTooltip")
GameTooltip.SetOwner = function(s) s.lines = {} end
GameTooltip.SetText = function(s, t) s.lines = {t} end

---------------------------------------------------------------------------
-- What the scenarios use
---------------------------------------------------------------------------
-- (the addon's first frame is the one that listens to the game)
local function ears() return frames[1] end
function fire(event, ...) ears().scripts.OnEvent(ears(), event, ...) end
-- lets time pass, a quarter of a second at a time, the way the game calls a visible frame
function tick(seconds)
	for _ = 1, math.floor(seconds / 0.25 + 0.5) do
		now = now + 0.25
		for i = #timers, 1, -1 do
			if timers[i].at <= now then table.remove(timers, i).fn() end
		end
		if ears().shown then ears().scripts.OnUpdate(ears(), 0.25) end
	end
end
function start()
	fire("ADDON_LOADED", "WarDrum")
	fire("PLAYER_LOGIN")
	db, list = WarDrumDB, WarDrumFrame
end
function logged(what)
	for _, l in ipairs(WarDrumDB.log) do if l:find(what, 1, true) then return true end end
	return false
end
function said(what)
	local n = 0
	for _, m in ipairs(chat) do if m:find(what, 1, true) then n = n + 1 end end
	return n
end
function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function slash(msg) SlashCmdList["WARDRUM"](msg or "") end
-- an enemy player; pass what differs from a level 36 rogue who is on you and fighting
function enemy(guid, name, more)
	local u = {player = true, hostile = true, guid = guid, name = name, class = "ROGUE", level = 36, onMe = true, fighting = true, dead = false}
	for k, v in pairs(more or {}) do u[k] = v end
	return u
end
function plate(unit, u) units[unit] = u fire("NAME_PLATE_UNIT_ADDED", unit) end
function unplate(unit) units[unit] = nil fire("NAME_PLATE_UNIT_REMOVED", unit) end
function fightStarts() fighting = true fire("PLAYER_REGEN_DISABLED") end
function fightEnds() fighting = false fire("PLAYER_REGEN_ENABLED") end
function options()
	if not (WarDrumOptionsFrame and WarDrumOptionsFrame.shown) then slash("") end
	return WarDrumOptionsFrame, WarDrumOptionsFrame.controls
end
function click(widget) widget.scripts.OnClick(widget) end
-- nothing may have gone wrong inside the addon
function noProblems()
	for _, l in ipairs(WarDrumDB.log) do
		assert(not l:find("problem in", 1, true), l)
	end
end
