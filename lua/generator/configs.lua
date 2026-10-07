_G.CSR_Config = _G.CSR_Config or {}
local C = _G.CSR_Config

dofile(ModPath .. "lua/util.lua")
local U = _G.ScrollingTexturesUtil

C.SCROLL_SPEED = 0.1
C.GLOW_MULTIPLIER = "5"
C.GLOW_BLOOM = "1.0"
C.RENDER_TEMPLATE = "generic:DEPTH_SCALING:DIFFUSE_TEXTURE:DIFFUSE_UVANIM:SELF_ILLUMINATION:SELF_ILLUMINATION_BLOOM:SELF_ILLUMINATION_UVANIM"
C.DIRECTIONS = {
	e = { 1, 0 }, w = { -1, 0 }, n = { 0, 1 }, s = { 0, -1 },
	ne = { 0.7, 0.7 }, nw = { -0.7, 0.7 }, se = { 0.7, -0.7 }, sw = { -0.7, -0.7 },
}
C.ids_of = C.ids_of or {}

local function number(v)
	local r = math.floor(math.abs(v) * 1e6 + 0.5) / 1e6
	if v < 0 and r ~= 0 then r = -r end
	return ("%.6g"):format(r)
end

local function el(tag, attrs, children)
	return { tag = tag, attrs = attrs or {}, children = children or {} }
end

