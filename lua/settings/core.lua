_G.ScrollingTexturesSettings = _G.ScrollingTexturesSettings or {}
local T = _G.ScrollingTexturesSettings

if T._core_loaded then
	return
end
T._core_loaded = true

dofile(ModPath .. "lua/util.lua")
dofile(ModPath .. "lua/loader.lua")
local U = _G.ScrollingTexturesUtil

T._path = ModPath
T._save = SavePath .. "scrolling_textures_settings.json"

T.defaults = {
	enabled = true,
	scroll = true,
	breath = true,
	breath_rate = 10,
	breath_depth = 0.35,
	breath_offset = -0.20,
	glow = 1.25,
	bloom = 0.75,
	speed = 0.07,
	menus = true,

	primary_skin = 1,
	secondary_skin = 1,

	react_shot_flash = true,
	react_shot_flash_boost = 5.0,
	react_shot_flash_decay = 50,

	light = true,
	light_intensity = 0.4,
	light_range = 350,

}

T.settings = {}
for k, v in pairs(T.defaults) do
	T.settings[k] = v
end

T.react = { shot_boost = 0, current = 1.0, weapon = nil }

T.skins = { { id = "default", name = "Default" } }

function T:load_manifest()
	local data = U.read_json(T._path .. "data/variants.json")
	local list = {}
	for _, s in ipairs(data.skins or {}) do table.insert(list, s) end
	for _, s in ipairs(_G.ScrollingTexturesLoader.skins()) do table.insert(list, s) end
	if #list > 0 then self.skins = list end

	for _, skin in ipairs(self.skins) do
		skin.ids_base = skin.base and Idstring(skin.base)
		skin.ids_glow = skin.glow and Idstring(skin.glow)
		local c = skin.color
		skin.color = c and { c[1], c[2], c[3] }
	end

	self._config_cache = {}
end

local NS = "units/mods/scrolling_textures/"
local BASE_DIFFUSE = NS .. "textures/default_df"

function T:info_for_config(config_name)
	if not config_name then
		return nil
	end
	local cache = self._config_cache
	local cached = cache[config_name]
	if cached ~= nil then
		return cached or nil
	end
	local text = U.read(self._path .. "assets/" .. NS .. "materials/" .. config_name .. ".material_config")
	if not text then
		cache[config_name] = false
		return nil
	end

	local entry = { anim = {}, base = {} }
	for _, m in ipairs(U.materials(text)) do
		local name = U.attr(m.attrs, "name")
		if name then
			local uv, diffuse
			for _, c in ipairs(m.children) do
				if c.tag == "variable" and U.attr(c.attrs, "name") == "uv_speed" then
					uv = U.attr(c.attrs, "value")
				elseif c.tag == "diffuse_texture" then
					diffuse = U.attr(c.attrs, "file")
				end
			end
			local key = Idstring(name):key()
			if uv then
				local a, b = uv:match("(%S+)%s+(%S+)")
				local ux, uy = tonumber(a) or 0, tonumber(b) or 0
				local len = math.sqrt(ux * ux + uy * uy)
				if len > 1e-6 then
					ux, uy = ux / len, uy / len
				else
					ux, uy = 1, 0
				end
				entry.anim[key] = { ux, uy }
			elseif diffuse == BASE_DIFFUSE then
				entry.base[key] = true
			end
		end
	end
	cache[config_name] = entry
	return entry
end

function T:load()
	local data = U.read_json(self._save)
	for k, v in pairs(data) do
		if self.defaults[k] ~= nil and type(v) == type(self.defaults[k]) then
			self.settings[k] = v
		end
	end

	local function legacy_slot(value)
		if type(value) == "number" and value > 1 then return value - 1 end
		if type(data.skin) == "number" then return data.skin end
	end
	if data.primary_skin == nil then
		self.settings.primary_skin = legacy_slot(data.skin_primary) or self.settings.primary_skin
	end
	if data.secondary_skin == nil then
		self.settings.secondary_skin = legacy_slot(data.skin_secondary) or self.settings.secondary_skin
	end

	local s = self.settings
	if s.bloom > 4 then s.bloom = 4 end
	if not self.skins[s.primary_skin] then s.primary_skin = 1 end
	if not self.skins[s.secondary_skin] then s.secondary_skin = 1 end
	self:sync_scrolling_textures()
end

function T:save()
	local f = io.open(self._save, "w+")
	if f then
		f:write(json.encode(self.settings))
		f:close()
	end
end

function T:sync_scrolling_textures()
	local ST = _G.ScrollingTextures or {}
	_G.ScrollingTextures = ST
	ST.menus = self.settings.menus
	ST.enabled = self.settings.enabled ~= false
	if ST.update then ST.update() end
end

function T:skin_names()
	local out = {}
	for _, s in ipairs(self.skins) do table.insert(out, s.name or s.id) end
	return out
