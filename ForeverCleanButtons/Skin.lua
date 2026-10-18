local ADDON, ns = ...

-- The look: every button gets a square backdrop (border colour outside, a
-- dark fill inside) and its picture is fitted into that square without the
-- game's rounded mask and frame art.
--
-- Three kinds of buttons are handled:
--   action  action, pet, stance and extra buttons (ActionButtonTemplate)
--   bag     the backpack and bag slots
--   micro   the small menu buttons (character, spellbook, quest log ...)
--
-- Everything the skin changes on a Blizzard region is remembered first, so
-- turning the addon or a part of it off puts the region back as it was. The
-- stock UI re-applies its rounded art on some updates; those calls are
-- hooked and the skin is laid on again right after them.

local OUTLINE = "Interface\\AddOns\\" .. ADDON .. "\\media\\outline"
local GOLD = { 1, 0.82, 0 }
local COLORS = {
	black = { 0, 0, 0 },
	graphite = { 0.22, 0.23, 0.26 },
	gold = { 0.92, 0.74, 0.38 },
}
local MICRO_FILL = { 0.05, 0.05, 0.06, 0.92 }

local ACTION_BUTTONS = {
	{ "ActionButton", 12 },
	{ "MultiBarBottomLeftButton", 12 },
	{ "MultiBarBottomRightButton", 12 },
	{ "MultiBarRightButton", 12 },
	{ "MultiBarLeftButton", 12 },
	{ "MultiBar5Button", 12 },
	{ "MultiBar6Button", 12 },
	{ "MultiBar7Button", 12 },
	{ "PetActionButton", 10 },
	{ "StanceButton", 10 },
	{ "PossessButton", 2 },
	{ "ExtraActionButton", 1 },
}
local BAG_BUTTONS = {
	"MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton",
}
local MICRO_BUTTONS = {
	"CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton", "SpellbookMicroButton",
	"TalentMicroButton", "AchievementMicroButton", "QuestLogMicroButton", "HousingMicroButton",
	"GuildMicroButton", "SocialsMicroButton", "LFDMicroButton", "LFGMicroButton", "PVPMicroButton",
	"CollectionsMicroButton", "EJMicroButton", "WorldMapMicroButton", "LegacyMicroButton",
	"StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}

local kinds = {} -- [button] = "action" | "bag" | "micro"
local parts = {} -- [button] = { outer, inner, saved = {}, skinned, mask, masked }

-- Settings ---------------------------------------------------------------------

local function DB() return ns.DB() end

local function Active(button)
	local db = DB()
	if not db or not db.enabled then return false end
	local kind = kinds[button]
	if kind == "bag" then return db.bags end
	if kind == "micro" then return db.micro end
	return kind ~= nil
end

function ns.BorderColor()
	local key = DB().color
	if key == "class" then
		local _, class = UnitClass("player")
		local c = class and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or RAID_CLASS_COLORS[class])
		if c then return { c.r, c.g, c.b } end
	end
	return COLORS[key] or COLORS.black
end

function ns.Crop()
	local z = (DB().zoom or 0) / 100
	return z, 1 - z, z, 1 - z
end

-- One screen pixel in the frame's own units, at any UI and bar scale.
function ns.Pixel(frame)
	local factor
	if PixelUtil and PixelUtil.GetPixelToUIUnitFactor then
		factor = PixelUtil.GetPixelToUIUnitFactor()
	else
		factor = 768 / select(2, GetPhysicalScreenSize())
	end
	return factor / frame:GetEffectiveScale()
end

-- Remember and restore ---------------------------------------------------------

-- keepArt: the region's picture changes on its own (icons, the portrait), so
-- only its placement and texture coordinates are put back.
local function Save(button, r, keepArt)
	local saved = parts[button].saved
	if not r or saved[r] then return end
	local s = { alpha = r:GetAlpha(), points = {}, keepArt = keepArt }
	for i = 1, r:GetNumPoints() do s.points[i] = { r:GetPoint(i) } end
	s.width, s.height = r:GetSize()
	if r.GetTexCoord then s.coords = { r:GetTexCoord() } end
	if not keepArt and r.GetAtlas then
		s.atlas = r:GetAtlas()
		if not s.atlas then s.texture = r:GetTexture() end
	end
	if r.GetBlendMode then s.blend = r:GetBlendMode() end
	-- the game tints an icon on its own (unusable, out of mana) and the skin
	-- never does, so its colour and alpha are left to the game
	if keepArt then s.alpha = nil elseif r.GetVertexColor then s.color = { r:GetVertexColor() } end
	saved[r] = s
