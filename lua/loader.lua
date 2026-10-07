-- Registers textures and material configs with the engine at runtime (DB:create_entry) and loads
-- them into the dynamic resource package. Replaces the old main.xml / BeardLib route.
_G.ScrollingTexturesLoader = _G.ScrollingTexturesLoader or {}
local L = _G.ScrollingTexturesLoader

if L._loaded then
	return
end
L._loaded = true

dofile(ModPath .. "lua/util.lua")
local U = _G.ScrollingTexturesUtil

local NS = "units/mods/scrolling_textures/"
L.TEX_DB = NS .. "textures/"
L.MAT_DB = NS .. "materials/"

local TEX_DIR = ModPath .. "assets/" .. L.TEX_DB
local MAT_DIR = ModPath .. "assets/" .. L.MAT_DB
local INPUT_DIR = ModPath .. "input/"
local VARIANTS_FILE = ModPath .. "data/variants.json"

local IDS_TEXTURE = Idstring("texture")
local IDS_MATERIAL_CONFIG = Idstring("material_config")

-- Names that can not be used as skin ids (the fallback texture and the black placeholder).
local RESERVED = { default = true, black = true }

L.problems = {}
L.queue = {}
L._qi = 0
L.cfg_registered = {}
L.skin_list = {}

local function problem(msg)
	L.problems[#L.problems + 1] = msg
	log("[Scrolling Textures] " .. msg)
end

local function sanitize(name)
	return (tostring(name):lower():gsub("[^%w_]", "_"))
end

local function files_in(dir)
	if not file.DirectoryExists(dir) then return {} end
	return file.GetFiles(dir) or {}
end

local function register(ids_type, db_path, file_path)
	local ids = Idstring(db_path)
	DB:create_entry(ids_type, ids, file_path)
	L.queue[#L.queue + 1] = { ids_type, ids }
end

-- Returns nil if the file is a usable DDS, otherwise a short reason.
local function dds_problem(path)
	local f = io.open(path, "rb")
	if not f then return "could not read file" end
	local head = f:read(128)
	f:close()
	if not head or #head < 128 or head:sub(1, 4) ~= "DDS " then
		return "not a DDS file"
	end
	local fourcc = head:sub(85, 88)
	if fourcc ~= "DXT1" and fourcc ~= "DXT5" then
		return "unsupported DDS format '" .. (fourcc:gsub("[^%w]", "?")) .. "', use DXT1 or DXT5"
	end
	local function u32(p)
		local a, b, c, d = head:byte(p, p + 3)
		return a + b * 256 + c * 65536 + d * 16777216
	end
	local h, w = u32(13), u32(17)
	if w % 4 ~= 0 or h % 4 ~= 0 then
		return ("size %dx%d: both sides must be multiples of 4"):format(w, h)
	end
	return nil
end

-- Optional metadata (display name, world light color) kept in data/variants.json under "imported".
local function skin_meta()
	local meta = {}
	for _, s in ipairs(U.read_json(VARIANTS_FILE).imported or {}) do
		if s.id then meta[s.id] = s end
	end
	return meta
end

local function make_skin(id, meta)
	local m = meta[id] or {}
	return {
		id = id,
		name = m.name or id,
		base = L.TEX_DB .. id .. "_df",
		glow = L.TEX_DB .. id .. "_il",
		color = m.color,
	}
end

-- 1) Everything already shipped in assets/.../textures (bundled and earlier imports).
local function register_shipped()
	local have = {}
	for _, f in ipairs(files_in(TEX_DIR)) do
		local stem = f:match("^(.+)%.texture$")
		if stem then
			have[stem] = true
			register(IDS_TEXTURE, L.TEX_DB .. stem, TEX_DIR .. f)
		end
	end
	local out = {}
	for stem in pairs(have) do
		local id = stem:match("^(.+)_df$")
		if id and have[id .. "_il"] and not RESERVED[id:lower()] then
			out[id] = true
		end
	end
	return out
end

-- 2) Pairs dropped into input/. They stay where they are and are registered straight from there.
local function scan_input()
	local files = files_in(INPUT_DIR)
	table.sort(files)
	local sets, order = {}, {}
	for _, f in ipairs(files) do
		local base, ext = f:match("^(.+)%.(%w+)$")
		ext = ext and ext:lower()
		if base and (ext == "dds" or ext == "texture") then
			local tail = base:lower():sub(-3)
			local key, kind
			if #base > 3 and (tail == "_df" or tail == "_il") then
				key, kind = base:sub(1, -4), tail:sub(2)
			else
				key, kind = base, "plain"
			end
			if not sets[key] then
				sets[key] = {}
				order[#order + 1] = key
			end
			sets[key][kind] = INPUT_DIR .. f
		end
	end

	local found = {}
	for _, name in ipairs(order) do
		local p = sets[name]
		if p.df and p.il then
			found[#found + 1] = { name = name, df = p.df, il = p.il }
		elseif p.plain and not p.df and not p.il then
			found[#found + 1] = { name = name, df = p.plain, il = p.plain }
		else
			problem("input '" .. name .. "' ignored: needs both _df and _il")
		end
	end
	return found
end

local function register_input(ids_out)
	for _, entry in ipairs(scan_input()) do
		local id = sanitize(entry.name)
		local why = RESERVED[id] and "name is reserved, please rename the files"
			or dds_problem(entry.df) or dds_problem(entry.il)
		if why then
			problem(entry.name .. ": " .. why)
		else
			register(IDS_TEXTURE, L.TEX_DB .. id .. "_df", entry.df)
			register(IDS_TEXTURE, L.TEX_DB .. id .. "_il", entry.il)
			ids_out[id] = true
		end
	end
end

-- 3) Material configs. Called at start for what is on disk and again by the generator for new files.
function L.register_configs(names)
	for _, name in ipairs(names) do
		if not L.cfg_registered[name] then
			L.cfg_registered[name] = true
			register(IDS_MATERIAL_CONFIG, L.MAT_DB .. name, MAT_DIR .. name .. ".material_config")
		end
	end
	L.start_loading()
end

local function list_config_names()
	local names = {}
	for _, f in ipairs(files_in(MAT_DIR)) do
		local n = f:match("^(.*)%.material_config$")
		if n then names[#names + 1] = n end
	end
	table.sort(names)
	return names
end

-- Skin list for the settings menu: built fresh on every start, nothing is written to disk.
function L.skins()
	return L.skin_list
end

-- Loads queued resources into the dynamic package, a few per tick so the menu does not hitch.
function L.start_loading()
	if L._loading or not managers or not managers.dyn_resource then return end
	if #L.queue == 0 then return end
	L._loading = true
	local package = DynamicResourceManager.DYN_RESOURCES_PACKAGE

	local function step()
		local n = 0
		while L._qi < #L.queue and n < 40 do
			L._qi = L._qi + 1
			local q = L.queue[L._qi]
			managers.dyn_resource:load(q[1], q[2], package)
			n = n + 1
		end
		if L._qi < #L.queue then
			DelayedCalls:Add("ScrollingTextures_load", 0.05, step)
		else
			L.queue, L._qi, L._loading = {}, 0, false
			local ST = _G.ScrollingTextures
			if ST and ST.update then ST.update() end
		end
	end
	step()
end

do
	local ids = register_shipped()
	register_input(ids)

	local meta = skin_meta()
	local list = {}
	for id in pairs(ids) do list[#list + 1] = make_skin(id, meta) end
	table.sort(list, function(a, b) return a.id < b.id end)
	L.skin_list = list

	L.register_configs(list_config_names())
end

Hooks:Add("MenuManagerOnOpenMenu", "ScrollingTexturesLoader_start", function(menu_manager, menu_name)
	if menu_name == "menu_main" then L.start_loading() end
end)
