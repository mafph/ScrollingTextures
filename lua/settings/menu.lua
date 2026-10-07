dofile(ModPath .. "lua/settings/core.lua")
core:import("CoreMenuItemOption")
local T = _G.ScrollingTexturesSettings

local MENU = "st_settings"
local MENU_SKIN = "st_settings_skin"
local MENU_VISUALS = "st_settings_visuals"
local refresh_skin_choices

Hooks:Add("LocalizationManagerPostInit", "ScrollingTextures_loc", function(loc)
	loc:load_localization_file(T._path .. "loc/english.txt")
end)

local function refresh_active_menu(menu_id)
	local menu = MenuHelper:GetMenu(menu_id)
	if not (menu and menu._items) then return end
	for _, item in pairs(menu._items) do
		local p = item._parameters
		if p and p.name then
			local key = p.name:match("^st_(.+)$")
			if key and T.settings[key] ~= nil then
				local v = T.settings[key]
				if type(v) == "boolean" then v = v and "on" or "off" end
				item:set_value(v)
			end
		end
	end
end

local function do_reset(menu_id, keys)
	for _, k in ipairs(keys) do
		if T.defaults[k] ~= nil then
			T.settings[k] = T.defaults[k]
		end
	end
	T:sync_scrolling_textures()
	T:save()
	T:apply_all()
	refresh_active_menu(menu_id)
end

Hooks:Add("MenuManagerInitialize", "ScrollingTextures_callbacks", function(menu_manager)
	local function set(key, value, repaint)
		T.settings[key] = value
		if repaint then T:apply_all() end
	end
	local function slider(key, repaint)
		return function(self, item) set(key, tonumber(item:value()) or T.defaults[key], repaint) end
	end
	local function toggle(key, repaint)
		return function(self, item) set(key, item:value() == "on", repaint) end
	end
	local function choice(key, repaint)
		return function(self, item) set(key, item:value(), repaint) end
	end

	MenuCallbackHandler.st_set_primary_skin = choice("primary_skin", true)
	MenuCallbackHandler.st_set_secondary_skin = choice("secondary_skin", true)
	MenuCallbackHandler.st_set_enabled = function(self, item)
		set("enabled", item:value() == "on")
		T:sync_scrolling_textures()
		T:save()
		if T.settings.enabled then T:apply_all() end
	end
	MenuCallbackHandler.st_set_scroll = toggle("scroll", true)
	MenuCallbackHandler.st_set_menus = function(self, item)
		set("menus", item:value() == "on")
		T:sync_scrolling_textures()
	end
	MenuCallbackHandler.st_set_breath = toggle("breath", true)
	MenuCallbackHandler.st_set_breath_rate = slider("breath_rate", true)
	MenuCallbackHandler.st_set_breath_depth = slider("breath_depth", true)
	MenuCallbackHandler.st_set_breath_offset = slider("breath_offset", true)
	MenuCallbackHandler.st_set_glow = slider("glow", true)
	MenuCallbackHandler.st_set_bloom = slider("bloom", true)
	MenuCallbackHandler.st_set_speed = slider("speed", true)
	MenuCallbackHandler.st_set_light = toggle("light", true)
	MenuCallbackHandler.st_set_light_intensity = slider("light_intensity", true)
	MenuCallbackHandler.st_set_light_range = slider("light_range", true)
	MenuCallbackHandler.st_set_react_shot_flash = toggle("react_shot_flash", true)
	MenuCallbackHandler.st_set_react_shot_flash_boost = slider("react_shot_flash_boost", true)
	MenuCallbackHandler.st_set_react_shot_flash_decay = slider("react_shot_flash_decay", true)

	local SKIN_KEYS = {
		"primary_skin", "secondary_skin", "enabled", "scroll", "menus",
		"glow", "bloom", "speed"
	}
	local VISUAL_KEYS = {
		"react_shot_flash", "react_shot_flash_boost", "react_shot_flash_decay",
		"breath", "breath_rate", "breath_depth", "breath_offset",
		"light", "light_intensity", "light_range"
	}

	MenuCallbackHandler.st_reset_skin = function()
		do_reset(MENU_SKIN, SKIN_KEYS)
		QuickMenu:new(managers.localization:text("st_reset_skin_title"), managers.localization:text("st_reset_done"), {}, true)
	end
	MenuCallbackHandler.st_rescan_skins = function()
		_G.ScrollingTexturesLoader.rescan()
		T:load_manifest()
		refresh_skin_choices(MENU_SKIN)
		DelayedCalls:Add("ScrollingTextures_rescan_apply", 0.5, function()
			local ST = _G.ScrollingTextures
			if ST and ST.update then ST.update() end
		end)
		QuickMenu:new(managers.localization:text("st_rescan_skins_title"), managers.localization:text("st_rescan_skins_done"), {}, true)
	end
	MenuCallbackHandler.st_reset_visuals = function()
		do_reset(MENU_VISUALS, VISUAL_KEYS)
		QuickMenu:new(managers.localization:text("st_reset_visuals_title"), managers.localization:text("st_reset_done"), {}, true)
	end
	MenuCallbackHandler.st_save = function() T:save() end
end)

Hooks:Add("MenuManagerSetupCustomMenus", "ScrollingTextures_setup", function()
	MenuHelper:NewMenu(MENU)
	MenuHelper:NewMenu(MENU_SKIN)
	MenuHelper:NewMenu(MENU_VISUALS)
end)

