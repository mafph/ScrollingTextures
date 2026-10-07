_G.ScrollingTexturesRT = _G.ScrollingTexturesRT or {}
local CSR = _G.ScrollingTexturesRT

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local INPUT_DIR = ModPath .. "input/"
-- Namensraum: muss mit G.NS in generate.lua uebereinstimmen.
local OUTPUT_DB = "units/mods/scrolling_textures/textures/"
local OUTPUT_DIR = ModPath .. "assets/" .. OUTPUT_DB

CSR.settings = CSR.settings or {
	max_size = 512,
	scan_dirs = { "assets/mod_overrides/", "mods/" },
	glow_contrast = 1.6,
	glow_brightness = 1.4,
	glow_scale = 0.1,
}
CSR.TILE_SIZE = CSR.TILE_SIZE or 512
CSR.BLEND_WIDTH = CSR.BLEND_WIDTH or 16

local function fail(msg)
	msg = "[Scrolling Textures] " .. msg
	log(msg)
	error(msg, 0)
end

local function read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local data = f:read("*all")
	f:close()
	return data
end

local function le(s, p, n)
	local v = 0
	for i = n - 1, 0, -1 do v = v * 256 + s:byte(p + i) end
	return v
end

local function pack(v, n)
	local s = ""
	for _ = 1, n do
		s = s .. string.char(v % 256)
		v = floor(v / 256)
	end
	return s
end

local function rgb565(v)
	local r, g, b = floor(v / 2048), floor(v / 32) % 64, v % 32
	return r * 8 + floor(r / 4), g * 4 + floor(g / 16), b * 8 + floor(b / 4)
end

local function luma(p)
	return floor((floor(p / 65536) * 19595 + floor(p / 256) % 256 * 38470 + p % 256 * 7471 + 32768) / 65536)
end

function CSR.decode_dds(data, max_size)
	if #data < 128 or data:sub(1, 4) ~= "DDS " then fail("not a DDS file") end
	local fourcc = data:sub(85, 88)
	if fourcc ~= "DXT1" and fourcc ~= "DXT5" then fail("unsupported DDS format '" .. fourcc .. "', use DXT1 or DXT5") end
	local h, w = le(data, 13, 4), le(data, 17, 4)
	local dxt5 = fourcc == "DXT5"
	local step = 1
	while max_size and max(w, h) / step > max_size do step = step * 2 end
	local ow, bw = ceil(w / step), ceil(w / 4)
	local px = {}
	local jump = max(1, step / 4)

	for by = 0, ceil(h / 4) - 1, jump do
		for bx = 0, bw - 1, jump do
			local o = 129 + (by * bw + bx) * (dxt5 and 16 or 8) + (dxt5 and 8 or 0)
			local c0, c1, bits = le(data, o, 2), le(data, o + 2, 2), le(data, o + 4, 4)
			local r0, g0, b0 = rgb565(c0)
			local r1, g1, b1 = rgb565(c1)
			local pr, pg, pb
			if dxt5 or c0 > c1 then
				pr = { r0, r1, floor((2 * r0 + r1) / 3), floor((r0 + 2 * r1) / 3) }
				pg = { g0, g1, floor((2 * g0 + g1) / 3), floor((g0 + 2 * g1) / 3) }
				pb = { b0, b1, floor((2 * b0 + b1) / 3), floor((b0 + 2 * b1) / 3) }
			else
				pr = { r0, r1, floor((r0 + r1) / 2), 0 }
				pg = { g0, g1, floor((g0 + g1) / 2), 0 }
				pb = { b0, b1, floor((b0 + b1) / 2), 0 }
			end
			for i = 0, 15 do
				local x, y = bx * 4 + i % 4, by * 4 + floor(i / 4)
				if x < w and y < h and x % step == 0 and y % step == 0 then
					local k = floor(bits / 4 ^ i) % 4 + 1
					px[y / step * ow + x / step + 1] = pr[k] * 65536 + pg[k] * 256 + pb[k]
				end
			end
		end
	end
	return { w = ow, h = ceil(h / step), px = px }
end

