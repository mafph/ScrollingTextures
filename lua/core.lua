_G.ScrollingTextures = _G.ScrollingTextures or {}
local ST = _G.ScrollingTextures

dofile(ModPath .. "lua/loader.lua")

ST.path = ModPath
ST.enabled = ST.enabled ~= false
ST.menus = ST.menus ~= false
ST.weapons = ST.weapons or setmetatable({}, { __mode = "k" })
ST.swapped = ST.swapped or setmetatable({}, { __mode = "k" })

-- Reads data/map.json (vanilla part config -> our config). Called at start and again by the
-- generator after it wrote a new map, so a regeneration does not need a restart.
function ST.load_map()
	ST.map, ST.alias, ST.our_keys = {}, {}, {}
	local map_file = io.open(ST.path .. "data/map.json", "r")
	if not map_file then return end
	for vanilla, ours in pairs(json.decode(map_file:read("*all"))) do
		ST.our_keys[Idstring(ours):key()] = true
		local entry = { ids = Idstring(ours), name = ours }
		local hash = vanilla:match("^@ID(%x+)@$")
		if hash then ST.alias[hash] = entry else ST.map[Idstring(vanilla):key()] = entry end
	end
	map_file:close()
end
ST.load_map()

local function lookup(cfg)
	if type(cfg) == "string" then return ST.map[Idstring(cfg):key()] end
	if not cfg then return nil end
	return ST.map[cfg:key()] or ST.alias[tostring(cfg):match("@ID(%x+)@") or ""]
end

function ST.update()
	for weapon in pairs(ST.weapons) do
		if alive(weapon._unit) then weapon:_update_materials() end
	end
end

if _G.NewRaycastWeaponBase then
	Hooks:PostHook(NewRaycastWeaponBase, "_material_config_name", "ScrollingTextures_swap_name", function(self)
		local name = Hooks:GetReturn()
		local target = lookup(name)
		local heist = Global.level_data and Global.level_data.level_id
		local wanted = ST.enabled and not _G.IS_VR and not self._cosmetics_data
			and (heist and not self:is_npc() or not heist and ST.menus)
		if target and wanted and managers.dyn_resource:is_resource_ready(
			Idstring("material_config"), target.ids, DynamicResourceManager.DYN_RESOURCES_PACKAGE) then
			return type(name) == "string" and target.name or target.ids
		end
	end)
end

Hooks:PostHook(NewRaycastWeaponBase, "_update_materials", "ScrollingTextures_swap", function(self)
	local heist = Global.level_data and Global.level_data.level_id
	if (heist and self:is_npc()) or not self._parts or not self._factory_id then return end
	ST.weapons[self] = true

	local wanted = ST.enabled and not _G.IS_VR and not self._cosmetics_data
		and (heist or ST.menus)
	local list = {}

	for part_id, part in pairs(self._parts) do
		local data = managers.weapon_factory:get_part_data_by_part_id_from_weapon(part_id, self._factory_id, self._blueprint)
		local vanilla = alive(part.unit) and data and (data.material_config or data.unit)
		if vanilla then
			local original = type(vanilla) == "string" and Idstring(vanilla) or vanilla
			local target = lookup(vanilla)
			local current = part.unit:material_config()
			local ready = target and managers.dyn_resource:is_resource_ready(
				Idstring("material_config"), target.ids, DynamicResourceManager.DYN_RESOURCES_PACKAGE)

			if wanted and ready then
				if not current or current:key() ~= target.ids:key() then part.unit:set_material_config(target.ids, true) end
				list[#list + 1] = { unit = part.unit, ids = target.ids, config = target.name:match("[^/]+$"), part_id = part_id }
			elseif not self._cosmetics_data and current and ST.our_keys[current:key()] then
				part.unit:set_material_config(original, true)
			end
		end
	end

	ST.swapped[self] = #list > 0 and list or nil
	if #list > 0 then Hooks:Call("ScrollingTexturesSwapped", self, list) end
end)

Hooks:Add("MenuManagerOnOpenMenu", "ScrollingTextures_menu_refresh", function(menu_manager, menu_name)
	if menu_name == "menu_main" then ST.update() end
end)
