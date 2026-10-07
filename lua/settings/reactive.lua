dofile(ModPath .. "lua/settings/core.lua")
local T = _G.ScrollingTexturesSettings

if not T then
	return
end
if T._reactive_loaded then
	return
end
T._reactive_loaded = true

T.react = T.react or {
	assault = false,
	anticipation = false,
	shot_boost = 0,
	current = 1.0,
	applied = nil,
	weapon = nil,
	groups = nil,
	groups_age = 0,
	time = 0,
}

function T:on_assault(active)
	self.react.assault = active and true or false
	if active then
		self.react.anticipation = false
	end
end

function T:on_anticipation()
	self.react.anticipation = true
end

local function equipped_base()
	local p = managers.player and managers.player:player_unit()
	if not alive(p) then return nil end
	local inventory = p:inventory()
	local unit = inventory and inventory:equipped_unit()
	local base = alive(unit) and unit:base()
	if base and base._unit and alive(base._unit) then return base end
	return nil
end

local function second_base(weapon)
	if not weapon then return nil end
	local u = weapon._second_gun
	if not alive(u) then return nil end
	local base = u:base()
	if base and base._unit and alive(base._unit) then return base end
	return nil
end

local function is_equipped_pair(weapon, primary)
	if not weapon or not primary then return false end
	if weapon == primary then return true end
	local sec = second_base(primary)
	return sec and weapon == sec
end

local function collect_pair(primary)
	local groups = T:collect(primary)
	local sec = second_base(primary)
	if sec then
		for _, g in ipairs(T:collect(sec)) do
			groups[#groups + 1] = g
		end
	end
	return groups
end

function T:on_shot(weapon)
	local s = self.settings
	local r = self.react
	if not s.reactive or not s.enabled then return end
	if not is_equipped_pair(weapon, r.weapon) then return end
	if s.react_shot_flash then
		r.shot_boost = s.react_shot_flash_boost or 2.5
	end
end

local function target_multiplier()
	local s = T.settings
	local r = T.react
	local mult = 1.0
	if s.reactive then
		if r.assault then
			mult = mult * 1.25
		elseif r.anticipation then
			mult = mult * 1.1
		end
		if s.react_shot_flash then
			mult = mult + (r.shot_boost or 0)
		end
	end
	return mult
end

local function apply_to_groups(groups, mult)
	for _, g in ipairs(groups or {}) do
		T:apply_group(g, mult)
	end
end

function T:update_reactive(t, dt)
	local r = self.react
	r.time = t or Application:time()
	local primary = equipped_base()
	r.weapon = primary
	if not primary then
		r.groups = nil
		r.applied = nil
		r.shot_boost = 0
		return
	end

	r.groups_age = (r.groups_age or 0) + (dt or 0)
	if not r.groups or r.groups_age > 1 or not is_equipped_pair(primary, r.weapon) then
		r.groups = collect_pair(primary)
		r.groups_age = 0
	end

	local decay = (self.settings.react_shot_flash_decay or 6) * (dt or 0)
	r.shot_boost = math.max(0, (r.shot_boost or 0) - decay)

	local target = target_multiplier()
	local smooth = math.min(1, (dt or 0) * 8)
	r.current = r.current + (target - r.current) * smooth

	if r.applied == nil or math.abs((r.applied or 0) - r.current) > 0.001 then
		apply_to_groups(r.groups, r.current)
		r.applied = r.current
	end
end