end

local function live_base(unit)
	local base = alive(unit) and unit:base()
	if base and alive(base._unit) then return base end
end

local function selection_index(base)
	if base and base.selection_index then
		return base:selection_index()
	end
end

local function equipped_base()
	local p = managers.player and managers.player:player_unit()
	local inventory = alive(p) and p:inventory()
	return inventory and live_base(inventory:equipped_unit())
end

local function second_base(weapon)
	return weapon and live_base(weapon._second_gun)
end

function T:skin_for(weapon)
	local s = self.settings
	local idx = selection_index(weapon)
	if idx == nil and weapon and weapon._factory_id and managers.blackmarket then
		local secondary = managers.blackmarket:equipped_secondary()
		local primary = managers.blackmarket:equipped_primary()
		if secondary and secondary.factory_id == weapon._factory_id then
			idx = 1
		elseif primary and primary.factory_id == weapon._factory_id then
			idx = 2
		end
	end
	if idx == nil then
		idx = selection_index(equipped_base())
	end
	local choice = idx == 1 and s.secondary_skin or s.primary_skin
	return self.skins[choice] or self.skins[1]
end

local IDS_MATERIAL = Idstring("material")
local IDS_TEXTURE = Idstring("texture")
local IDS_NORMAL = Idstring("normal")
local IL_MULT = Idstring("il_multiplier")
local IL_BLOOM = Idstring("il_bloom")
local UV_SPEED = Idstring("uv_speed")
local SLOT_DIFFUSE = Idstring("diffuse_texture")
local SLOT_GLOW = Idstring("self_illumination_texture")

local ready = {}
local function texture_ready(ids)
	if not ids then return false end
	local key = ids:key()
	if not ready[key] then
		ready[key] = managers.dyn_resource:is_resource_ready(IDS_TEXTURE, ids, DynamicResourceManager.DYN_RESOURCES_PACKAGE) or nil
	end
	return ready[key] and true or false
end

function T:collect(weapon)
	local groups = {}
	local swapped = _G.ScrollingTextures and _G.ScrollingTextures.swapped and _G.ScrollingTextures.swapped[weapon]
	if not swapped then
		return groups
	end
	for _, part in ipairs(swapped) do
		local unit = part.unit
		local info = self:info_for_config(part.config)
		if info and alive(unit) and unit:material_config() == part.ids then
			local group = { unit = unit, ids = part.ids, anim = {}, base = {} }
			for _, m in ipairs(unit:get_objects_by_type(IDS_MATERIAL)) do
				local key = m:name():key()
				local dir = info.anim[key]
				if dir then
					table.insert(group.anim, { m, dir[1], dir[2] })
				elseif info.base[key] then
					table.insert(group.base, m)
				end
			end
			table.insert(groups, group)
		end
	end
	return groups
end

function T.group_live(group)
	return alive(group.unit) and group.unit:material_config() == group.ids
end

function T:speed_for(u, v, scale)
	local s = self.settings
	if not s.enabled or not s.scroll then
		return Vector3(0, 0, 0)
	end
	local speed = s.speed * (scale or 1)
	return Vector3(u * speed, v * speed, 0)
end

function T:breath_factor()
	local s = self.settings
	if not s.enabled or not s.breath then
		return 1
	end
	local rate = s.breath_rate
	local depth = s.breath_depth
	local offset = s.breath_offset
	local t = TimerManager:game():time()
	local v = 1 + offset + depth * math.sin(t * rate * (math.pi * 2))
	if v < 0 then v = 0 end
	return v
end

function T:glow_mult()
	local s = self.settings
	local m = s.glow * self:breath_factor()
	local r = self.react
	if r and r.current then
		m = m * r.current
	end
	return m
end

function T:write_vars(groups, mult, speed_scale, bloom)
	mult = mult or 0
	local n = 0
	for _, group in ipairs(groups) do
		if T.group_live(group) then
			for _, entry in ipairs(group.anim) do
				local m = entry[1]
				m:set_variable(IL_MULT, mult)
				m:set_variable(UV_SPEED, self:speed_for(entry[2], entry[3], speed_scale))
				if bloom then
					m:set_variable(IL_BLOOM, bloom)
				end
				n = n + 1
			end
		end
	end
	return n
end