local function add_to(menu_id, kind, id, data)
	data.id = "st_" .. id
	data.title = "st_" .. id .. "_title"
	data.desc = "st_" .. id .. "_desc"
	if not data.callback then data.callback = "st_set_" .. id end
	data.menu_id = menu_id
	data.priority = data.priority or 100
	if kind == "slider" then
		data.show_value = true
		MenuHelper:AddSlider(data)
	elseif kind == "toggle" then
		MenuHelper:AddToggle(data)
	else
		MenuHelper:AddMultipleChoice(data)
	end
end

Hooks:Add("MenuManagerPopulateCustomMenus", "ScrollingTextures_populate", function()
	local s = T.settings

	add_to(MENU_SKIN, "choice", "primary_skin", { value = s.primary_skin, items = T:skin_names(), localized_items = false, priority = 100 })
	add_to(MENU_SKIN, "choice", "secondary_skin", { value = s.secondary_skin, items = T:skin_names(), localized_items = false, priority = 99 })
	MenuHelper:AddButton({ id = "st_rescan_skins", title = "st_rescan_skins_title", desc = "st_rescan_skins_desc", callback = "st_rescan_skins", menu_id = MENU_SKIN, priority = 98 })
	add_to(MENU_SKIN, "toggle", "enabled", { value = s.enabled, priority = 98 })
	add_to(MENU_SKIN, "toggle", "scroll", { value = s.scroll, priority = 97 })
	add_to(MENU_SKIN, "toggle", "menus", { value = s.menus, priority = 96 })
	add_to(MENU_SKIN, "slider", "glow", { value = s.glow, min = 0, max = 20, step = 0.5, priority = 95 })
	add_to(MENU_SKIN, "slider", "bloom", { value = s.bloom, min = 0, max = 4, step = 0.25, priority = 94 })
	add_to(MENU_SKIN, "slider", "speed", { value = s.speed, min = 0, max = 0.5, step = 0.01, priority = 93 })
	MenuHelper:AddButton({ id = "st_reset_skin", title = "st_reset_skin_title", desc = "st_reset_skin_desc", callback = "st_reset_skin", menu_id = MENU_SKIN, priority = 10 })

	add_to(MENU_VISUALS, "toggle", "react_shot_flash", { value = s.react_shot_flash, priority = 99 })
	add_to(MENU_VISUALS, "slider", "react_shot_flash_boost", { value = s.react_shot_flash_boost, min = 0, max = 10, step = 0.1, priority = 98 })
	add_to(MENU_VISUALS, "slider", "react_shot_flash_decay", { value = s.react_shot_flash_decay, min = 0.1, max = 100, step = 0.1, priority = 97 })
	MenuHelper:AddDivider({ id = "st_div_visuals", size = 12, menu_id = MENU_VISUALS, priority = 95 })
	add_to(MENU_VISUALS, "toggle", "breath", { value = s.breath, priority = 94 })
	add_to(MENU_VISUALS, "slider", "breath_rate", { value = s.breath_rate, min = 0.2, max = 30, step = 0.1, priority = 93 })
	add_to(MENU_VISUALS, "slider", "breath_depth", { value = s.breath_depth, min = 0, max = 1, step = 0.05, priority = 92 })
	add_to(MENU_VISUALS, "slider", "breath_offset", { value = s.breath_offset, min = -0.8, max = 0.8, step = 0.05, priority = 91 })
	add_to(MENU_VISUALS, "toggle", "light", { value = s.light, priority = 87 })
	add_to(MENU_VISUALS, "slider", "light_intensity", { value = s.light_intensity, min = 0, max = 5, step = 0.1, priority = 86 })
	add_to(MENU_VISUALS, "slider", "light_range", { value = s.light_range, min = 50, max = 800, step = 10, priority = 85 })
	MenuHelper:AddButton({ id = "st_reset_visuals", title = "st_reset_visuals_title", desc = "st_reset_visuals_desc", callback = "st_reset_visuals", menu_id = MENU_VISUALS, priority = 10 })
end)

Hooks:Add("MenuManagerBuildCustomMenus", "ScrollingTextures_build", function(menu_manager, nodes)
	nodes[MENU] = MenuHelper:BuildMenu(MENU, { back_callback = "st_save" })
	nodes[MENU_SKIN] = MenuHelper:BuildMenu(MENU_SKIN, { back_callback = "st_save" })
	nodes[MENU_VISUALS] = MenuHelper:BuildMenu(MENU_VISUALS, { back_callback = "st_save" })
	nodes[MENU_SKIN]:parameters().hide_bg = true

	MenuHelper:AddMenuItem(nodes.blt_options, MENU, "st_menu_title", "st_menu_desc")
	MenuHelper:AddMenuItem(nodes[MENU], MENU_SKIN, "st_skin_menu_title", "st_skin_menu_desc")
	MenuHelper:AddMenuItem(nodes[MENU], MENU_VISUALS, "st_reactive_menu_title", "st_reactive_menu_desc")
end)

refresh_skin_choices = function(menu_id)
	local menu = MenuHelper:GetMenu(menu_id)
	if not (menu and menu._items) then return end
	local names = T:skin_names()
	for _, item in pairs(menu._items) do
		local p = item._parameters
		if p and (p.name == "st_primary_skin" or p.name == "st_secondary_skin") and item.clear_options then
			local current = item:value()
			item:clear_options()
			for i, name in ipairs(names) do
				item:add_option(CoreMenuItemOption.ItemOption:new(nil, { text_id = name, value = i, localize = false }))
			end
			item:_show_options(item._callback_handler)
			item:set_value(current)
		end
	end
end