local function render(e, depth, out)
	local pad = string.rep("\t", depth)
	local parts = { pad, "<", e.tag }
	for _, a in ipairs(e.attrs) do
		parts[#parts + 1] = (' %s="%s"'):format(a[1], a[2])
	end
	if #e.children == 0 then
		parts[#parts + 1] = " />"
		out[#out + 1] = table.concat(parts)
	else
		parts[#parts + 1] = ">"
		out[#out + 1] = table.concat(parts)
		for _, c in ipairs(e.children) do render(c, depth + 1, out) end
		out[#out + 1] = pad .. "</" .. e.tag .. ">"
	end
end

local function parse_elements(text)
	local list = {}
	for _, m in ipairs(U.materials(text)) do
		local id, kept = nil, {}
		for _, kv in ipairs(m.attrs) do
			if kv[1] == "id" then id = kv[2] else kept[#kept + 1] = kv end
		end
		list[#list + 1] = { id = id, attrs = kept, children = m.children, name = U.attr(m.attrs, "name") }
	end
	return list
end

local function ensure_unique(attrs)
	local out, has = {}, false
	for _, kv in ipairs(attrs or {}) do
		if kv[1] == "unique" then has = true end
		out[#out + 1] = { kv[1], kv[2] }
	end
	if not has then out[#out + 1] = { "unique", "true" } end
	return out
end

local function animated_material(name, dir, skin)
	local d = C.DIRECTIONS[dir]
	return el("material", {
		{ "name", name }, { "render_template", C.RENDER_TEMPLATE },
		{ "version", "2" }, { "unique", "true" },
	}, {
		el("diffuse_texture", { { "file", skin.df } }),
		el("self_illumination_texture", { { "file", skin.il } }),
		el("variable", { { "name", "uv_speed" }, { "value", number(d[1] * C.SCROLL_SPEED) .. " " .. number(d[2] * C.SCROLL_SPEED) .. " 0" }, { "type", "vector3" } }),
		el("variable", { { "name", "il_bloom" }, { "value", C.GLOW_BLOOM }, { "type", "float" } }),
		el("variable", { { "name", "il_multiplier" }, { "value", C.GLOW_MULTIPLIER }, { "type", "scalar" } }),
	})
end

local function config_path(part)
	local mc = part.material_config
	if mc == nil then return part.unit end
	if type(mc) == "string" then return mc end
	local key = tostring(mc):match("(@ID%x+@)") or tostring(mc)
	C.ids_of[key] = mc
	return key
end

local OPTIC_EXCLUDE = {
	optical = true, screen = true,
	mtr_mullplan = true, mullplan = true, mtr_mullplane = true,
}

local DIR_KEYS = { "e", "ne", "n", "nw", "w", "sw", "s", "se" }

function C.auto_direction(name)
	local h = 0
	for i = 1, #name do h = (h * 31 + name:byte(i)) % 2147483647 end
	return DIR_KEYS[h % #DIR_KEYS + 1]
end

local function animatable(vel)
	local name = vel.name
	if not name or OPTIC_EXCLUDE[name] then return false end
	for _, kv in ipairs(vel.attrs) do
		if kv[1] == "render_template" then
			return kv[2]:sub(1, 8) == "generic:"
		end
	end
	return false
end

function C.game_part_units()
	local factory = tweak_data and tweak_data.weapon and tweak_data.weapon.factory
	if not (factory and factory.parts) then return nil end
	local seen, list = {}, {}
	for _, part in pairs(factory.parts) do
		local path = config_path(part)
		if path and not seen[path] then
			seen[path] = true
			list[#list + 1] = path
		end
	end
	table.sort(list)
	return list
end

function C.read_vanilla_config(path)
	local t = Idstring("material_config")
	local n = C.ids_of[path] or Idstring(path)
	if not DB:has(t, n) then return nil end
	local f = DB:open(t, n)
	if not f then return nil end
	local data = f:read()
	f:close()
	if type(data) ~= "string" or data:sub(1, 1) ~= "<" then return nil end
	local elements = parse_elements(data)
	if #elements == 0 then return nil end
	return { group = data:match("<materials[^>]-group%s*=%s*\"([^\"]*)\""), elements = elements }
end

function C.load_parts()
	local units = C.game_part_units()
	if not units then return {} end
	local out = {}
	for _, unit in ipairs(units) do
		local info = C.read_vanilla_config(unit)
		if info then
			out[#out + 1] = {
				name = unit:match("^@ID(%x+)@$") and ("alias_" .. unit:match("^@ID(%x+)@$")) or unit:match("[^/]+$"),
				vanilla = unit,
				group = info.group or "-",
				elements = info.elements,
			}
		end
	end
	return out
end

local function resolve(p)
	local out = {}
	if not p.elements then return out end
	for _, vel in ipairs(p.elements) do
		if animatable(vel) then
			out[#out + 1] = { name = vel.name, anim = C.auto_direction(vel.name) }
		else
			out[#out + 1] = { name = vel.name, vanilla = vel }
		end
	end
	return out
end

function C.build(dir, skin)
	local parts = C.load_parts()
	table.sort(parts, function(a, b) return a.vanilla < b.vanilla end)

	local by_content, configs, mapping = {}, {}, {}
	for _, p in ipairs(parts) do
		local attrs = { { "version", "3" } }
		if p.group and p.group ~= "-" then attrs[#attrs + 1] = { "group", p.group } end
		local mats = resolve(p)

		local children = {}
		for _, m in ipairs(mats) do
			if m.anim then
				children[#children + 1] = animated_material(m.name, m.anim, skin)
			else
				local cs = {}
				for _, c in ipairs(m.vanilla.children) do cs[#cs + 1] = el(c.tag, c.attrs) end
				children[#children + 1] = el("material", ensure_unique(m.vanilla.attrs), cs)
			end
		end

		local lines = {}
		render(el("materials", attrs, children), 0, lines)
		local content = table.concat(lines, "\n") .. "\n"
		local config = by_content[content]
		if not config then
			config = p.name
			local k = 1
			while configs[config] do k = k + 1; config = p.name .. "_" .. k end
			by_content[content] = config
			configs[config] = content
		end
		mapping[#mapping + 1] = {
			p.vanilla, config,
			ids = C.ids_of[p.vanilla] or (Idstring and Idstring(p.vanilla)),
		}
	end

	return { configs = configs, mapping = mapping }
end

function C.mapping_json(res, prefix)
	local map = {}
	for _, m in ipairs(res.mapping) do map[m[1]] = prefix .. m[2] end
	return json.encode(map)
end