end

local function Restore(r, s)
	if s.atlas then
		r:SetAtlas(s.atlas)
	elseif s.texture then
		r:SetTexture(s.texture)
	end
	if s.coords and not s.atlas then r:SetTexCoord(unpack(s.coords)) end
	if s.blend then r:SetBlendMode(s.blend) end
	if s.color then r:SetVertexColor(unpack(s.color)) end
	if s.alpha then r:SetAlpha(s.alpha) end
	r:ClearAllPoints()
	for _, p in ipairs(s.points) do r:SetPoint(unpack(p)) end
	if #s.points < 2 then r:SetSize(s.width, s.height) end
end

local function Fit(button, r, anchor)
	if not r then return end
	Save(button, r)
	r:ClearAllPoints()
	r:SetAllPoints(anchor)
end

local function Hide(button, r)
	if not r then return end
	Save(button, r)
	r:SetAlpha(0)
end

-- A region the stock UI masks; the mask is taken off while the skin is on.
local function Unmask(button, r, mask)
	local p = parts[button]
	if r and mask and not p.masked then
		r:RemoveMaskTexture(mask)
		p.mask, p.maskTarget, p.masked = mask, r, true
	end
end

-- Backdrop ---------------------------------------------------------------------

local function Parts(button)
	local p = parts[button]
	if not p then
		p = { saved = {} }
		p.outer = button:CreateTexture(nil, "BACKGROUND", nil, -8)
		p.inner = button:CreateTexture(nil, "BACKGROUND", nil, -7)
		parts[button] = p
	end
	return p
end

local function Layout(button)
	local p = parts[button]
	local db = DB()
	local edge = (db.border or 0) * ns.Pixel(button)

	p.outer:ClearAllPoints()
	if kinds[button] == "micro" then
		-- micro buttons are taller than wide; the picture sits in the middle
		local w = button:GetWidth()
		p.outer:SetPoint("CENTER")
		p.outer:SetSize(w, w)
	else
		p.outer:SetAllPoints(button)
	end
	p.inner:ClearAllPoints()
	p.inner:SetPoint("TOPLEFT", p.outer, "TOPLEFT", edge, -edge)
	p.inner:SetPoint("BOTTOMRIGHT", p.outer, "BOTTOMRIGHT", -edge, edge)

	local c = ns.BorderColor()
	p.outer:SetColorTexture(c[1], c[2], c[3], 1)
	local fill = kinds[button] == "micro" and MICRO_FILL or COLORS.black
	p.inner:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
	p.outer:Show()
	p.inner:Show()
end

local function Outline(button, r, anchor, color)
	if not r then return end
	Save(button, r)
	r:SetTexture(OUTLINE)
	if color then r:SetVertexColor(color[1], color[2], color[3]) end
	r:SetBlendMode("BLEND")
	Fit(button, r, anchor)
end

local function Pushed(button, inner)
	local pushed = button:GetPushedTexture()
	if not pushed then return end
	Save(button, pushed)
	pushed:SetColorTexture(0, 0, 0, 0.4)
	Fit(button, pushed, inner)
end

local function Highlight(button, inner)
	local hl = button:GetHighlightTexture()
	if not hl then return end
	Save(button, hl)
	hl:SetColorTexture(1, 1, 1, 0.15)
	hl:SetBlendMode("ADD")
	Fit(button, hl, inner)
end

-- Styles -------------------------------------------------------------------------

local STYLE = {}

function STYLE.action(button)
	local inner, icon = parts[button].inner, button.icon

	Unmask(button, icon, button.IconMask)
	Save(button, icon, true)
	icon:SetTexCoord(ns.Crop())
	Fit(button, icon, inner)

	Hide(button, button.SlotArt)
	Hide(button, button.SlotBackground)
	Hide(button, button:GetNormalTexture())
	Pushed(button, inner)
	Highlight(button, inner)
	Outline(button, button:GetCheckedTexture(), inner, GOLD)
	Outline(button, button.Border, inner) -- equipped items; the stock UI tints it green
	Outline(button, button.NewActionTexture, inner, GOLD)
	Outline(button, button.SpellHighlightTexture, inner, GOLD)

	if button.Flash then
		Save(button, button.Flash)
		button.Flash:SetColorTexture(1, 0.1, 0.1, 0.35)
		Fit(button, button.Flash, inner)
	end

	Fit(button, button.cooldown, inner)
	Fit(button, button.lossOfControlCooldown, inner)
	Fit(button, button.chargeCooldown, inner)