function CSR.encode_dds(img)
	local w, h, px = img.w, img.h, img.px
	local blocks, n = {}, 0
	local rs, gs, bs = {}, {}, {}

	for by = 0, ceil(h / 4) - 1 do
		for bx = 0, ceil(w / 4) - 1 do
			local lr, lg, lb, hr, hg, hb = 255, 255, 255, 0, 0, 0
			for i = 0, 15 do
				local p = px[min(by * 4 + floor(i / 4), h - 1) * w + min(bx * 4 + i % 4, w - 1) + 1]
				local r, g, b = floor(p / 65536), floor(p / 256) % 256, p % 256
				rs[i], gs[i], bs[i] = r, g, b
				lr, hr = min(lr, r), max(hr, r)
				lg, hg = min(lg, g), max(hg, g)
				lb, hb = min(lb, b), max(hb, b)
			end
			local c0 = floor(hr / 8) * 2048 + floor(hg / 4) * 32 + floor(hb / 8)
			local c1 = floor(lr / 8) * 2048 + floor(lg / 4) * 32 + floor(lb / 8)
			if c0 < c1 then c0, c1 = c1, c0 end
			local r0, g0, b0 = rgb565(c0)
			local r1, g1, b1 = rgb565(c1)
			local pr = { r0, r1, floor((2 * r0 + r1) / 3), floor((r0 + 2 * r1) / 3) }
			local pg = { g0, g1, floor((2 * g0 + g1) / 3), floor((g0 + 2 * g1) / 3) }
			local pb = { b0, b1, floor((2 * b0 + b1) / 3), floor((b0 + 2 * b1) / 3) }
			local bits = 0
			for i = 0, 15 do
				local best, dist = 0, math.huge
				for k = 1, 4 do
					local d = (rs[i] - pr[k]) ^ 2 + (gs[i] - pg[k]) ^ 2 + (bs[i] - pb[k]) ^ 2
					if d < dist then best, dist = k - 1, d end
				end
				bits = bits + best * 4 ^ i
			end
			n = n + 1
			blocks[n] = "\255\255\0\0\0\0\0\0" .. pack(c0, 2) .. pack(c1, 2) .. pack(bits, 4)
		end
	end

	local body = table.concat(blocks)
	return "DDS " .. pack(124, 4) .. pack(0x81007, 4) .. pack(h, 4) .. pack(w, 4) .. pack(#body, 4) .. pack(0, 8)
		.. string.rep("\0", 44) .. pack(32, 4) .. pack(4, 4) .. "DXT5" .. string.rep("\0", 20)
		.. pack(0x1000, 4) .. string.rep("\0", 16) .. body
end

local function load(path, max_size)
	local data = read(path)
	if not data then fail("cannot read " .. tostring(path)) end
	return CSR.decode_dds(data, max_size)
end

local function resize(img, size)
	local sw, sh, sp, px = img.w, img.h, img.px, {}
	for y = 0, size - 1 do
		local fy = (y + 0.5) * sh / size - 0.5
		local ty = fy - floor(fy)
		local ya, yb = min(max(floor(fy), 0), sh - 1), min(max(floor(fy) + 1, 0), sh - 1)
		for x = 0, size - 1 do
			local fx = (x + 0.5) * sw / size - 0.5
			local tx = fx - floor(fx)
			local xa, xb = min(max(floor(fx), 0), sw - 1), min(max(floor(fx) + 1, 0), sw - 1)
			local p00, p10, p01, p11 = sp[ya * sw + xa + 1], sp[ya * sw + xb + 1], sp[yb * sw + xa + 1], sp[yb * sw + xb + 1]
			local w00, w10, w01, w11 = (1 - tx) * (1 - ty), tx * (1 - ty), (1 - tx) * ty, tx * ty
			local out = 0
			for _, c in ipairs({ 65536, 256, 1 }) do
				local v = floor(p00 / c) % 256 * w00 + floor(p10 / c) % 256 * w10 + floor(p01 / c) % 256 * w01 + floor(p11 / c) % 256 * w11
				out = out * 256 + floor(v + 0.5)
			end
			px[y * size + x + 1] = out
		end
	end
	return { w = size, h = size, px = px }
end

local function soften(img)
	local size, px = img.w, img.px
	local r = floor(floor(CSR.BLEND_WIDTH * size / 512) / 2)
	for _, horizontal in ipairs({ true, false }) do
		for a = 0, size - 1 do
			local line = {}
			for c = 0, size - 1 do
				line[c + 1] = horizontal and px[a * size + c + 1] or px[c * size + a + 1]
			end
			for c = 0, size - 1 do
				if c < r or c >= size - r then
					local sr, sg, sb = 0, 0, 0
					for d = -r, r do
						local p = line[(c + d) % size + 1]
						sr, sg, sb = sr + floor(p / 65536), sg + floor(p / 256) % 256, sb + p % 256
					end
					local n = 2 * r + 1
					local v = floor(sr / n + 0.5) * 65536 + floor(sg / n + 0.5) * 256 + floor(sb / n + 0.5)
					if horizontal then px[a * size + c + 1] = v else px[c * size + a + 1] = v end
				end
			end
		end
	end
end

function CSR.glow_color_file(path)
	local data = read(path)
	local img = CSR.decode_dds(data or "", 64)
	local R, G, B = 0, 0, 0
	for _, p in pairs(img.px) do
		local r, g, b = floor(p / 65536), floor(p / 256) % 256, p % 256
		local weight = max(r, g, b)
		R, G, B = R + r * weight, G + g * weight, B + b * weight
	end
	local top = max(R, G, B)
	if top <= 0 then return nil end
	return { floor(R / top * 100 + 0.5) / 100, floor(G / top * 100 + 0.5) / 100, floor(B / top * 100 + 0.5) / 100 }
end

function CSR:names(skin)
	local key = (tostring(skin.id):lower():gsub("[^%w_]", "_"))
	return {
		key = key,
		id = "imported_" .. key,
		name = skin.label or ("Imp. " .. tostring(skin.id)),
		base_name = OUTPUT_DB .. key .. "_df",
		glow_name = OUTPUT_DB .. key .. "_il",
		base_file = OUTPUT_DIR .. key .. "_df.texture",
		glow_file = OUTPUT_DIR .. key .. "_il.texture",
	}
end

function CSR:generate(skin)
	local names = self:names(skin)
	local s, size = self.settings, self.TILE_SIZE
	local diffuse, glow

	if skin.df and skin.il then
		diffuse, glow = resize(load(skin.df, size), size), resize(load(skin.il, size), size)
	else
		if skin.image then
			diffuse = resize(load(skin.image, s.max_size), size)
		else
			local pattern = resize(load(skin.pattern, s.max_size), size)
			local gradient = resize(load(skin.gradient), size)
			diffuse = { w = size, h = size, px = {} }
			for i = 1, size * size do
				local g, l = gradient.px[i], luma(pattern.px[i])
				diffuse.px[i] = floor((floor(g / 65536) * l + 127) / 255) * 65536
					+ floor((floor(g / 256) % 256 * l + 127) / 255) * 256
					+ floor(((g % 256) * l + 127) / 255)
			end
		end
		local mean = 0
		for i = 1, size * size do mean = mean + luma(diffuse.px[i]) end
		mean = floor(mean / (size * size) + 0.5)
		glow = { w = size, h = size, px = {} }
		for i = 1, size * size do
			local out = 0
			for _, c in ipairs({ 65536, 256, 1 }) do
				local v = floor(min(255, max(0, mean + (floor(diffuse.px[i] / c) % 256 - mean) * s.glow_contrast)))
				v = floor(min(255, v * s.glow_brightness))
				out = out * 256 + floor(v * s.glow_scale + 0.5)
			end
			glow.px[i] = out
		end
	end

	soften(diffuse)
	soften(glow)
	for path, img in pairs({ [names.base_file] = diffuse, [names.glow_file] = glow }) do
		local f = io.open(path, "wb")
		if not f then fail("could not write " .. path) end
		f:write(CSR.encode_dds(img))
		f:close()
	end
	return names
end

local function attr(s, name)
	return (" " .. s):match("%s" .. name .. '%s*=%s*"([^"]*)"')
end

local function locate(dir, name, depth)
	if dir:sub(-1) ~= "/" then dir = dir .. "/" end
	if not file.DirectoryExists(dir) then return nil end
	for _, f in ipairs(file.GetFiles(dir) or {}) do
		if f == name .. ".dds" or f == name .. ".texture" then return dir .. f end
	end
	if depth > 0 then
		for _, sub in ipairs(file.GetDirectories(dir) or {}) do
			local hit = locate(dir .. sub, name, depth - 1)
			if hit then return hit end
		end
	end
end

function CSR:find_color_skins()
	local found, seen = {}, {}

	for _, root in ipairs(self.settings.scan_dirs) do
		for _, mod in ipairs(file.GetDirectories(root) or {}) do
			local dir = root .. mod .. "/"
			local xml = read(dir .. "main.xml")
			if xml then
				xml = xml:gsub("<!%-%-.-%-%->", "")
				local folders = {}
				for attrs, body in xml:gmatch("<AddFiles%s*([^>]*)>(.-)</AddFiles>") do
					for tag, a in body:gmatch("<(%w+)%s+([^>]-)/?>") do
						if (tag == "texture" or tag == "dds") and attr(a, "path") then
							folders[attr(a, "path")] = (attr(attrs, "directory") or ""):gsub("\\", "/")
						end
					end
				end
				for attrs, body in xml:gmatch("<WeaponSkin%s+([^>]*)>(.-)</WeaponSkin>") do
					local data = body:match("<color_skin_data%s+([^>]-)/?>")
					local id = attr(attrs, "id")
					local pattern = data and attr(data, "pattern_default")
					local gradient = data and attr(data, "gradient_default")
					if attr(attrs, "is_a_color_skin") == "true" and pattern and gradient and not seen[id] then
						local pattern_file = locate(dir .. (folders[pattern] or ""), pattern:match("[^/]+$"), 0) or locate(dir, pattern:match("[^/]+$"), 4)
						local gradient_file = locate(dir .. (folders[gradient] or ""), gradient:match("[^/]+$"), 0) or locate(dir, gradient:match("[^/]+$"), 4)
						if pattern_file and gradient_file then
							seen[id] = true
							found[#found + 1] = { id = id, pattern = pattern_file, gradient = gradient_file, mod = mod }
						else
							log("[Scrolling Textures] skipped " .. tostring(id) .. ": pattern or gradient not found in " .. mod)
						end
					end
				end
			end
		end
	end

	local files = file.DirectoryExists(INPUT_DIR) and file.GetFiles(INPUT_DIR) or {}
	table.sort(files)
	local entries, order = {}, {}
	for _, f in ipairs(files) do
		local base, ext = f:match("^(.+)%.(%w+)$")
		if base and (ext:lower() == "dds" or ext:lower() == "texture") then
			local name, role = base, "image"
			for _, r in ipairs({ "pattern", "gradient", "df", "il" }) do
				if base:lower():sub(-#r - 1) == "_" .. r and #base > #r + 1 then
					name, role = base:sub(1, -#r - 2), r
				end
			end
			if not entries[name] then
				entries[name] = {}
				order[#order + 1] = name
			end
			entries[name][role] = INPUT_DIR .. f
		end
	end

	for _, name in ipairs(order) do
		local e = entries[name]
		local complete = (e.image and not (e.pattern or e.gradient or e.df or e.il))
			or (e.pattern and e.gradient and not (e.image or e.df or e.il))
			or (e.df and e.il and not (e.image or e.pattern or e.gradient))
		local skin = { id = "input_" .. name, label = "Input: " .. name, mod = "input", image = e.image, pattern = e.pattern, gradient = e.gradient, df = e.df, il = e.il }
		local names = self:names(skin)
		local base, glow = io.open(names.base_file, "rb"), io.open(names.glow_file, "rb")
		if base then base:close() end
		if glow then glow:close() end
		if not complete then
			log("[Scrolling Textures] skipped input '" .. name .. "': needs one image, or _pattern + _gradient, or _df + _il")
		elseif not (base and glow) then
			found[#found + 1] = skin
		end
	end

	return found
end
