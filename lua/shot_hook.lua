Hooks:PostHook(RaycastWeaponBase, "fire", "ScrollingTextures_shot", function(self)
	local T = _G.ScrollingTexturesSettings
	if T then T:on_shot(self) end
end)