end

-- Bag pictures, the empty slot placeholder included, are cropped like any
-- icon.
local function BagIcon(button)
	button.icon:SetTexCoord(ns.Crop())
end

function STYLE.bag(button)
	local inner, icon = parts[button].inner, button.icon

	Unmask(button, icon, button.SquareMask or button.IconMask or button.CircleMask)
	Save(button, icon, true)
	BagIcon(button)
	Fit(button, icon, inner)

	Hide(button, button:GetNormalTexture())
	Hide(button, button.IconBorder)
	Pushed(button, inner)
	Highlight(button, inner)
	Outline(button, button.SlotHighlightTexture, inner, GOLD)
end

-- Micro button pictures are taller than wide; cut the middle square out of
-- the atlas so they fill the square without stretching. On an atlas texture
-- the game reads texture coordinates inside the atlas piece (0-1 is the
-- whole picture), not inside the big texture file.
local function SquareAtlas(tex)
	local atlas = tex and tex:GetAtlas()
	local info = atlas and C_Texture.GetAtlasInfo(atlas)
	if not info then return end
	local w, h = info.width or 1, info.height or 1
	local l, r, t, b = 0, 1, 0, 1
	if h > w then
		local d = (1 - w / h) / 2
		t, b = d, 1 - d
	elseif w > h then
		local d = (1 - h / w) / 2
		l, r = d, 1 - d
	end
	tex:SetTexCoord(l, r, t, b)
end

local MICRO_STATES = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }

local function Portrait(button)
	local portrait = button.Portrait
	if not portrait then return end
	Unmask(button, portrait, button.PortraitMask)
	Save(button, portrait, true)
	portrait:SetTexCoord(0.15, 0.85, 0.15, 0.85)
	Fit(button, portrait, parts[button].inner)
end

function STYLE.micro(button)
	local inner = parts[button].inner

	Hide(button, button.Background)
	Hide(button, button.PushedBackground)
	Hide(button, button.Shadow)
	Hide(button, button.PushedShadow)

	for _, getter in ipairs(MICRO_STATES) do
		local tex = button[getter](button)
		if tex then
			Save(button, tex)
			SquareAtlas(tex)
			Fit(button, tex, inner)
		end
	end
	if button.FlashContent then
		Save(button, button.FlashContent)
		SquareAtlas(button.FlashContent)
		Fit(button, button.FlashContent, inner)
	end
	Outline(button, button.FlashBorder, inner, GOLD)
	Portrait(button)
end

-- Skin / unskin --------------------------------------------------------------------

local function Skinned(button)
	local p = parts[button]
	return p and p.skinned and Active(button)
end

