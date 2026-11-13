-- Replaces the test stand-in's frames with ones that remember everything needed to draw them:
-- parents, anchors, sizes, textures, colors and texts. Loaded after tests/fakegame.lua.
Enum.UITextureSliceMode = {Stretched = 1}
regions = {}
local MT
local function new(kind, parent)
	local o = {id = #regions + 1, kind = kind, parent = parent, shown = true, scripts = {}, events = {}, points = {}, children = {}, alpha = 1}
	regions[o.id] = o
	if parent then parent.children[#parent.children + 1] = o end
	return setmetatable(o, MT)
end
local M = {
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
	SetTextColor = function(s, r, g, b, a) s.color = {r, g, b, a or 1} end,
	SetVertexColor = function(s, r, g, b, a) s.vertex = {r, g, b, a or 1} end,
	SetColorTexture = function(s, r, g, b, a) s.rgba = {r, g, b, a or 1} end,
	SetTexture = function(s, t) s.texture = t end,
	SetTexCoord = function(s, a, b, c, d) s.texcoord = {a, b, c, d} end,
	SetRotation = function(s, r) s.rotation = r end,
	SetTextureSliceMargins = function(s) s.slice = true end,
	SetTextureSliceMode = function() end,
	SetWidth = function(s, v) s.width = v end,
	SetHeight = function(s, v) s.h = v end,
	SetSize = function(s, a, b) s.width, s.h = a, b end,
	GetWidth = function(s) return s.width or 0 end,
	GetHeight = function(s) return s.h or 0 end,
	SetScale = function(s, v) s.scale = v end,
	GetScale = function(s) return s.scale or 1 end,
	SetAlpha = function(s, v) s.alpha = v end,
	SetJustifyH = function(s, v) s.justifyH = v end,
	SetJustifyV = function(s, v) s.justifyV = v end,
	SetWordWrap = function(s, v) s.wrap = v end,
	SetSpacing = function(s, v) s.spacing = v end,
	SetValue = function(s, v) s.value = v end,
	GetValue = function(s) return s.value end,
	SetMinMaxValues = function(s, a, b) s.min, s.max = a, b end,
	SetClipsChildren = function(s, v) s.clips = v end,
	SetPoint = function(s, point, a, b, c, d)
		local rel, relPoint, x, y
		if type(a) == "number" then x, y = a, b else rel, relPoint, x, y = a, b, c, d end
		s.points[#s.points + 1] = {point = point, rel = (rel and rel.id) or (s.parent and s.parent.id) or 1, relPoint = relPoint or point, x = x or 0, y = y or 0}
	end,
	ClearAllPoints = function(s) s.points = {} end,
	SetAllPoints = function(s, rel)
		local id = (rel and rel.id) or (s.parent and s.parent.id) or 1
		s.points = {{point = "TOPLEFT", rel = id, relPoint = "TOPLEFT", x = 0, y = 0}, {point = "BOTTOMRIGHT", rel = id, relPoint = "BOTTOMRIGHT", x = 0, y = 0}}
	end,
	GetPoint = function(s) local p = s.points[1] return p.point, nil, p.relPoint, p.x, p.y end,
	CreateTexture = function(s, _, layer) local t = new("Texture", s) t.layer = layer or "ARTWORK" return t end,
	CreateFontString = function(s, _, layer, template) local t = new("FontString", s) t.font = template or "GameFontNormal" return t end,
	SetThumbTexture = function(s, path) local t = new("Texture", s) t.layer = "OVERLAY" t.texture = path t.isThumb = true s.thumb = t end,
	GetThumbTexture = function(s) return s.thumb end,
	SetOwner = function(s, owner) s.owner = owner.id s.lines = {} end,
	AddLine = function(s, t, r, g, b) s.lines[#s.lines + 1] = {t, r or 1, g or 0.82, b or 0} end,
}
MT = {__index = function(_, k)
	if M[k] then return M[k] end
	if type(k) == "string" and k:match("^%u") then return function() end end
	return nil
end}
UIParent = new("Frame", nil)
UIParent.width, UIParent.h = 1366, 768
frames = {}
function CreateFrame(kind, name, parent)
	local f = new(kind, parent or UIParent)
	if name then _G[name] = f end
	frames[#frames + 1] = f
	return f
end
GameTooltip = new("GameTooltip", UIParent)
GameTooltip.shown = false
GameTooltip.SetText = function(s, t, r, g, b) s.lines = {{t, r or 1, g or 1, b or 1}} end

-- everything, as JSON, for the drawing side
local function esc(s) return '"' .. tostring(s):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
local function json(v)
	local t = type(v)
	if t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for i, x in ipairs(v) do parts[i] = json(x) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, x in pairs(v) do parts[#parts + 1] = esc(k) .. ":" .. json(x) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return esc(v)
	elseif t == "number" or t == "boolean" then
		return tostring(v)
	end
	return "null"
end
function export()
	local out = {}
	for i, r in ipairs(regions) do
		local kids = {}
		for j, c in ipairs(r.children) do kids[j] = c.id end
		out[i] = {id = r.id, kind = r.kind, parent = r.parent and r.parent.id or 0, shown = r.shown, points = r.points, width = r.width, height = r.h,
			text = r.txt, font = r.font, color = r.color, vertex = r.vertex, rgba = r.rgba, texture = r.texture, texcoord = r.texcoord,
			rotation = r.rotation, slice = r.slice, layer = r.layer, alpha = r.alpha, justifyH = r.justifyH, wrap = r.wrap, spacing = r.spacing,
			value = type(r.value) == "number" and r.value or nil, min = type(r.min) == "number" and r.min or nil, max = type(r.max) == "number" and r.max or nil, thumb = r.thumb and r.thumb.id, isThumb = r.isThumb, children = kids,
			owner = r.owner, lines = r.lines, name = (r == WarDrumFrame and "list") or (r == WarDrumOptionsFrame and "options") or (r == GameTooltip and "tooltip") or nil}
	end
	return json(out)
end
