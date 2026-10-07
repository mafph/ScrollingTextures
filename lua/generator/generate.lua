_G.ScrollingTexturesGenerator = _G.ScrollingTexturesGenerator or {}
local G = _G.ScrollingTexturesGenerator

local MOD_PATH = ModPath
dofile(MOD_PATH .. "lua/util.lua")
local U = _G.ScrollingTexturesUtil
dofile(MOD_PATH .. "lua/loader.lua")
local L = _G.ScrollingTexturesLoader

G.VERSION = 11

G.NS = "units/mods/scrolling_textures/"
G.MATERIALS_DB = G.NS .. "materials/"
G.TEX_DB = G.NS .. "textures/"
G.FILE_MANIFEST = "data/generated.json"

local function prompt_restart(message)
	local loc = managers.localization
	local yes = {
		text = loc:text("dialog_yes"),
		callback = function()
			DelayedCalls:Add("ScrollingTextures_restart", 0.15, function() setup:quit() end)
		end,
	}
	local no = { text = loc:text("dialog_no"), is_cancel_button = true }
	QuickMenu:new("Scrolling Textures", message, { yes, no }, true)
end

local function exists(path)
	local f = io.open(path, "rb")
	if f then f:close() return true end
	return false
end

G.problems = G.problems or {}
local function problem(msg)
	G.problems[#G.problems + 1] = msg
end

local function write_text(path, text)
	local f = io.open(path, "wb")
	if not f then
		problem("could not write " .. path:match("[^/]+$"))
		return false
	end
	f:write(text)
	f:close()
	return true
end

local function hash_list(list)
	local h = 5381
	for _, s in ipairs(list) do
		for i = 1, #s do
			h = (h * 33 + s:byte(i)) % 4294967296
		end
		h = (h * 33 + 10) % 4294967296
	end
	return ("%08x"):format(h)
end

local function ensure_dir(path)
	path = path:gsub("\\", "/"):gsub("/+$", "")
	if file.DirectoryExists(path) then return end
	local parent = path:match("^(.*)/[^/]+$")
	if parent and parent ~= "" and not parent:match("^%a:$") then
		ensure_dir(parent)
	end
	file.CreateDirectory(path)
	if not file.DirectoryExists(path) then
		problem("could not create directory " .. path)
	end
end

local function dir_files(path)
	if not path or path == "" or not file.DirectoryExists(path) then
		return {}
	end
	return file.GetFiles(path) or {}
end

function G:config_names_from_dir()
	local names = {}
	local dir = MOD_PATH .. "assets/" .. G.MATERIALS_DB
	ensure_dir(dir)
	for _, f in ipairs(dir_files(dir)) do
		local n = f:match("^(.*)%.material_config$")
		if n then names[#names + 1] = n end
	end
	table.sort(names)
	return names
end

function G:config_signature(units)
	return table.concat({
		G.VERSION,
		#units,
		hash_list(units),
	}, "|")
end

function G:read_manifest()
	return U.read_json(MOD_PATH .. G.FILE_MANIFEST)
end

function G:write_manifest(csig)
	return write_text(MOD_PATH .. G.FILE_MANIFEST, json.encode({
		version = G.VERSION, configs = csig,
	}))
end

-- Builds the material configs when the game's part list changed. New files are registered and
-- loaded right away. A restart is only asked for when a config that is already loaded changed
-- its content, because a loaded resource can not be replaced while the game runs.
function G:process()
	ensure_dir(MOD_PATH .. "input")
	local C = _G.CSR_Config
	local old = G:read_manifest()

	local units = C.game_part_units() or {}
	local csig = G:config_signature(units)
	local config_names = G:config_names_from_dir()
	local stale = old.configs ~= csig
		or not exists(MOD_PATH .. "data/map.json")
		or #config_names == 0
	if not stale then
		return
	end

	local res = C.build(MOD_PATH .. "data/", {
		df = G.TEX_DB .. "default_df",
		il = G.TEX_DB .. "default_il",
		black = G.TEX_DB .. "black",
	})
	local matdir = MOD_PATH .. "assets/" .. G.MATERIALS_DB
	ensure_dir(matdir)

	local needs_restart = false
	config_names = {}
	for name, content in pairs(res.configs) do
		config_names[#config_names + 1] = name
		local path = matdir .. name .. ".material_config"
		if L.cfg_registered[name] then
			local before = U.read(path)
			if before and before ~= content then needs_restart = true end
		end
		if not write_text(path, content) then return end
	end
	table.sort(config_names)
	local keep_cfg = {}
	for _, n in ipairs(config_names) do keep_cfg[n .. ".material_config"] = true end
	for _, f in ipairs(dir_files(matdir)) do
		if f:find("%.material_config$") and not keep_cfg[f] then
			os.remove(matdir .. f)
		end
	end
	if not write_text(MOD_PATH .. "data/map.json", C.mapping_json(res, G.MATERIALS_DB)) then return end
	if not G:write_manifest(csig) then return end

	L.register_configs(config_names)
	local ST = _G.ScrollingTextures
	if ST and ST.load_map then
		ST.load_map()
		if ST.update then ST.update() end
	end

	local msg = ("%d material configs generated."):format(#config_names)
	if needs_restart then
		return msg .. " Some existing configs changed, restart now to load them?", true
	end
	return msg
end

local function show_ok(message)
	local ok = { text = managers.localization:text("dialog_ok"), is_cancel_button = true }
	QuickMenu:new("Scrolling Textures", message, { ok }, true)
end

function G:run()
	G.problems = {}
	for _, msg in ipairs(L.problems) do G.problems[#G.problems + 1] = msg end
	local message, restart = G:process()
	local lines = {}
	for i, msg in ipairs(G.problems) do
		if i > 6 then
			lines[#lines + 1] = ("... and %d more"):format(#G.problems - 6)
			break
		end
		lines[#lines + 1] = msg
	end
	if message then
		if #lines > 0 then lines[#lines + 1] = "" end
		lines[#lines + 1] = message
	end
	if restart then
		prompt_restart(table.concat(lines, "\n"))
	elseif #lines > 0 then
		show_ok(table.concat(lines, "\n"))
	end
end

dofile(MOD_PATH .. "lua/generator/configs.lua")

if not G._hooked then
	G._hooked = true
	Hooks:Add("MenuManagerOnOpenMenu", "ScrollingTexturesGen_start", function(menu_manager, menu_name)
		if menu_name == "menu_main" and not G._started then
			G._started = true
			G:run()
		end
	end)
end