function T:apply(weapon)
	local s = self.settings
	local groups = self:collect(weapon)
	if #groups == 0 then
		return
	end

	local skin = self:skin_for(weapon)
	local base = skin and texture_ready(skin.ids_base) and skin.ids_base
	local glow = skin and texture_ready(skin.ids_glow) and skin.ids_glow

	local mult = s.enabled and self:glow_mult() or 0
	self:write_vars(groups, mult, 1, s.bloom)
	for _, group in ipairs(groups) do
		if T.group_live(group) then
			for _, entry in ipairs(group.anim) do
				if base then Application:set_material_texture(entry[1], SLOT_DIFFUSE, base, IDS_NORMAL) end
				if glow then Application:set_material_texture(entry[1], SLOT_GLOW, glow, IDS_NORMAL) end
			end
			if base then
				for _, m in ipairs(group.base) do
					Application:set_material_texture(m, SLOT_DIFFUSE, base, IDS_NORMAL)
				end
			end
		end
	end

end

function T:apply_all()
	local swapped = _G.ScrollingTextures and _G.ScrollingTextures.swapped
	if not swapped then
		return
	end
	for weapon in pairs(swapped) do
		if weapon._unit and alive(weapon._unit) then
			self:apply(weapon)
		end
	end
end

function T:on_shot(weapon)
	local s = self.settings
	local r = self.react
	if not s.react_shot_flash or not s.enabled then return end
	if weapon ~= r.weapon and weapon ~= second_base(r.weapon) then return end
	r.shot_boost = s.react_shot_flash_boost
end

function T:update_reactive(t, dt)
	local s = self.settings
	local r = self.react
	r.weapon = equipped_base()
	if not r.weapon then
		r.shot_boost = 0
		r.current = 1.0
		return
	end

	dt = dt or 0
	r.shot_boost = math.max(0, r.shot_boost - s.react_shot_flash_decay * dt)
	local target = s.react_shot_flash and 1.0 + r.shot_boost or 1.0
	r.current = r.current + (target - r.current) * math.min(1, dt * 8)
end

Hooks:Add("ScrollingTexturesSwapped", "ScrollingTexturesSettings_apply", function(weapon)
	T:apply(weapon)
end)

T._config_cache = T._config_cache or {}
T:load_manifest()
T:load()

Hooks:Add("GameSetupUpdate", "ScrollingTexturesSettings_Update", function(t, dt)
	local s = T.settings
	if not s.enabled then
		return
	end
	T:update_reactive(t, dt)
	local r = T.react
	local reacting = r and math.abs((r.current or 1) - 1) > 0.001
	if not s.breath and not reacting then
		return
	end
	local swapped = _G.ScrollingTextures and _G.ScrollingTextures.swapped
	if not swapped then
		return
	end
	local mult = T:glow_mult()
	for weapon in pairs(swapped) do
		if weapon._unit and alive(weapon._unit) then
			local groups = T:collect(weapon)
			if #groups > 0 then
				T:write_vars(groups, mult, 1, s.bloom)
			end
		end
	end
end)

local lights = {}
local WHITE = { 1, 1, 1 }

local function kill_one(entry)
	if entry and entry.light then
		World:delete_light(entry.light)
	end
end

local function kill_all()
	for _, entry in pairs(lights) do
		kill_one(entry)
	end
	lights = {}
end

local function fire_object(base)
	if type(base._obj_fire) == "userdata" then
		return base._obj_fire
	end
	return base._unit:get_object(Idstring("fire"))
end

local function ensure_light(unit)
	local entry = lights[unit]
	if entry and entry.light then
		return entry.light
	end
	local light = World:create_light("omni|specular")
	if not light then
		return nil
	end
	lights[unit] = { light = light }
	return light
end

local function bases_to_light()
	local out = {}
	local swapped = _G.ScrollingTextures and _G.ScrollingTextures.swapped
	local primary = swapped and equipped_base()
	if primary and swapped[primary] then
		out[1] = primary
		local sec = second_base(primary)
		if sec and swapped[sec] then
			out[2] = sec
		end
	end
	return out
end

local function update_lights()
	local s = T.settings
	if not s.enabled or not s.light then
		kill_all()
		return
	end
	local want = bases_to_light()
	local keep = {}
	for _, base in ipairs(want) do
		keep[base._unit] = true
	end
	for unit, entry in pairs(lights) do
		if not keep[unit] or not alive(unit) then
			kill_one(entry)
			lights[unit] = nil
		end
	end
	local base_glow = T.defaults.glow > 0 and T.defaults.glow or 5
	local intensity = s.light_intensity * (T:glow_mult() / base_glow)
	for _, base in ipairs(want) do
		local unit = base._unit
		local light = ensure_light(unit)
		if light then
			local c = T:skin_for(base).color or WHITE
			local obj = fire_object(base)
			if obj then
				light:link(obj)
				light:set_local_position(Vector3(0, 0, 0))
			else
				light:set_position(unit:position())
			end
			light:set_far_range(s.light_range)
			light:set_color(Vector3(c[1], c[2], c[3]))
			light:set_multiplier(intensity)
			light:set_enable(true)
		end
	end
end

Hooks:Add("GameSetupUpdate", "ScrollingTexturesSettings_Light", update_lights)