local function Unskin(button)
	local p = parts[button]
	if not p or not p.skinned then return end
	p.skinned = false
	for r, s in pairs(p.saved) do Restore(r, s) end
	wipe(p.saved)
	if p.masked then
		p.maskTarget:AddMaskTexture(p.mask)
		p.masked = false
	end
	p.outer:Hide()
	p.inner:Hide()

	-- The snapshot is from when the skin went on; the stock art may have changed
	-- since (Edit Mode's "Hide Bar Art"). Let the game lay its current art again.
	if kinds[button] == "action" and type(button.UpdateButtonArt) == "function" then
		button:UpdateButtonArt()
	elseif kinds[button] == "bag" and type(button.UpdateTextures) == "function" then
		button:UpdateTextures()
	end

	local icon = button.icon
	if kinds[button] == "bag" and icon then
		icon:SetAlpha(1)
		local atlas = icon:GetAtlas()
		if atlas then
			icon:SetAtlas(atlas)
		else
			icon:SetTexCoord(0, 1, 0, 1)
		end
	end
end

local hooked = {}

local function Hook(button)
	if hooked[button] then return end
	hooked[button] = true
	local kind = kinds[button]
	local function Again()
		if Skinned(button) then STYLE[kind](button) end
	end

	if kind == "action" then
		if button.UpdateButtonArt then hooksecurefunc(button, "UpdateButtonArt", Again) end
	elseif kind == "bag" then
		if button.UpdateTextures then hooksecurefunc(button, "UpdateTextures", Again) end
		local function Icon()
			if Skinned(button) then BagIcon(button) end
		end
		hooksecurefunc(button.icon, "SetTexture", Icon)
		hooksecurefunc(button.icon, "SetAtlas", Icon)
	elseif kind == "micro" then
		for _, method in ipairs({ "SetNormalAtlas", "SetPushedAtlas", "SetDisabledAtlas", "SetHighlightAtlas" }) do
			hooksecurefunc(button, method, Again)
		end
		if button.Portrait then
			-- pressing the character button moves its portrait about
			if button.SetPushed then hooksecurefunc(button, "SetPushed", Again) end
			if button.SetNormal then hooksecurefunc(button, "SetNormal", Again) end
		end
	end
end

local function Skin(button)
	if not Active(button) then
		Unskin(button)
		return
	end
	local p = Parts(button)
	p.skinned = true
	Layout(button)
	STYLE[kinds[button]](button)
	Hook(button)
end

local function KindOf(button)
	if type(button) ~= "table" or not button.GetObjectType then return end
	if button.IsForbidden and button:IsForbidden() then return end
	if button.icon and button.IconMask and button.SlotArt then return "action" end
	if button.Background and button.PushedBackground then return "micro" end
	if button.icon and button.UpdateTextures and (button.SquareMask or button.IconMask or button.CircleMask) then
		return "bag"
	end
end

-- Other parts of the addon (Auras.lua) want to know every button too.
local registerListeners = {}

function ns.OnRegister(fn)
	registerListeners[#registerListeners + 1] = fn
	for button, kind in pairs(kinds) do fn(button, kind) end
end

local function Register(button)
	if kinds[button] then return end
	local kind = KindOf(button)
	if not kind then return end
	kinds[button] = kind
	Skin(button)
	for _, fn in ipairs(registerListeners) do fn(button, kind) end
end
ns.Register = Register

function ns.ApplyAll()
	for button in pairs(kinds) do Skin(button) end
end

-- Finding the buttons ------------------------------------------------------------------

local function RegisterStock()
	for _, spec in ipairs(ACTION_BUTTONS) do
		for i = 1, spec[2] do Register(_G[spec[1] .. i]) end
	end
	for _, name in ipairs(BAG_BUTTONS) do Register(_G[name]) end
	for _, name in ipairs(MICRO_BUTTONS) do Register(_G[name]) end
end

-- Dominos passes every button it builds through its ButtonThemer module.
-- Dominos loads first (OptionalDeps), so the hook is in place before it
-- builds its bars at login.
-- Every hook checks the method is there first: Dominos updates weekly, and a
-- renamed method must not stop this file from loading.
local function HookIf(target, method, fn)
	if type(target) == "table" and type(target[method]) == "function" then
		hooksecurefunc(target, method, fn)
	end
end

local Dominos = _G.Dominos
if type(Dominos) == "table" and type(Dominos.GetModule) == "function" then
	local ok, themer = pcall(Dominos.GetModule, Dominos, "ButtonThemer", true)
	if ok then
		HookIf(themer, "Register", function(_, button) Register(button) end)
		HookIf(themer, "Reskin", function() ns.ApplyAll() end)
	end
	-- a bar's scale changes how many units one screen pixel is
	HookIf(Dominos.Frame, "SetFrameScale", function() ns.ApplyAll() end)
end

function ns.InitSkin()
	-- after Dominos and the stock bars have set themselves up
	C_Timer.After(0, RegisterStock)

	hooksecurefunc("SetPortraitTexture", function(tex)
		local button = CharacterMicroButton
		if button and tex == button.Portrait and Skinned(button) then Portrait(button) end
	end)

	-- Edit Mode's icon and menu sizes scale the stock bars: a border keeps one pixel
	for _, name in ipairs({ "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
		"MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar",
		"MicroMenuContainer", "BagsBar" }) do
		HookIf(_G[name], "UpdateSystemSettingIconSize", function() ns.ApplyAll() end)
		HookIf(_G[name], "UpdateSystemSettingSize", function() ns.ApplyAll() end)
	end

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("UI_SCALE_CHANGED")
	watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
	watcher:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	watcher:SetScript("OnEvent", function() ns.ApplyAll() end)
end
