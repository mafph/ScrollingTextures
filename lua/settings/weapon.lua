dofile(ModPath .. "lua/settings/core.lua")
dofile(ModPath .. "lua/settings/reactive.lua")
dofile(ModPath .. "lua/settings/light.lua")
local T = _G.ScrollingTexturesSettings

if not T._fire_wrapped and type(RaycastWeaponBase) == "table" and type(RaycastWeaponBase.fire) == "function" then
	T._fire_wrapped = true
	local fire = RaycastWeaponBase.fire
	function RaycastWeaponBase:fire(...)
		local result = fire(self, ...)
		if result then
			T:on_shot(self)
		end
		return result
	end
	end
