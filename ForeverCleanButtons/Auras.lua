local _, ns = ...

-- Buff timers: a buff you cast on yourself shows how long it has left on the
-- button of the spell that gives it, so a 50-minute blessing is not recast
-- for nothing.
--
-- Forever hides aura data from addons in combat (the values come back as
-- secrets). So buffs are read only out of combat; in combat the last known
-- expiration keeps counting down, and the list is read again the moment the
-- fight ends. A buff matches a button by spell ID first, then by name, so
-- another rank of the same spell finds it too.

local UPDATE = 1 -- seconds between text updates while a timer is shown

local texts = {}  -- [button] = FontString
local byId = {}   -- [spellId] = expirationTime
local byName = {} -- [spell name] = expirationTime
local ticker

local function DB() return ns.DB() end

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local function SpellName(spellId)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellId) end
	if GetSpellInfo then return (GetSpellInfo(spellId)) end
end

-- Reading -----------------------------------------------------------------------

local function Scan()
	if InCombatLockdown() then return false end
	wipe(byId)
	wipe(byName)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return true end
	for i = 1, 255 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or not aura then break end
		local source, expires, id, name = aura.sourceUnit, aura.expirationTime, aura.spellId, aura.name
		if not (Secret(source) or Secret(expires) or Secret(id) or Secret(name))
			and source == "player" and expires and expires > 0 then
			if id then byId[id] = expires end
			if name then byName[name] = expires end
		end
	end
	return true
end

-- The spell a button casts: a spell straight away, or the spell a macro uses.
local function ButtonSpell(button)
	local action
	if button.CalculateAction then
		action = button:CalculateAction()
	end
	action = action or button.action or button:GetAttribute("action")
	if type(action) ~= "number" or action <= 0 then return end
	local kind, id, subType = GetActionInfo(action)
	if kind == "spell" then return id end
	if kind == "macro" then
		-- newer clients hand the macro's spell ID back directly
		if subType == "spell" then return id end
		if GetMacroSpell then return GetMacroSpell(id) end
	end
end

local function Expires(button)
	local spell = ButtonSpell(button)
	if not spell then return end
	if byId[spell] then return byId[spell] end
	local name = SpellName(spell)
	return name and byName[name]
end

-- Showing ----------------------------------------------------------------------------

function ns.FormatAuraTime(left)
	if left >= 3600 then return ("%dh"):format(math.ceil(left / 3600)) end
	if left >= 60 then return ("%dm"):format(math.ceil(left / 60)) end
	return ("%ds"):format(math.ceil(left))
end

local function Text(button)
	local fs = texts[button]
	if not fs then
		-- in a frame of its own, above the icon, the cooldown swipe and the hotkey
		local holder = CreateFrame("Frame", nil, button)
		holder:SetAllPoints(button)
		holder:SetFrameLevel(button:GetFrameLevel() + 5)
		fs = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		local font, size = fs:GetFont()
		if font then fs:SetFont(font, size or 11, "OUTLINE") end
		fs:SetTextColor(1, 1, 1)
		-- top left: the hotkey sits top right, the stack count bottom right and a
		-- macro's name bottom centre
		fs:SetPoint("TOPLEFT", 2, -2)
		fs:SetJustifyH("LEFT")
		texts[button] = fs
	end
	return fs
end

local Update

local function StartTicker()
	if not ticker then ticker = C_Timer.NewTicker(UPDATE, function() Update() end) end
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- Puts the right text on every button; keeps the ticker only while one shows.
Update = function()
	local on = DB() and DB().auraTimers
	local now = GetTime()
	local any = false
	for button, fs in pairs(texts) do
		local expires = on and button:IsVisible() and Expires(button)
		local left = expires and expires - now
		if left and left > 0 then
			fs:SetText(ns.FormatAuraTime(left))
			fs:Show()
			any = true
		else
			fs:Hide()
		end
	end
	if any then StartTicker() else StopTicker() end
end
ns.UpdateAuraTimers = Update

-- Many changes come at once (a Dominos page turn touches every button):
-- collect them and update once on the next frame.
local queued = false
local function Queue()
	if queued then return end
	queued = true
	C_Timer.After(0, function()
		queued = false
		Update()
	end)
end

local function Refresh()
	Scan()
	Queue()
end

-- Buttons --------------------------------------------------------------------------------

ns.OnRegister(function(button, kind)
	if kind ~= "action" then return end
	Text(button):Hide()
	-- paging (Dominos, stances, the default bars) changes the button's action
	button:HookScript("OnAttributeChanged", function(_, name)
		if name == "action" then Queue() end
	end)
	Queue()
end)

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
	if event == "UNIT_AURA" then
		if InCombatLockdown() then return end
		Refresh()
	elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
		Refresh()
	else
		Queue()
	end
end)
frame:RegisterUnitEvent("UNIT_AURA", "player")
for _, event in ipairs({
	"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
	"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
}) do
	frame:RegisterEvent(event)
end

ns.OnChange(Update)
