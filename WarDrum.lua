-- War Drum: a small window listing the enemy players who attack you.
--
-- WoW Forever gives addons no combat log, but its built-in damage meter knows
-- who damaged you, and after a fight an addon may read it. So:
--   * during a fight, an enemy player seen targeting you (nameplate, target,
--     mouseover, focus) shows on the list at once;
--   * after the fight the damage meter settles it: everyone who damaged you is
--     an attacker (seen or not), and anyone who never did is taken off again;
--   * die with them having damaged you, and it counts as their kill.
--
-- Who never counts: players of your own faction (duels), anyone in a
-- battleground or arena (unless you switch that on), and a player you attacked
-- first while they were neither fighting nor targeting you.
--
-- It also keeps a short record (WarDrumDB.log) of what the game showed during
-- those fights and at your death, so the detection can be checked against what
-- really happened. /wd dump adds the damage meter's full view to it.
--
-- Some things the game hides during a fight (often names and levels). Whatever
-- is hidden is filled in as soon as it can be read; nothing hidden is ever
-- compared, printed or saved.

local ADDON = "War Drum"
local LOG_MAX = 600
local ATTACK_AGAIN = 30   -- seconds before the same player counts as attacking you again
local KILL_WINDOW = 15    -- you died this soon after they were on you: their kill (when the meter can't be read)
local NEAR_FOR = 20       -- the list marks a player as nearby this long after seeing them
local WARN_AGAIN = 60     -- at most one warning a minute about the same player
local SCAN_EVERY = 0.5

local db
local frame = CreateFrame("Frame")
local window, options
local demo = false        -- /wd demo: the list shows sample players (nothing is saved)

local DEFAULTS = {
	width = 200, scale = 1, alpha = 0.9, rows = 10, showLevel = true, showClass = true, lock = false,
	onlyDamage = true, skipBG = true, alert = true, sound = "DRUM",
}
local function Opt(key)
	local v = db and db.settings and db.settings[key]
	if v == nil then return DEFAULTS[key] end
	return v
end

local function Say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffcc3322" .. ADDON .. "|r: " .. msg) end

-- The warning sounds: the addon's own war drum, the game's raid warning, or none
local SOUNDS = {
	DRUM = {name = "War drum", file = "Interface\\AddOns\\WarDrum\\media\\WarDrum.ogg"},
	WARNING = {name = "Raid warning", kit = "RAID_WARNING"},
	NONE = {name = "No sound"},
}
local SOUND_ORDER = {"DRUM", "WARNING", "NONE"}
local function PlayWarning(which)
	local sound = SOUNDS[which or Opt("sound")]
	if not sound then return end
	if sound.file and PlaySoundFile then
		pcall(PlaySoundFile, sound.file, "Master")
	elseif sound.kit and SOUNDKIT and SOUNDKIT[sound.kit] and PlaySound then
		pcall(PlaySound, SOUNDKIT[sound.kit], "Master")
	end
end

---------------------------------------------------------------------------
-- Reading the game safely
---------------------------------------------------------------------------
local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Plain(v) if IsSecret(v) then return nil end return v end
-- for the record: a value as text, without touching a hidden one
local function S(v)
	if IsSecret(v) then return "HIDDEN" end
	return tostring(v)
end
-- calls a game function that may not exist or may refuse; returns its results or nothing
local function Ask(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d, e, f, g
end

local function Log(msg)
	if not db then return end
	local log = db.log
	log[#log + 1] = string.format("%s %.1f  %s", date("%H:%M:%S"), GetTime(), msg)
	while #log > LOG_MAX do table.remove(log, 1) end
end

-- a table from the game as one line of text (keys and values, a little way down)
local function Describe(t, depth, maxItems)
	if IsSecret(t) then return "HIDDEN" end
	if type(t) ~= "table" then return S(t) end
	depth, maxItems = depth or 1, maxItems or 12
	local parts, n = {}, 0
	for k, v in pairs(t) do
		n = n + 1
		if n > maxItems then
			parts[#parts + 1] = "..."
			break
		end
		local value
		if IsSecret(v) then
			value = "HIDDEN"
		elseif type(v) == "table" then
			value = depth > 0 and ("{" .. Describe(v, depth - 1, maxItems) .. "}") or "{...}"
		else
			value = tostring(v)
		end
		parts[#parts + 1] = S(k) .. "=" .. value
	end
	return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Enemy players in view
---------------------------------------------------------------------------
-- Names on Forever have two parts ("Tk Deadeye"). For a unit the game returns
-- them as two values; its damage meter writes them as one, with a space.
local function FullName(first, second)
	if not first or first == "" then return nil end
	if second and second ~= "" then return first .. " " .. second end
	return first
end

local FIXED_UNITS = {"target", "focus", "mouseover"}
local plates = {}  -- the nameplates now on screen (unit -> true), kept from the game's own events
local ownSide = {} -- this session: names of players of your own faction who were hostile for a while (a duel)

-- What can be read of an enemy player on this unit (nil: not an enemy player)
local function ReadUnit(unit)
	if not Plain(Ask(UnitExists, unit)) then return nil end
	if not Plain(Ask(UnitIsPlayer, unit)) then return nil end
	local hostile = Plain(Ask(UnitIsEnemy, "player", unit))
	if hostile == nil then hostile = Plain(Ask(UnitCanAttack, "player", unit)) end
	if not hostile then return nil end
	local name, second = Ask(UnitName, unit)
	name = FullName(Plain(name), Plain(second))
	-- Your own faction can only fight you in a duel: never listed, and remembered by name so the
	-- damage meter's word about them is ignored as well
	local theirs, mine = Plain(Ask(UnitFactionGroup, unit)), Plain(Ask(UnitFactionGroup, "player"))
	if theirs and mine and theirs == mine then
		if name then ownSide[name] = true end
		return nil
	end
	local info = {unit = unit}
	info.guid = Plain(Ask(UnitGUID, unit))
	info.name = name
	local _, classFile = Ask(UnitClass, unit)
	info.class = Plain(classFile)
	info.level = Plain(Ask(UnitLevel, unit))
	info.onMe = Plain(Ask(UnitIsUnit, unit .. "target", "player")) -- true / false, nil when the game hides it
	info.fighting = Plain(Ask(UnitAffectingCombat, unit))
	info.dead = Plain(Ask(UnitIsDeadOrGhost, unit))
	return info
end

local function UnitLine(info)
	return string.format("%s guid=%s name=%s class=%s level=%s onMe=%s fighting=%s dead=%s", info.unit, tostring(info.guid),
		tostring(info.name), tostring(info.class), tostring(info.level), tostring(info.onMe), tostring(info.fighting), tostring(info.dead))
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local seen = {}       -- this session: key -> {info, at}: enemy players lately in view
local nearAt = {}     -- key -> when a listed player was last in view
local warnedAt = {}   -- key -> when you were last warned about them
local onMeAt = {}     -- key -> when they were last seen on you in a fight
local inCombat = false
local deadHandled = 0
local fightStartedAt, fightEndedAt = 0, 0

-- this fight only
local pending = {}     -- key -> true: counted only because they were targeting you (the meter confirms or takes it back)
local counted = {}     -- key -> true: their attack in this fight has been counted
local started = {}     -- key -> true: you attacked them first
local startedName = {} -- the same, by name (for what the damage meter says)
local death            -- your death in this fight: {at, credited = {key -> true}, settled}
local lastTargetKey    -- the enemy player you have targeted

local dirty, lastDraw = true, 0
local index, indexStale = {}, true -- name -> key, rebuilt when the list changes

local function Redraw()
	dirty = true
end

local function NameKey(name) return name and ("name:" .. name) or nil end
local function KeyOf(info) return info.guid or NameKey(info.name) end

local function FindByName(name)
	if not name then return nil end
	if indexStale then
		index = {}
		for key, e in pairs(db.players) do
			if e.name and (index[e.name] == nil or e.guid) then index[e.name] = key end
		end
		indexStale = false
	end
	local key = index[name]
	local e = key and db.players[key]
	if e and e.name == name then return e, key end
end

-- name and class from the game's own memory of a player it has seen
local function FillFromGUID(entry)
	if not entry.guid or (entry.name and entry.class) then return end
	local _, classFile, _, _, _, name, second = Ask(GetPlayerInfoByGUID, entry.guid)
	if not entry.name then
		entry.name = FullName(Plain(name), Plain(second))
		if entry.name then indexStale = true end
	end
	entry.class = entry.class or Plain(classFile)
end

-- what this session remembers about a list entry follows it to its new key, or is dropped with it
local function Rekey(old, new)
	for _, t in ipairs({nearAt, warnedAt, onMeAt, pending, counted, started}) do
		if t[old] ~= nil then
			if new and t[new] == nil then t[new] = t[old] end
			t[old] = nil
		end
	end
	if lastTargetKey == old then lastTargetKey = new end
end

local function Remove(key)
	db.players[key] = nil
	Rekey(key, nil)
	indexStale = true
	Redraw()
end

-- two entries turned out to be the same player
local function Merge(into, from)
	into.attacks = (into.attacks or 0) + (from.attacks or 0)
	into.kills = (into.kills or 0) + (from.kills or 0)
	into.mine = (into.mine or 0) + (from.mine or 0)
	if from.first and (not into.first or from.first < into.first) then into.first = from.first end
	if (from.last or 0) > (into.last or 0) then into.last, into.zone = from.last, from.zone end
	if (from.lastAttack or 0) > (into.lastAttack or 0) then into.lastAttack = from.lastAttack end
	if (from.lastMine or 0) > (into.lastMine or 0) then into.lastMine = from.lastMine end
	into.name = into.name or from.name
	into.class = into.class or from.class
	into.level = into.level or from.level
	into.confirmed = into.confirmed or from.confirmed
end

-- A player listed by name alone (from the damage meter) whose id is now known under another entry: one entry
local function Tidy()
	local byName, twins = {}, nil
	for key, e in pairs(db.players) do
		if e.guid and e.name then byName[e.name] = key end
	end
	for key, e in pairs(db.players) do
		local into = not e.guid and e.name and byName[e.name]
		if into then
			twins = twins or {}
			twins[key] = into
		end
	end
	if not twins then return end
	for key, into in pairs(twins) do
		Merge(db.players[into], db.players[key])
		db.players[key] = nil
		Rekey(key, into)
	end
	indexStale = true
	Redraw()
end

-- The list's entry for this player (made if asked), with whatever is readable now filled in
local function Entry(info, create)
	local key = KeyOf(info)
	if not key then return nil end
	local e = db.players[key]
	local twin, twinKey = FindByName(info.name)
	if twin and twin ~= e then
		if not info.guid then
			e, key = twin, twinKey -- no id readable right now: it is the listed player of that name
		elseif not twin.guid then
			-- listed by name alone so far: now the game shows their id
			if e then Merge(e, twin) else e = twin end
			db.players[twinKey] = nil
			db.players[key] = e
			Rekey(twinKey, key)
			indexStale = true
		end
		-- (a twin with another id is another player of the same name)
	end
	if not e and create then
		e = {first = time(), attacks = 0, kills = 0, mine = 0}
		db.players[key] = e
		indexStale = true
	end
	if not e then return nil end
	e.guid = info.guid or e.guid
	if info.name and e.name ~= info.name then
		e.name = info.name
		indexStale = true
	end
	e.class = info.class or e.class
	if info.level and info.level ~= 0 then e.level = info.level end -- (-1: too high for the game to tell you)
	FillFromGUID(e)
	return e, key
end

local function Zone()
	return Plain(Ask(GetRealZoneText)) or Plain(Ask(GetZoneText)) or ""
end

-- Battlegrounds and arenas are fights you signed up for: with "Not in battlegrounds" on,
-- nobody is listed, counted or announced while you are in one
local function Paused()
	if not Opt("skipBG") then return false end
	local _, kind = Ask(IsInInstance)
	kind = Plain(kind)
	return kind == "pvp" or kind == "arena"
end

local function DrawIfNeeded()
	if not (window and window:IsShown()) then return end
	local now = GetTime()
	-- (the "nearby" marks fade by themselves: while one is lit, look again every couple of seconds)
	if dirty or (window.anyNear and now - lastDraw > 2) then
		dirty, lastDraw = false, now
		window.Draw()
	end
end

-- They are attacking you: on the list (once per fight)
local function Attacked(info, why)
	local rawKey = KeyOf(info)
	if (rawKey and started[rawKey]) or (info.name and startedName[info.name]) then return end -- your fight, not theirs
	local e, key = Entry(info, true)
	if not e then return end
	local now = time()
	onMeAt[key] = GetTime()
	if not counted[key] and (not e.lastAttack or now - e.lastAttack >= ATTACK_AGAIN) then
		e.attacks = e.attacks + 1
		counted[key] = true
		-- only seen targeting you: the damage meter confirms it after the fight, or takes it back
		if why == "targeting you in a fight" then pending[key] = true end
		Log(string.format("ATTACK (%s): %s -> attacks %d", why, UnitLine(info), e.attacks))
	end
	e.last, e.zone, e.lastAttack = now, Zone(), now
	-- (they are on you: no "is near" warning on top of that)
	nearAt[key] = GetTime()
	warnedAt[key] = GetTime()
	Redraw()
end

-- Harmful effects on you name the unit that cast them, when the game says so
local function ScanDebuffs()
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
		if not ok or IsSecret(aura) or type(aura) ~= "table" then break end
		local source = Plain(aura.sourceUnit)
		if source then
			local info = ReadUnit(source)
			if info then Attacked(info, "their effect on you") end
		end
	end
end

local function ColorName(e)
	local c = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
	local name = e.name or "A listed player"
	if not c then return name end
	return string.format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), name)
end

local lastEnemySeen, lastUnreadable = 0, 0
-- Looks at one unit. True when it is an enemy player.
local function Look(unit, now, paused)
	local info = ReadUnit(unit)
	if not info then
		if unit == "target" then lastTargetKey = nil end
		return false
	end
	lastEnemySeen = now
	if not KeyOf(info) then
		if unit == "target" then lastTargetKey = nil end
		if inCombat and now - lastUnreadable > 10 then
			lastUnreadable = now
			Log("seen, nothing readable: " .. UnitLine(info))
		end
		return true
	end
	local e, key = Entry(info, false) -- already on the list: fill in what is readable now
	key = key or KeyOf(info)
	if unit == "target" then lastTargetKey = key end
	local was = seen[key]
	if not was or now - (was.logged or 0) > 30 then
		Log("seen: " .. UnitLine(info))
		seen[key] = {info = info, at = now, logged = now}
	else
		was.info, was.at = info, now
	end
	if e and not paused then
		if not nearAt[key] or now - nearAt[key] > NEAR_FOR then
			dirty = true
			if Opt("alert") and not info.dead and (not warnedAt[key] or now - warnedAt[key] > WARN_AGAIN) then
				warnedAt[key] = now
				Say(ColorName(e) .. " is near" .. (e.kills > 0 and (" (killed you " .. e.kills .. "x)") or "") .. ".")
				PlayWarning()
			end
		end
		nearAt[key] = now
		-- you had them targeted, they were fighting you, and they died: your kill
		if info.dead and key == lastTargetKey and e.lastAttack and time() - e.lastAttack < 60 and (not e.lastMine or time() - e.lastMine > 60) then
			e.mine = e.mine + 1
			e.lastMine = time()
			dirty = true
			Log("YOUR KILL: " .. UnitLine(info))
		end
	end
	-- In a fight, targeting you, and in combat themselves (or the game won't say): an attacker
	if inCombat and not paused and info.onMe and info.fighting ~= false and not info.dead then
		Attacked(info, "targeting you in a fight")
	end
	return true
end

-- what this session remembers about players long gone
local lastPrune = 0
local function Prune(now)
	if now - lastPrune < 60 then return end
	lastPrune = now
	for key, was in pairs(seen) do if now - was.at > 120 then seen[key] = nil end end
	for _, t in ipairs({nearAt, warnedAt, onMeAt}) do
		for key, at in pairs(t) do if now - at > 120 then t[key] = nil end end
	end
end

local function Scan()
	local now, paused = GetTime(), Paused()
	for _, unit in ipairs(FIXED_UNITS) do Look(unit, now, paused) end
	for unit in pairs(plates) do Look(unit, now, paused) end
	if inCombat and not paused then ScanDebuffs() end
	Prune(now)
	DrawIfNeeded()
	-- keep looking twice a second while you fight or enemy players are about; otherwise the game's events wake it
	frame:SetShown(inCombat or now - lastEnemySeen < 15 or (window ~= nil and window:IsShown() and now - lastEnemySeen < 60))
end

---------------------------------------------------------------------------
-- The game's damage meter: who damaged you
---------------------------------------------------------------------------
-- Enemy players (not creatures, not pets, not you, not your own faction) in the
-- "damage taken" breakdown of a meter session: name -> {class, amount}.
-- nil when the meter can't be read. The second result is true when part of it
-- was hidden (so "not in the list" proves nothing). The third tells one
-- session from the next.
local function MeterAttackers(sessionName)
	if not (C_DamageMeter and Enum and Enum.DamageMeterType and Enum.DamageMeterSessionType) then return nil end
	local typeId, sessionId = Enum.DamageMeterType.DamageTaken, Enum.DamageMeterSessionType[sessionName]
	local me = Plain(Ask(UnitGUID, "player"))
	if typeId == nil or sessionId == nil or not me then return nil end
	local mine = Plain(Ask(C_DamageMeter.GetCombatSessionSourceFromType, sessionId, typeId, me))
	if type(mine) ~= "table" then return nil end
	local spells = Plain(mine.combatSpells)
	if type(spells) ~= "table" then return nil end
	local first, second = Ask(UnitName, "player")
	local myName = FullName(Plain(first), Plain(second))
	local found, hidden = {}, false
	for _, spell in ipairs(spells) do
		spell = Plain(spell)
		local d = type(spell) == "table" and Plain(spell.combatSpellDetails)
		if type(d) ~= "table" then
			hidden = true
		else
			local name, isMob = Plain(d.unitName), Plain(d.isMob)
			if name == nil or isMob == nil or IsSecret(d.isPet) then
				hidden = true
			elseif isMob == false and not d.isPet and name ~= "" and name ~= myName and not ownSide[name] then
				local f = found[name]
				if not f then
					f = {amount = 0}
					found[name] = f
				end
				f.class = Plain(d.unitClassFilename) or f.class
				f.amount = f.amount + (Plain(spell.totalAmount) or 0)
			end
		end
	end
	local names = {}
	for name in pairs(found) do names[#names + 1] = name end
	table.sort(names)
	for i, name in ipairs(names) do names[i] = name .. "=" .. tostring(found[name].amount) end
	local signature = tostring(Plain(mine.totalAmount) or "?") .. "|" .. #spells .. "|" .. table.concat(names, ",")
	return found, hidden, signature
end

-- The meter says this player damaged you in this fight
local function DamagedBy(name, class, amount)
	local e, key = FindByName(name)
	if not e then
		key = NameKey(name)
		e = {first = time(), attacks = 0, kills = 0, mine = 0, name = name}
		db.players[key] = e
		indexStale = true
	end
	e.class = e.class or class
	e.confirmed = true
	pending[key] = nil
	if not counted[key] and (not e.lastAttack or time() - e.lastAttack >= ATTACK_AGAIN) then
		e.attacks = e.attacks + 1
	end
	counted[key] = true
	e.last, e.zone, e.lastAttack = time(), Zone(), time()
	Log(string.format("meter: %s (%s) damaged you for %s -> attacks %d", name, tostring(class), tostring(amount), e.attacks))
	return e, key
end

-- After a fight: everyone who damaged you is an attacker; anyone listed only for
-- targeting you who never damaged you is taken off again.
local function Settle(again)
	local found, hidden, signature = MeterAttackers("Current")
	if Paused() then
		if signature then db.lastSession = signature end
		pending, death = {}, nil
		return
	end
	if not found then
		-- the meter can't be read this instant: once more in a moment, then leave things as they are
		if not again and C_Timer and C_Timer.After then
			C_Timer.After(1.5, function()
				if not inCombat then pcall(Settle, true) end
			end)
		else
			pending, death = {}, nil
		end
		return
	end
	local fresh = signature ~= db.lastSession -- (the same session twice means this fight left no trace in the meter)
	db.lastSession = signature
	if fresh then
		for name, f in pairs(found) do
			if startedName[name] then
				Log("not listed: you attacked " .. name .. " first")
			else
				DamagedBy(name, f.class, f.amount)
			end
		end
		-- You died while the meter was unreadable and the kill went to whoever was seen on you: now it is known
		if death and not death.settled and death.at >= fightStartedAt then
			for name in pairs(found) do
				local e, key = FindByName(name)
				if e and not startedName[name] and not death.credited[key] then
					e.kills = e.kills + 1
					Log(string.format("KILLED BY %s (the damage meter, after the fight) -> kills %d", name, e.kills))
				end
			end
			if not hidden then
				for key in pairs(death.credited) do
					local e = db.players[key]
					if e and not (e.name and found[e.name]) then
						e.kills = math.max(0, e.kills - 1)
						Log("kill taken back: " .. tostring(e.name) .. " never damaged you")
					end
				end
			end
		end
	end
	death = nil
	if not hidden and Opt("onlyDamage") then
		for key in pairs(pending) do
			local e = db.players[key]
			if e then
				e.attacks = math.max(0, e.attacks - 1)
				Log("taken back: " .. tostring(e.name) .. " was targeting you but never damaged you")
				if e.attacks == 0 and e.kills == 0 then Remove(key) end
			end
		end
	end
	pending = {}
	Redraw()
end

---------------------------------------------------------------------------
-- The record of what the game shows (to check the detection against)
---------------------------------------------------------------------------
local function LogInventory()
	local function keys(t)
		if type(t) ~= "table" then return "none" end
		local list = {}
		for k in pairs(t) do list[#list + 1] = tostring(k) end
		table.sort(list)
		return table.concat(list, " ")
	end
	Log("game: C_DamageMeter = " .. keys(C_DamageMeter))
	Log("game: DamageMeterType = " .. keys(Enum and Enum.DamageMeterType))
	Log("game: DamageMeterSessionType = " .. keys(Enum and Enum.DamageMeterSessionType))
	Log("game: C_DeathRecap = " .. keys(C_DeathRecap))
end

local triedRecap = {}
local function LogRecapById(id, from)
	id = Plain(id)
	if not id or id == 0 or not C_DeathRecap or triedRecap[id] then return end
	triedRecap[id] = true
	Log(string.format("recap id %s (from %s): has=%s maxHealth=%s", tostring(id), from,
		S(Ask(C_DeathRecap.HasRecapEvents, id)), S(Ask(C_DeathRecap.GetRecapMaxHealth, id))))
	local events = Plain(Ask(C_DeathRecap.GetRecapEvents, id))
	if type(events) == "table" then
		Log("  " .. #events .. " recap events")
		for i = 1, math.min(#events, 8) do Log("  recap " .. i .. ": " .. Describe(events[i], 1, 18)) end
	else
		Log("  GetRecapEvents(" .. tostring(id) .. ") = " .. S(events))
	end
end

-- What the built-in damage meter says about damage you took and about deaths.
-- everything: all its sessions (on request); otherwise only the fight just over.
local function LogDamageMeter(why, everything)
	if not (C_DamageMeter and Enum and Enum.DamageMeterType and Enum.DamageMeterSessionType) then return end
	local me = Plain(Ask(UnitGUID, "player"))
	for typeName, typeId in pairs(Enum.DamageMeterType) do
		local lower = tostring(typeName):lower()
		if lower == "damagetaken" or lower == "deaths" or (everything and lower:find("taken", 1, true)) then
			for sessionName, sessionId in pairs(Enum.DamageMeterSessionType) do
				if everything or sessionName == "Current" then
					local session = Plain(Ask(C_DamageMeter.GetCombatSessionFromType, sessionId, typeId))
					if type(session) == "table" then
						local sources = Plain(session.combatSources)
						Log(string.format("meter %s [%s / %s]: %s", why, tostring(typeName), tostring(sessionName), Describe(session, 0, 10)))
						if type(sources) == "table" then
							for i = 1, math.min(#sources, 6) do
								local source = Plain(sources[i])
								Log("  source " .. i .. ": " .. Describe(source, 0, 16))
								if type(source) == "table" then LogRecapById(source.deathRecapID, "the meter's deaths") end
							end
						end
					end
					if me then
						local mine = Plain(Ask(C_DamageMeter.GetCombatSessionSourceFromType, sessionId, typeId, me))
						if type(mine) == "table" then
							Log(string.format("meter %s [%s / %s] on you: %s", why, tostring(typeName), tostring(sessionName), Describe(mine, 0, 10)))
							local spells = Plain(mine.combatSpells)
							if type(spells) == "table" then
								for i = 1, math.min(#spells, 8) do Log("  spell " .. i .. ": " .. Describe(spells[i], 2, 14)) end
							end
						end
					end
				end
			end
		end
	end
end

local function LogDeathRecap()
	if C_DeathRecap then
		Log("recap: HasRecapEvents() = " .. S(Ask(C_DeathRecap.HasRecapEvents)))
		local events = Plain(Ask(C_DeathRecap.GetRecapEvents))
		if type(events) == "table" then
			Log("recap: " .. #events .. " events")
			for i = 1, math.min(#events, 6) do Log("  recap " .. i .. ": " .. Describe(events[i], 1, 16)) end
		else
			Log("recap: GetRecapEvents() = " .. S(events))
		end
	end
	if DeathRecap_GetEvents then
		local events = Plain(Ask(DeathRecap_GetEvents))
		Log("recap (old): " .. (type(events) == "table" and (#events .. " events; first: " .. Describe(events[1], 1, 16)) or S(events)))
	end
end

-- You died. Whoever damaged you in this fight killed you: the damage meter names them when it
-- can be read; otherwise it is whoever was seen on you just before, put right after the fight.
local function Died()
	if GetTime() - deadHandled < 5 then return end
	deadHandled = GetTime()
	local now, credited, n = GetTime(), {}, 0
	if Paused() then
		Log("YOU DIED in a battleground: not counted")
		return
	end
	local inFight = inCombat or now - fightEndedAt < 5
	local found, hidden, signature = MeterAttackers("Current")
	-- (during a fight the meter may still be showing the one before: then it says nothing about this death)
	local thisFight = found ~= nil and ((inCombat and signature ~= db.lastSession) or (not inCombat and now - fightEndedAt < 5))
	local settled = false
	if thisFight and next(found) then
		settled = true
		for name, f in pairs(found) do
			if not startedName[name] then
				local e, key = DamagedBy(name, f.class, f.amount)
				e.kills = e.kills + 1
				credited[key], n = true, n + 1
				Log(string.format("KILLED BY %s (the damage meter: %s damage on you) -> kills %d", name, tostring(f.amount), e.kills))
			end
		end
	elseif thisFight and not hidden then
		settled = true -- the meter is readable and names no player: a creature, a fall
	elseif inFight then
		for key, at in pairs(onMeAt) do
			local e = db.players[key]
			if e and now - at <= KILL_WINDOW and not started[key] then
				e.kills = e.kills + 1
				e.last, e.zone = time(), Zone()
				credited[key], n = true, n + 1
				Log(string.format("KILLED BY %s (%s): on you %.1fs before you died -> kills %d", tostring(e.name), tostring(key), now - at, e.kills))
			end
		end
	end
	death = {at = now, credited = credited, settled = settled}
	Log(string.format("YOU DIED in %s%s; %d listed player(s) credited", Zone(), inFight and "" or " (not in a fight)", n))
	for _, was in pairs(seen) do
		if now - was.at <= 20 then Log(string.format("  in view %.1fs before: %s", now - was.at, UnitLine(was.info))) end
	end
	LogDeathRecap()
	LogDamageMeter("at death")
	Redraw()
	DrawIfNeeded()
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local ROW_H, MAX_ROWS = 16, 20
local CLASS_NAMES = LOCALIZED_CLASS_NAMES_MALE or {}

local SAMPLE = { -- what /wd demo and the options' preview show
	{name = "Stabby Pants", class = "ROGUE", level = 36, kills = 2, attacks = 5, mine = 1, zone = "Stranglethorn Vale", near = true},
	{name = "Frost Bolter", class = "MAGE", level = -1, kills = 1, attacks = 1, mine = 0, zone = "Tanaris"},
	{name = "Gruk Thar", class = "WARRIOR", level = 33, kills = 0, attacks = 2, mine = 2, zone = "Arathi Highlands"},
	{name = "Dot Dotter", class = "WARLOCK", level = 38, kills = 3, attacks = 4, mine = 0, zone = "Stranglethorn Vale"},
	{name = "Twang Longbow", class = "HUNTER", level = 35, kills = 0, attacks = 1, mine = 1, zone = "Desolace"},
	{name = "Moo Stomper", class = "DRUID", level = 29, kills = 0, attacks = 1, mine = 0, zone = "Hillsbrad Foothills"},
	{name = "Holy Smiter", class = "PRIEST", level = 34, kills = 1, attacks = 2, mine = 0, zone = "Swamp of Sorrows"},
}

local function ClassColor(classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c then return c.r, c.g, c.b end
	return 0.75, 0.75, 0.75
end

local function Ago(t)
	local s = time() - (t or 0)
	if s < 90 then return "just now" end
	if s < 5400 then return math.floor(s / 60 + 0.5) .. "m ago" end
	if s < 129600 then return math.floor(s / 3600 + 0.5) .. "h ago" end
	return math.floor(s / 86400 + 0.5) .. "d ago"
end

-- newest first
local function SortedPlayers()
	local list = {}
	if demo then
		for i, e in ipairs(SAMPLE) do list[i] = {e = e} end
		return list
	end
	for key, e in pairs(db.players) do list[#list + 1] = {key = key, e = e} end
	table.sort(list, function(a, b)
		if (a.e.last or 0) ~= (b.e.last or 0) then return (a.e.last or 0) > (b.e.last or 0) end
		return tostring(a.key) < tostring(b.key)
	end)
	return list
end

local function Solid(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	t:SetColorTexture(r, g, b, a)
	return t
end

-- One line of the list (also used by the options' preview)
local function NewRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row.wash = Solid(row, "BACKGROUND", 1, 0.2, 0.15, 0.10) -- behind a player who is near you
	row.wash:SetAllPoints(row)
	row.wash:Hide()
	row.hover = Solid(row, "BORDER", 1, 1, 1, 0.06)
	row.hover:SetAllPoints(row)
	row.hover:Hide()
	row.near = Solid(row, "ARTWORK", 1, 0.2, 0.15, 1) -- lit while they are near you
	row.near:SetSize(3, ROW_H - 6)
	row.near:SetPoint("LEFT", 0, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.level:SetJustifyH("RIGHT")
	row.level:SetWordWrap(false)
	row.class = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.class:SetJustifyH("LEFT")
	row.class:SetWordWrap(false)
	row.kills = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.kills:SetJustifyH("RIGHT")
	row.kills:SetWordWrap(false)
	return row
end

-- Lays a row's columns out for the list's width and for what is switched on:
-- name | level | class | kills, with the name taking whatever room is left
local function LayoutRow(row, width)
	local used = 3
	row.kills:ClearAllPoints()
	row.kills:SetPoint("RIGHT", row, "RIGHT", -used, 0)
	row.kills:SetWidth(24)
	used = used + 24 + 4
	local showClass, showLevel = Opt("showClass"), Opt("showLevel")
	row.class:SetShown(showClass)
	if showClass then
		row.class:ClearAllPoints()
		row.class:SetPoint("RIGHT", row, "RIGHT", -used, 0)
		row.class:SetWidth(48)
		used = used + 48 + 4
	end
	row.level:SetShown(showLevel)
	if showLevel then
		row.level:ClearAllPoints()
		row.level:SetPoint("RIGHT", row, "RIGHT", -used, 0)
		row.level:SetWidth(18)
		used = used + 18 + 5
	end
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row, "LEFT", 7, 0)
	row.name:SetWidth(math.max(40, width - 7 - used))
end

local function FillRow(row, e, near)
	local r, g, b = ClassColor(e.class)
	row.name:SetText(e.name or "Unknown player")
	row.name:SetTextColor(r, g, b)
	row.level:SetText(e.level == nil and "" or (e.level < 0 and "??" or tostring(e.level)))
	row.class:SetText(e.class and (CLASS_NAMES[e.class] or e.class) or "")
	row.class:SetTextColor(r, g, b)
	row.kills:SetText(e.kills > 0 and ("|cffff5544" .. e.kills .. "x|r") or "")
	row.near:SetShown(near and true or false)
	row.wash:SetShown(near and true or false)
end

local OpenOptions -- (defined with the options window, below)

-- Puts the list where it was left: its top-left corner, in screen units, so it grows
-- downwards and stays put when its size setting changes
local function Place(w)
	local s = w:GetScale() or 1
	if s <= 0 then s = 1 end
	local pos = db.pos
	w:ClearAllPoints()
	if type(pos) == "table" and #pos == 2 then
		w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1] / s, pos[2] / s)
	else
		w:SetPoint("TOPLEFT", UIParent, "LEFT", 40 / s, 200 / s)
	end
end

local function BuildWindow()
	local w = CreateFrame("Frame", "WarDrumFrame", UIParent)
	w:SetSize(Opt("width"), 40)
	w:SetFrameStrata("MEDIUM")
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	w:RegisterForDrag("LeftButton")
	w:SetScale(Opt("scale"))
	local function dragStart() if not Opt("lock") then w:StartMoving() end end
	local function dragStop()
		w:StopMovingOrSizing()
		local s, left, top = w:GetScale() or 1, w:GetLeft(), w:GetTop()
		if left and top then
			db.pos = {left * s, top * s}
			Place(w)
		end
	end
	w:SetScript("OnDragStart", dragStart)
	w:SetScript("OnDragStop", dragStop)
	-- (earlier versions saved the anchor the game happened to pick: put it there once, then keep the corner)
	local pos = db.pos
	if type(pos) == "table" and #pos == 4 then
		w:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
		local s, left, top = w:GetScale() or 1, w:GetLeft(), w:GetTop()
		db.pos = left and top and {left * s, top * s} or nil
	end
	Place(w)
	w.bg = Solid(w, "BACKGROUND", 0.04, 0.04, 0.05, 0.9)
	w.bg:SetAllPoints(w)
	w.top = Solid(w, "BORDER", 0.55, 0.12, 0.1, 1) -- brighter while someone on the list is near
	w.top:SetPoint("TOPLEFT")
	w.top:SetPoint("TOPRIGHT")
	w.top:SetHeight(1)

	w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	w.title:SetPoint("TOPLEFT", 6, -5)
	w.title:SetText(ADDON)
	w.count = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	w.count:SetPoint("LEFT", w.title, "RIGHT", 6, 0)
	local close = CreateFrame("Button", nil, w)
	close:SetSize(16, 16)
	close:SetPoint("TOPRIGHT", -2, -2)
	close.text = close:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	close.text:SetPoint("CENTER")
	close.text:SetText("x")
	close:SetScript("OnClick", function()
		db.shown = false
		w:Hide()
		Say("hidden. Type /wd show to bring it back.")
	end)
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(0.5, 0.5, 0.5) end)
	w.close = close
	-- the options: three short bars
	local menu = CreateFrame("Button", nil, w)
	menu:SetSize(16, 16)
	menu:SetPoint("RIGHT", close, "LEFT", -1, 0)
	menu.bars = {}
	for i = 1, 3 do
		local bar = Solid(menu, "ARTWORK", 0.55, 0.52, 0.45, 1)
		bar:SetSize(8, 1)
		bar:SetPoint("CENTER", 0, 5 - i * 3)
		menu.bars[i] = bar
	end
	menu:SetScript("OnClick", function() OpenOptions() end)
	menu:SetScript("OnEnter", function(self) for _, bar in ipairs(self.bars) do bar:SetColorTexture(1, 0.82, 0.3, 1) end end)
	menu:SetScript("OnLeave", function(self) for _, bar in ipairs(self.bars) do bar:SetColorTexture(0.55, 0.52, 0.45, 1) end end)
	w.menu = menu

	w.empty = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	w.empty:SetPoint("TOPLEFT", 11, -22)
	w.empty:SetJustifyH("LEFT")
	w.empty:SetWordWrap(false)
	w.empty:SetText("No attackers yet.")

	-- how far down the list you have scrolled, when there are more players than rows
	w.mark = Solid(w, "OVERLAY", 0.54, 0.46, 0.27, 0.7)
	w.mark:SetWidth(2)
	w.mark:Hide()

	w.rows, w.offset = {}, 0
	for i = 1, MAX_ROWS do
		local row = NewRow(w)
		row:SetPoint("TOPLEFT", 4, -20 - (i - 1) * ROW_H)
		row:SetPoint("RIGHT", w, "RIGHT", -4, 0)
		row:RegisterForClicks("RightButtonUp")
		row:RegisterForDrag("LeftButton") -- (the rows cover the list: it moves by them too)
		row:SetScript("OnDragStart", dragStart)
		row:SetScript("OnDragStop", dragStop)
		row:SetScript("OnClick", function(self)
			if self.key and IsShiftKeyDown() then
				Remove(self.key)
				w.Draw()
			end
		end)
		row:SetScript("OnEnter", function(self)
			self.hover:Show()
			local e = self.entry
			if not e or not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local r, g, b = ClassColor(e.class)
			GameTooltip:SetText(e.name or "Unknown player", r, g, b)
			GameTooltip:AddLine(string.format("Attacked you %d time%s", e.attacks, e.attacks == 1 and "" or "s"), 1, 1, 1)
			GameTooltip:AddLine(string.format("Killed you %d time%s", e.kills, e.kills == 1 and "" or "s"), 1, 0.35, 0.3)
			if e.mine > 0 then GameTooltip:AddLine(string.format("You killed them %d time%s", e.mine, e.mine == 1 and "" or "s"), 0.4, 1, 0.4) end
			if not self.key then
				GameTooltip:AddLine("Last seen 5m ago in " .. e.zone, 0.7, 0.7, 0.7)
				GameTooltip:AddLine("A sample player. /wd demo hides them.", 0.5, 0.5, 0.5)
			else
				if e.last then
					GameTooltip:AddLine("Last seen " .. Ago(e.last) .. ((e.zone and e.zone ~= "") and (" in " .. e.zone) or ""), 0.7, 0.7, 0.7)
				end
				GameTooltip:AddLine("Shift + right-click to remove", 0.5, 0.5, 0.5)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function(self)
			self.hover:Hide()
			if GameTooltip then GameTooltip:Hide() end
		end)
		w.rows[i] = row
	end
	w:EnableMouseWheel(true)
	w:SetScript("OnMouseWheel", function(self, delta)
		self.offset = self.offset - delta
		self.Draw()
	end)

	function w.Draw()
		local list = SortedPlayers()
		local rows = math.max(1, math.min(MAX_ROWS, Opt("rows")))
		w.offset = math.max(0, math.min(w.offset, #list - rows))
		w.count:SetText(demo and "(sample)" or (#list > 0 and ("(" .. #list .. ")") or ""))
		w.empty:SetShown(#list == 0)
		local now, shown, anyNear = GetTime(), 0, false
		for i, row in ipairs(w.rows) do
			local item = i <= rows and list[i + w.offset] or nil
			if item then
				shown = shown + 1
				row.key, row.entry = item.key, item.e
				local near = item.e.near or (item.key ~= nil and nearAt[item.key] ~= nil and now - nearAt[item.key] <= NEAR_FOR)
				anyNear = anyNear or near
				FillRow(row, item.e, near)
				row:Show()
			else
				row.key, row.entry = nil, nil
				row:Hide()
			end
		end
		w.anyNear = anyNear
		w.top:SetColorTexture(anyNear and 1 or 0.55, anyNear and 0.25 or 0.12, anyNear and 0.2 or 0.1, 1)
		w.top:SetHeight(anyNear and 2 or 1)
		if #list > rows then
			local body = shown * ROW_H
			local h = math.max(8, body * rows / #list)
			w.mark:SetHeight(h)
			w.mark:ClearAllPoints()
			w.mark:SetPoint("TOPRIGHT", w, "TOPRIGHT", -1, -20 - (body - h) * w.offset / (#list - rows))
			w.mark:Show()
		else
			w.mark:Hide()
		end
		w:SetHeight(24 + math.max(1, shown) * ROW_H)
	end

	-- size, look and columns from the settings
	function w.Apply()
		local width = Opt("width")
		w:SetWidth(width)
		w:SetScale(Opt("scale"))
		Place(w)
		w.bg:SetColorTexture(0.04, 0.04, 0.05, Opt("alpha"))
		w.top:SetAlpha(math.min(1, Opt("alpha") * 2))
		for _, row in ipairs(w.rows) do LayoutRow(row, width - 8) end
		w.Draw()
	end
	w.Apply()
	w:Hide()
	return w
end

local function ShowWindow(show)
	window = window or BuildWindow()
	db.shown = show
	window:SetShown(show)
	if show then
		dirty = true
		DrawIfNeeded()
		frame:Show() -- (one look around; it goes back to sleep by itself)
	end
end

local function SetDemo(on)
	demo = on and true or false
	if demo then ShowWindow(true) end
	if window then
		window.offset = 0
		window.Draw()
	end
	if options then options.Refresh() end
end

---------------------------------------------------------------------------
-- The options window (/wd), in the same style as YaHT Forever's:
-- rounded plates, pill switches, a preview and a help panel on the right
---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\WarDrum\\media\\"
local ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local SLICE = Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched
local COLOR = {
	bg = {0.05, 0.05, 0.055, 1}, panel = {0.095, 0.09, 0.08, 1}, plate = {0.15, 0.14, 0.12, 1},
	field = {0.06, 0.058, 0.052, 1}, preview = {0.04, 0.036, 0.032, 1},
	line = {0.54, 0.46, 0.27, 1}, soft = {0.26, 0.23, 0.17, 1}, edge = {0.2, 0.175, 0.13, 1}, hover = {1, 1, 1, 0.05},
	lit = {0.20, 0.165, 0.10, 1},
	gold = {0.91, 0.70, 0.20, 1}, goldDim = {0.72, 0.57, 0.18, 1}, text = {0.92, 0.87, 0.75, 1}, muted = {0.66, 0.62, 0.50, 1},
	white = {1, 1, 1, 1},
}
-- every setting: what it is called, what it does, and how it is changed
local SETTINGS = {
	{section = "The list"},
	{key = "width", kind = "slider", name = "Width", min = 160, max = 300, step = 5,
		help = "How wide the list is. The name takes whatever room the other columns leave, so on a narrow list long names are cut short. Switching Show class off gives the name the most room."},
	{key = "scale", kind = "slider", name = "Size", min = 0.7, max = 1.5, step = 0.05, percent = true,
		help = "Makes the whole list bigger or smaller."},
	{key = "alpha", kind = "slider", name = "Background", min = 0, max = 1, step = 0.05, percent = true,
		help = "How solid the dark background is. At 0% only the text shows."},
	{key = "rows", kind = "slider", name = "Rows shown", min = 3, max = 20, step = 1,
		help = "How many players show at once. When there are more, scroll the list with the mouse wheel: a small gold bar on its right edge shows where you are."},
	{key = "showLevel", kind = "toggle", name = "Show level", help = "The player's level. ?? means they are too high for the game to tell you."},
	{key = "showClass", kind = "toggle", name = "Show class", help = "The class, written out. The name is in the class color either way."},
	{key = "lock", kind = "toggle", name = "Lock in place", help = "Stops the list from being dragged by accident."},
	{section = "Who gets listed"},
	{key = "onlyDamage", kind = "toggle", name = "Only players who damaged you",
		help = "An enemy targeting you in a fight shows at once. After the fight the game's damage meter is read: with this on, anyone who never damaged you is taken off again.\n\nPlayers of your own faction (duels) and players you attacked first are never listed."},
	{key = "skipBG", kind = "toggle", name = "Not in battlegrounds",
		help = "In a battleground or arena everyone attacks you. With this on, nobody is listed, counted or announced while you are in one."},
	{section = "When a listed player is near"},
	{key = "alert", kind = "toggle", name = "Warn me",
		help = "A chat line and the warning sound when a player on the list comes into view, at most once a minute each.\n\nThe game only shows the addon players whose nameplate is on screen, or who you target or point at, so keep enemy nameplates switched on."},
	{key = "sound", kind = "choice", name = "Warning sound", values = SOUND_ORDER, labels = SOUNDS, needs = "alert",
		help = "What plays when a listed player comes near. The arrows change it; click the name to hear it."},
	{kind = "buttons",
		{name = function() return demo and "Hide sample players" or "Show sample players" end,
			help = "Fills the list with made-up players, so you can place it and set it up before anyone has attacked you. Nothing is saved.",
			run = function() SetDemo(not demo) end},
		{name = "Empty the list", confirm = "Empty the list?",
			help = "Takes everyone off the list. Shift + right-click a row removes just that player.",
			run = function()
				db.players = {}
				indexStale = true
			end},
	},
}

local function Paint(t, c)
	if t.shaped then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) else t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end
-- a rounded shape from the addon's own artwork (square if the game can't nine-slice)
local function Shaped(parent, layer, file, c)
	local t = parent:CreateTexture(nil, layer)
	if SLICE and t.SetTextureSliceMargins and t.SetTextureSliceMode then
		t:SetTexture(MEDIA .. file)
		t:SetTextureSliceMargins(8, 8, 8, 8)
		t:SetTextureSliceMode(SLICE)
		t.shaped = true
	end
	Paint(t, c)
	return t
end
local function Plate(parent, c, layer)
	return Shaped(parent, layer or "BACKGROUND", "Round", c)
end
local function Rim(f, c)
	local t = Shaped(f, "BORDER", "RoundEdge", c)
	if t.shaped then t:SetAllPoints(f) else t:Hide() end
	return t
end
local function Dot(parent, c)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetTexture(MEDIA .. "Dot")
	t.shaped = true
	Paint(t, c)
	return t
end
local function Label(parent, template, c)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	fs:SetTextColor(c[1], c[2], c[3])
	fs:SetJustifyH("LEFT")
	return fs
end

local function SetOpt(key, value)
	db.settings[key] = value
	if window then window.Apply() end
	if options then options.Refresh() end
end

local function FormatValue(def, v)
	if def.percent then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
	return tostring(math.floor(v + 0.5))
end

local function Version()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	return Plain(Ask(get, "WarDrum", "Version")) or ""
end

local function BuildOptions()
	local W, PAD, LEFT_W, ROW, PLATE, HEAD, GAP = 620, 10, 356, 32, 28, 44, 10
	local RIGHT_W = W - LEFT_W - 3 * PAD
	local o = CreateFrame("Frame", "WarDrumOptionsFrame", UIParent)
	o:SetSize(W, 560) -- (the height is set from what is in it, further down)
	o:SetFrameStrata("HIGH")
	o:SetToplevel(true)
	o:SetClampedToScreen(true)
	o:SetMovable(true)
	o:EnableMouse(true)
	o:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
	Plate(o, COLOR.bg):SetAllPoints(o)
	Rim(o, COLOR.line)
	if UISpecialFrames then table.insert(UISpecialFrames, "WarDrumOptionsFrame") end

	-- header: drag it to move the window
	local head = CreateFrame("Frame", nil, o)
	head:SetPoint("TOPLEFT")
	head:SetPoint("TOPRIGHT")
	head:SetHeight(HEAD)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() o:StartMoving() end)
	head:SetScript("OnDragStop", function() o:StopMovingOrSizing() end)
	local icon = head:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetSize(24, 24)
	icon:SetPoint("LEFT", 14, 0)
	local title = Label(head, "GameFontNormalLarge", COLOR.white)
	title:SetPoint("LEFT", icon, "RIGHT", 9, 0)
	title:SetText(ADDON)
	local version = Label(head, "GameFontHighlightSmall", COLOR.muted)
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
	version:SetText(Version())
	local close = CreateFrame("Button", nil, head)
	close:SetSize(24, 24)
	close:SetPoint("RIGHT", -12, 0)
	close.text = Label(close, "GameFontNormalLarge", COLOR.muted)
	close.text:SetPoint("CENTER")
	close.text:SetText("x")
	close:SetScript("OnClick", function() o:Hide() end)
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(COLOR.muted[1], COLOR.muted[2], COLOR.muted[3]) end)

	-- right: a preview of the list, and under it what the setting under the mouse does
	local help = CreateFrame("Frame", nil, o)
	help:SetPoint("TOPRIGHT", -PAD, -HEAD)
	help:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	help:SetWidth(RIGHT_W)
	Plate(help, COLOR.panel):SetAllPoints(help)
	Rim(help, COLOR.edge)
	local box = CreateFrame("Frame", nil, help)
	box:SetPoint("TOPLEFT", 10, -10)
	box:SetPoint("TOPRIGHT", -10, -10)
	box:SetHeight(78)
	Plate(box, COLOR.preview):SetAllPoints(box)
	Rim(box, COLOR.soft)
	if box.SetClipsChildren then box:SetClipsChildren(true) end
	local caption = Label(box, "GameFontHighlightSmall", COLOR.goldDim)
	caption:SetPoint("TOPLEFT", 10, -7)
	caption:SetText("Preview")
	o.preview = {}
	for i = 1, 3 do
		local row = NewRow(box)
		row:SetPoint("TOPLEFT", 8, -22 - (i - 1) * ROW_H)
		row.sample = SAMPLE[i]
		o.preview[i] = row
	end
	o.helpTitle = Label(help, "GameFontNormal", COLOR.gold)
	o.helpTitle:SetPoint("TOPLEFT", 14, -102)
	o.helpTitle:SetWidth(RIGHT_W - 28)
	local rule = Solid(help, "ARTWORK", COLOR.soft[1], COLOR.soft[2], COLOR.soft[3], 1)
	rule:SetPoint("TOPLEFT", o.helpTitle, "BOTTOMLEFT", 0, -8)
	rule:SetSize(RIGHT_W - 28, 1)
	o.helpText = Label(help, "GameFontHighlight", COLOR.text)
	o.helpText:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -10)
	o.helpText:SetWidth(RIGHT_W - 28)
	o.helpText:SetJustifyV("TOP")
	o.helpText:SetWordWrap(true)
	if o.helpText.SetSpacing then o.helpText:SetSpacing(4) end
	local foot = Label(help, "GameFontHighlightSmall", COLOR.muted)
	foot:SetPoint("BOTTOMLEFT", 14, 12)
	foot:SetWidth(RIGHT_W - 28)
	foot:SetText("/wd opens this window.\n/wd help lists the other commands.")
	if foot.SetSpacing then foot:SetSpacing(3) end
	local RESTING = "Point at a setting to see what it does. The list itself changes as you go.\n\n"
		.. "|cffe8b233How the list is made|r\n"
		.. "An enemy player who has you targeted in a fight shows at once.\n\n"
		.. "After the fight the game's own damage meter settles it: whoever damaged you stays, seen or not.\n\n"
		.. "Die, and everyone who damaged you in that fight gets the kill."
	local function Help(def)
		o.helpTitle:SetText(def and (type(def.name) == "function" and def.name() or def.name) or ADDON)
		o.helpText:SetText(def and def.help or RESTING)
	end
	Help(nil)

	-- left: the settings, on plates inside a box per section
	local panel = CreateFrame("Frame", nil, o)
	panel:SetPoint("TOPLEFT", PAD, -HEAD)
	panel:SetSize(LEFT_W, 400)
	o.controls, o.buttons = {}, {}
	local y, boxTop, boxTex = 0, nil, nil
	local function closeBox()
		if boxTex then
			boxTex:SetSize(LEFT_W, boxTop - y + 4)
			y = y - 4
		end
		boxTex = nil
	end
	for _, def in ipairs(SETTINGS) do
		if def.section then
			closeBox()
			if y < 0 then y = y - GAP end
			boxTex = Plate(panel, COLOR.panel)
			boxTex:SetPoint("TOPLEFT", 0, y)
			boxTop = y
			local head2 = Label(panel, "GameFontNormal", COLOR.gold)
			head2:SetPoint("TOPLEFT", 12, y - 9)
			head2:SetText(def.section)
			y = y - 30
		elseif def.kind == "buttons" then
			closeBox()
			y = y - GAP
			for i, item in ipairs(def) do
				local b = CreateFrame("Button", nil, panel)
				b:SetSize(168, 26)
				b:SetPoint("TOPLEFT", (i - 1) * 178, y)
				b.bg = Plate(b, COLOR.plate)
				b.bg:SetAllPoints(b)
				Rim(b, COLOR.line)
				b.text = Label(b, "GameFontHighlightSmall", COLOR.white)
				b.text:SetPoint("CENTER")
				b.item = item
				local function run()
					item.run()
					if window then window.Apply() end
					o.Refresh()
				end
				b:SetScript("OnClick", function()
					if item.confirm and StaticPopupDialogs and StaticPopup_Show then
						StaticPopupDialogs["WARDRUM_CONFIRM"] = StaticPopupDialogs["WARDRUM_CONFIRM"] or {
							text = "%s", button1 = YES or "Yes", button2 = NO or "No", timeout = 0, whileDead = true,
							hideOnEscape = true, preferredIndex = 3, OnAccept = function(_, data) if data then data() end end,
						}
						StaticPopup_Show("WARDRUM_CONFIRM", item.confirm, nil, run)
					else
						run()
					end
				end)
				b:SetScript("OnEnter", function(self)
					Paint(self.bg, COLOR.lit)
					Help(item)
				end)
				b:SetScript("OnLeave", function(self)
					Paint(self.bg, COLOR.plate)
					Help(nil)
				end)
				o.buttons[i] = b
			end
			y = y - 26
		else
			local row = CreateFrame("Frame", nil, panel)
			row:SetPoint("TOPLEFT", 8, y)
			row:SetSize(LEFT_W - 16, PLATE)
			row.def = def
			Plate(row, COLOR.plate):SetAllPoints(row)
			row.hover = Plate(row, COLOR.hover, "BORDER")
			row.hover:SetAllPoints(row)
			row.hover:Hide()
			row.label = Label(row, "GameFontHighlight", COLOR.text)
			row.label:SetPoint("LEFT", 12, 0)
			row.label:SetText(def.name)
			local function enter()
				row.hover:Show()
				Help(def)
			end
			local function leave()
				row.hover:Hide()
				Help(nil)
			end
			row:EnableMouse(true)
			row:SetScript("OnEnter", enter)
			row:SetScript("OnLeave", leave)
			if def.kind == "toggle" then
				local b = CreateFrame("Button", nil, row)
				b:SetSize(36, 18)
				b:SetPoint("RIGHT", -12, 0)
				b.bg = Plate(b, COLOR.soft)
				b.bg:SetAllPoints(b)
				b.knob = Dot(b, COLOR.muted)
				b.knob:SetSize(14, 14)
				b:SetScript("OnClick", function() SetOpt(def.key, not Opt(def.key)) end)
				b:SetScript("OnEnter", enter)
				b:SetScript("OnLeave", leave)
				row:SetScript("OnMouseUp", function(_, button)
					if button == nil or button == "LeftButton" then SetOpt(def.key, not Opt(def.key)) end
				end)
				row.widget = b
			elseif def.kind == "slider" then
				local function snap(v)
					v = math.floor(math.floor(v / def.step + 0.5) * def.step * 100 + 0.5) / 100
					return math.max(def.min, math.min(def.max, v))
				end
				local function arrow(dir, dy)
					local a = CreateFrame("Button", nil, row)
					a:SetSize(16, 12)
					a:SetPoint("RIGHT", -12, dy)
					a.tex = a:CreateTexture(nil, "ARTWORK")
					a.tex:SetTexture(MEDIA .. "Arrow")
					a.tex:SetSize(10, 5)
					a.tex:SetPoint("CENTER")
					if dir < 0 then a.tex:SetTexCoord(0, 1, 1, 0) end
					a.tex:SetVertexColor(COLOR.muted[1], COLOR.muted[2], COLOR.muted[3])
					a:SetScript("OnClick", function() SetOpt(def.key, snap(Opt(def.key) + dir * def.step)) end)
					a:SetScript("OnEnter", function(self)
						self.tex:SetVertexColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
						enter()
					end)
					a:SetScript("OnLeave", function(self)
						self.tex:SetVertexColor(COLOR.muted[1], COLOR.muted[2], COLOR.muted[3])
						leave()
					end)
					return a
				end
				row.up, row.down = arrow(1, 6), arrow(-1, -6)
				row.value = Label(row, "GameFontHighlightSmall", COLOR.white)
				row.value:SetPoint("RIGHT", -32, 0)
				row.value:SetWidth(40)
				row.value:SetJustifyH("RIGHT")
				local sl = CreateFrame("Slider", nil, row)
				sl:SetOrientation("HORIZONTAL")
				sl:SetSize(130, 14)
				sl:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
				sl.track = Solid(sl, "BACKGROUND", COLOR.soft[1], COLOR.soft[2], COLOR.soft[3], 1)
				sl.track:SetPoint("LEFT")
				sl.track:SetPoint("RIGHT")
				sl.track:SetHeight(4)
				sl.fill = Solid(sl, "BORDER", COLOR.goldDim[1], COLOR.goldDim[2], COLOR.goldDim[3], 1)
				sl.fill:SetPoint("LEFT")
				sl.fill:SetHeight(4)
				sl:SetThumbTexture(MEDIA .. "Dot")
				local thumb = sl:GetThumbTexture()
				if thumb then
					thumb:SetSize(14, 14)
					thumb:SetVertexColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
				end
				sl:SetMinMaxValues(def.min, def.max)
				sl:SetValueStep(def.step)
				if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
				sl:EnableMouse(true)
				sl:SetScript("OnValueChanged", function(self, v)
					if self.silent then return end
					v = snap(v)
					if v ~= Opt(def.key) then SetOpt(def.key, v) end
				end)
				sl:SetScript("OnEnter", enter)
				sl:SetScript("OnLeave", leave)
				row.widget = sl
			elseif def.kind == "choice" then
				local function step(dir)
					local at = 1
					for i, value in ipairs(def.values) do if value == Opt(def.key) then at = i end end
					SetOpt(def.key, def.values[(at - 1 + dir) % #def.values + 1])
					PlayWarning()
				end
				local function arrow(dir, x)
					local a = CreateFrame("Button", nil, row)
					a:SetSize(18, 22)
					a:SetPoint("RIGHT", x, 0)
					a.tex = a:CreateTexture(nil, "ARTWORK")
					a.tex:SetTexture(MEDIA .. "Arrow")
					a.tex:SetSize(10, 5)
					a.tex:SetPoint("CENTER")
					if a.tex.SetRotation then a.tex:SetRotation(dir < 0 and math.pi / 2 or -math.pi / 2) end
					a.tex:SetVertexColor(COLOR.muted[1], COLOR.muted[2], COLOR.muted[3])
					a:SetScript("OnClick", function() step(dir) end)
					a:SetScript("OnEnter", function(self)
						self.tex:SetVertexColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
						enter()
					end)
					a:SetScript("OnLeave", function(self)
						self.tex:SetVertexColor(COLOR.muted[1], COLOR.muted[2], COLOR.muted[3])
						leave()
					end)
					return a
				end
				row.next = arrow(1, -11)
				local b = CreateFrame("Button", nil, row)
				b:SetSize(104, 22)
				b:SetPoint("RIGHT", row.next, "LEFT", -2, 0)
				Plate(b, COLOR.field):SetAllPoints(b)
				Rim(b, COLOR.soft)
				b.text = Label(b, "GameFontHighlightSmall", COLOR.white)
				b.text:SetPoint("CENTER")
				b:SetScript("OnClick", function() PlayWarning() end)
				b:SetScript("OnEnter", enter)
				b:SetScript("OnLeave", leave)
				row.prev = arrow(-1, -11 - 18 - 2 - 104 - 2)
				row.widget = b
			end
			o.controls[def.key] = row
			y = y - ROW
		end
	end
	closeBox()
	o:SetHeight(HEAD - y + PAD)

	-- shows every control's current value, and the preview at the current width and columns
	function o.Refresh()
		for key, row in pairs(o.controls) do
			local def, v = row.def, Opt(key)
			if def.kind == "toggle" then
				local b = row.widget
				Paint(b.bg, v and COLOR.goldDim or COLOR.soft)
				Paint(b.knob, v and COLOR.white or COLOR.muted)
				b.knob:ClearAllPoints()
				if v then b.knob:SetPoint("RIGHT", -2, 0) else b.knob:SetPoint("LEFT", 2, 0) end
			elseif def.kind == "slider" then
				local sl = row.widget
				sl.silent = true
				sl:SetValue(v)
				sl.silent = false
				sl.fill:SetWidth(math.max(1, math.min(130, 130 * (v - def.min) / (def.max - def.min))))
				row.value:SetText(FormatValue(def, v))
			elseif def.kind == "choice" then
				row.widget.text:SetText(def.labels[v] and def.labels[v].name or tostring(v))
			end
			if def.needs then row:SetAlpha(Opt(def.needs) and 1 or 0.4) end -- (no use without the setting it belongs to)
		end
		for _, b in ipairs(o.buttons) do
			b.text:SetText(type(b.item.name) == "function" and b.item.name() or b.item.name)
		end
		local width = math.min(Opt("width") - 8, RIGHT_W - 20 - 16)
		for _, row in ipairs(o.preview) do
			row:SetWidth(width)
			LayoutRow(row, width)
			FillRow(row, row.sample, row.sample.near)
		end
	end
	o.Refresh()
	o:Hide()
	return o
end

OpenOptions = function()
	options = options or BuildOptions()
	if options:IsShown() then
		options:Hide()
	else
		ShowWindow(true) -- (the settings change the list: have it on screen)
		options.Refresh()
		options:Show()
	end
end

-- the game's addon button by the minimap, where it has one: click for the list, right-click for the settings
function WarDrum_OnAddonCompartmentClick(_, button)
	if not db then return end
	if button == "RightButton" then
		OpenOptions()
	else
		ShowWindow(not (window and window:IsShown()))
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local elapsedSum = 0
frame:SetScript("OnUpdate", function(_, elapsed)
	elapsedSum = elapsedSum + elapsed
	if elapsedSum < SCAN_EVERY then return end
	elapsedSum = 0
	local ok, err = pcall(Scan)
	if not ok then Log("problem in the scan: " .. tostring(err)) end
end)

-- What an earlier version saved, brought up to date
local function Upgrade()
	local moved
	for key, e in pairs(db.players) do
		e.attacks, e.kills, e.mine = e.attacks or 0, e.kills or 0, e.mine or 0
		e.near = nil -- (kept per session now)
		if e.realm then -- (the first version kept the two parts of a name apart)
			e.name = FullName(e.name, e.realm) or e.name
			e.realm = nil
		end
		if type(key) == "string" and key:sub(1, 5) == "name:" and e.name and key ~= NameKey(e.name) then
			moved = moved or {}
			moved[key] = NameKey(e.name)
		end
	end
	for old, new in pairs(moved or {}) do
		if db.players[new] == nil then db.players[new] = db.players[old] end
		db.players[old] = nil
	end
	-- The first version listed anyone seen targeting you in a fight, which included players you
	-- had attacked: only those who killed you stay
	if (db.version or (next(db.players) and 1 or 2)) < 2 then
		for key, e in pairs(db.players) do
			if e.kills == 0 and not e.confirmed then db.players[key] = nil end
		end
	end
	db.version = 2
	db.backfilled = nil
end

local function OnEvent(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= "WarDrum" then return end
		WarDrumDB = WarDrumDB or {}
		db = WarDrumDB
		db.players = db.players or {}
		db.log = db.log or {}
		db.settings = db.settings or {}
		if db.shown == nil then db.shown = true end
		Upgrade()
		indexStale = true
	elseif event == "PLAYER_LOGIN" then
		Log("=== War Drum " .. Version() .. " loaded ===")
		LogInventory()
		inCombat = Plain(Ask(InCombatLockdown)) and true or false
		if not inCombat then
			-- (the fight the meter still shows is over and done with: it must not be counted again)
			local _, _, signature = MeterAttackers("Current")
			if signature then db.lastSession = signature end
		end
		Tidy()
		if db.shown then ShowWindow(true) end
	elseif event == "PLAYER_REGEN_DISABLED" then
		inCombat, fightStartedAt = true, GetTime()
		pending, counted, started, startedName, death = {}, {}, {}, {}, nil
		Log("fight started in " .. Zone())
		-- Your target is an enemy player who is neither fighting nor targeting you: you struck first
		local info = ReadUnit("target")
		if info and info.fighting == false and info.onMe == false and not info.dead then
			local key = KeyOf(info)
			if key then started[key] = true end
			if info.name then startedName[info.name] = true end
			Log("you struck first: " .. UnitLine(info))
		end
		Scan()
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat, fightEndedAt = false, GetTime()
		Log("fight ended")
		for _, e in pairs(db.players) do FillFromGUID(e) end -- (names and classes the game hid during the fight)
		Tidy()
		Settle()
		Redraw()
		Scan()
	elseif event == "PLAYER_DEAD" then
		Died()
	elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		-- back on your feet: what the game hid during the fight may be readable now
		if deadHandled > 0 and GetTime() - deadHandled < 600 then
			for _, e in pairs(db.players) do FillFromGUID(e) end
			Tidy()
			Redraw()
			DrawIfNeeded()
		end
	elseif event == "CHAT_MSG_SYSTEM" then
		-- (the game's "you died" line links to its death recap)
		local text = Plain(arg1)
		local id = type(text) == "string" and tonumber(text:match("|Hdeath:(%d+)"))
		if id then LogRecapById(id, "the chat link") end
	elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
		-- Honor for a kill names nobody: it was the listed player you had targeted, unless they are still standing
		Scan()
		local e = lastTargetKey and db.players[lastTargetKey]
		local was = lastTargetKey and seen[lastTargetKey]
		local alive = was and GetTime() - was.at < 1.5 and was.info.dead == false
		if e and not alive and e.lastAttack and time() - e.lastAttack < 60 and (not e.lastMine or time() - e.lastMine > 60) then
			e.mine = e.mine + 1
			e.lastMine = time()
			Log("YOUR KILL (honor gained): " .. tostring(e.name))
			Redraw()
			DrawIfNeeded()
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		local unit = Plain(arg1)
		if unit then
			plates[unit] = true
			if Look(unit, GetTime(), Paused()) then frame:Show() end
		end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local unit = Plain(arg1)
		if unit then plates[unit] = nil end
	else -- your target, your focus or what your mouse is over changed
		local unit = (event == "PLAYER_TARGET_CHANGED" and "target") or (event == "PLAYER_FOCUS_CHANGED" and "focus") or "mouseover"
		if Look(unit, GetTime(), Paused()) then frame:Show() end
	end
end

frame:SetScript("OnEvent", function(self, event, ...)
	local ok, err = pcall(OnEvent, self, event, ...)
	if not ok and db then Log("problem in " .. tostring(event) .. ": " .. tostring(err)) end
end)
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_FOCUS_CHANGED",
	"CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_SYSTEM"}) do
	pcall(frame.RegisterEvent, frame, event)
end

---------------------------------------------------------------------------
-- /wd
---------------------------------------------------------------------------
local function Slash(msg)
	if not db then return end
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" or cmd == "options" or cmd == "config" or cmd == "settings" then
		OpenOptions()
	elseif cmd == "show" or cmd == "hide" then
		ShowWindow(cmd == "show")
	elseif cmd == "clear" then
		db.players = {}
		indexStale = true
		Say("list emptied.")
		Redraw()
		DrawIfNeeded()
	elseif cmd == "remove" and rest ~= "" then
		local gone = {}
		for key, e in pairs(db.players) do
			if e.name and e.name:lower() == rest:lower() then gone[#gone + 1] = key end
		end
		for _, key in ipairs(gone) do Remove(key) end
		Say(#gone > 0 and ("removed " .. rest .. ".") or ("nobody called " .. rest .. " on the list."))
		DrawIfNeeded()
	elseif cmd == "demo" or cmd == "sample" or cmd == "test" then
		SetDemo(not demo)
		Say(demo and "showing sample players. /wd demo hides them again." or "sample players hidden.")
	elseif cmd == "dump" then
		LogInventory()
		LogDamageMeter("on request", true)
		Say("written to the record. /reload saves it.")
	elseif cmd == "reset" then
		db.pos = nil
		if window then Place(window) end
		Say("window moved back.")
	else
		Say("/wd - open the settings (or click the three bars on the list)")
		Say("/wd show, /wd hide - show or hide the list")
		Say("/wd demo - show sample players, to place the list and set it up")
		Say("/wd remove Name - take one player off (or Shift + right-click their row)")
		Say("/wd clear - empty the list")
		Say("/wd reset - move the list back to where it started")
	end
end

SLASH_WARDRUM1 = "/wd"
SLASH_WARDRUM2 = "/wardrum"
SlashCmdList["WARDRUM"] = function(msg)
	local ok, err = pcall(Slash, msg)
	if not ok then
		Log("problem in /wd " .. tostring(msg) .. ": " .. tostring(err))
		Say("that didn't work: " .. tostring(err))
	end
end
