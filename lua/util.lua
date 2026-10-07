_G.ScrollingTexturesUtil = _G.ScrollingTexturesUtil or {}
local U = _G.ScrollingTexturesUtil

if U.materials then
	return
end

function U.read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local data = f:read("*all")
	f:close()
	return data
end

function U.read_json(path)
	local text = U.read(path)
	if not text then return {} end
	local ok, data = pcall(json.decode, text)
	if ok and type(data) == "table" then return data end
	return {}, true
end

function U.attrs(s)
	local out = {}
	for k, v in s:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do out[#out + 1] = { k, v } end
	return out
end

function U.attr(list, key)
	for _, kv in ipairs(list) do
		if kv[1] == key then return kv[2] end
	end
end

function U.materials(text)
	local list, pos = {}, 1
	while true do
		local s, e, attrs = text:find("<material%s+([^>]-)>", pos)
		if not s then break end
		local body = ""
		if attrs:sub(-1) == "/" then
			pos = e + 1
		else
			local cs, ce = text:find("</material>", e + 1, true)
			if not cs then break end
			body = text:sub(e + 1, cs - 1)
			pos = ce + 1
		end
		local children = {}
		for tag, cattrs in body:gmatch("<([%w_]+)%s+([^>]-)/?>") do
			children[#children + 1] = { tag = tag, attrs = U.attrs(cattrs) }
		end
		list[#list + 1] = { attrs = U.attrs(attrs), children = children }
	end
	return list
end
