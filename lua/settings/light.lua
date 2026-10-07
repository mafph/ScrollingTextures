dofile(ModPath .. "lua/settings/core.lua")
local T = _G.ScrollingTexturesSettings

if T._light_loaded then
	return
end
T._light_loaded = true

local lights = {}

local function kill_one(entry)
	if entry and entry.light then
		World:delete_light(entry.light)
	end
end

local function kill_all()
	for u, entry in pairs(lights) do
		kill_one(entry)
	end
	lights = {}
end

local function fire_object(base)
	if not base or not base._unit or not alive(base._unit) then
		return nil, nil
	end
	local unit = base._unit
	if type(base._obj_fire) == "userdata" then
		return base._obj_fire, unit
	end
	local obj = unit:get_object(Idstring("fire"))
	if obj then
		return obj, unit
	end
	return nil, unit
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
	if not swapped then
		return out
	end
	local p = managers.player and managers.player:player_unit()
	if not alive(p) then
		return out
	end
	local inv = p:inventory()
	local eq = inv and inv:equipped_unit()
	if not alive(eq) then
		return out
	end
	local primary = eq:base()
	if primary and swapped[primary] then
		out[#out + 1] = primary
		local sec_u = primary._second_gun
		if alive(sec_u) then
			local sec = sec_u:base()
			if sec and swapped[sec] then
				out[#out + 1] = sec
			end
		end
	end
	return out
end

local WHITE = { 1, 1, 1 }

local function skin_color(skin)
	if not skin then return WHITE end
	if skin.color == nil then
		skin.color = false
		local CS = _G.ScrollingTexturesRT
		if CS and CS.glow_color_file and T._scrolling_textures and skin.glow then
			skin.color = CS.glow_color_file(T._scrolling_textures .. "assets/" .. skin.glow .. ".texture") or false
		end
	end
	return skin.color or WHITE
end

local function update()
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
	local mult = (T.react and T.react.applied) or (s.glow * (T.breath_factor and T:breath_factor() or 1))
	local base_glow = T.defaults.glow > 0 and T.defaults.glow or 5
	local intensity = (s.light_intensity or 1) * (mult / base_glow)
	local range = s.light_range or 200
	for _, base in ipairs(want) do
		local unit = base._unit
		if alive(unit) then
			local light = ensure_light(unit)
			if light then
				local c = skin_color(T:skin_for(base))
				local color = Vector3(c[1], c[2], c[3])
				local obj, owner = fire_object(base)
				if obj then
					light:link(obj)
					light:set_local_position(Vector3(0, 0, 0))
				else
					light:set_position(unit:position())
				end
				light:set_far_range(range)
				light:set_color(color)
				light:set_multiplier(intensity)
				light:set_enable(true)
			end
		end
	end
end

Hooks:Add("GameSetupUpdate", "ScrollingTexturesSettings_Light", function()
	update()
end)
