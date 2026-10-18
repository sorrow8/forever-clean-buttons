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
--
-- Recasting a buff in combat can't be read either, but the cast itself can:
-- when you cast one of your own buffs on yourself, its timer starts again from
-- the full duration seen the last time it was read.

local FAST, SLOW = 0.2, 1 -- seconds between updates: while seconds show (a new one on time), or only minutes
local TEXT_SIZE, TEXT_MIN, TEXT_MAX = 0.45, 12, 22 -- font size: share of the button height, limits

local texts = {}  -- [button] = FontString
local byId = {}   -- [spellId] = expirationTime
local byName = {} -- [spell name] = expirationTime
local durationById = {}   -- [spellId] = full duration, kept for recasts in combat
local durationByName = {} -- [spell name] = full duration
local sentTo = {}         -- [castGUID] = who the cast was aimed at
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

-- The game can hide aura data out of combat too (a battleground, an arena, a
-- keystone): then the last known timers stay and keep counting down.
local function Scan()
	if InCombatLockdown() then return false end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
	local ids, names = {}, {}
	for i = 1, 255 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or not aura then break end
		local source, expires, id, name, duration = aura.sourceUnit, aura.expirationTime, aura.spellId, aura.name, aura.duration
		if Secret(source) or Secret(expires) or Secret(id) or Secret(name) or Secret(duration) then return false end
		if source == "player" and expires and expires > 0 then
			if id then ids[id] = expires end
			if name then names[name] = expires end
			if duration and duration > 0 then
				if id then durationById[id] = duration end
				if name then durationByName[name] = duration end
			end
		end
	end
	byId, byName = ids, names
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

-- By spell ID or by name, whichever is later: a recast of another rank in
-- combat only updates the name.
local function Expires(button)
	local spell = ButtonSpell(button)
	if not spell then return end
	local name = SpellName(spell)
	if Secret(name) then name = nil end
	local a, b = byId[spell], name and byName[name]
	if a and b then return math.max(a, b) end
	return a or b
end

-- Showing ----------------------------------------------------------------------------

-- As on the game's own buff icons: seconds up to 90 s, minutes up to 90 m,
-- seconds round down, minutes and hours up.
function ns.FormatAuraTime(left)
	if left >= 5400 then return ("%dh"):format(math.ceil(left / 3600)) end
	if left >= 90 then return ("%dm"):format(math.ceil(left / 60)) end
	return ("%ds"):format(math.floor(left))
end

local function Text(button)
	local fs = texts[button]
	if not fs then
		-- in a frame of its own, above the icon, the cooldown swipe and the hotkey
		local holder = CreateFrame("Frame", nil, button)
		holder:SetAllPoints(button)
		holder:SetFrameLevel(button:GetFrameLevel() + 5)
		fs = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		fs:SetTextColor(1, 1, 1)
		-- in the middle and big, so it reads at a glance; the size follows the button
		fs:SetPoint("CENTER", 0, 0)
		fs:SetJustifyH("CENTER")
		local font = fs:GetFont()
		local function Resize()
			local size = math.floor((button:GetHeight() or 36) * TEXT_SIZE + 0.5)
			size = math.max(TEXT_MIN, math.min(TEXT_MAX, size))
			if font then fs:SetFont(font, size, "OUTLINE") end
		end
		Resize()
		holder:SetScript("OnSizeChanged", Resize)
		texts[button] = fs
	end
	return fs
end

local Update
local tickEvery
local shownText = {} -- [FontString] = text it shows, so it is only set on a change

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	tickEvery = nil
end

local function StartTicker(every)
	if ticker and tickEvery == every then return end
	StopTicker()
	tickEvery = every
	ticker = C_Timer.NewTicker(every, function() Update() end)
end

-- Puts the right text on every button; keeps the ticker only while one shows.
Update = function()
	local on = DB() and DB().auraTimers
	local now = GetTime()
	local soonest
	for button, fs in pairs(texts) do
		local expires = on and button:IsVisible() and Expires(button)
		local left = expires and expires - now
		if left and left > 0 then
			local text = ns.FormatAuraTime(left)
			if shownText[fs] ~= text then
				fs:SetText(text)
				shownText[fs] = text
			end
			fs:Show()
			soonest = math.min(soonest or left, left)
		else
			fs:Hide()
		end
	end
	if soonest then StartTicker(soonest < 90 and FAST or SLOW) else StopTicker() end
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

-- Recasts -------------------------------------------------------------------------------

-- Whether a cast went to you: no target (seals, self-only buffs), your own
-- name, or, when the name can't be read, no friendly target but you.
local function AtSelf(target)
	if Secret(target) then
		return not (UnitExists("target") and UnitIsFriend("player", "target") and not UnitIsUnit("target", "player"))
	end
	if target == nil or target == "" then return true end
	-- the name may come with the realm ("Name-Realm")
	return target == UnitName("player") or target:match("^(.-)%-") == UnitName("player")
end

-- The last casts and what became of them, for /fcb debug.
local castLog = {}
local function Log(...)
	table.insert(castLog, 1, strjoin(" ", tostringall(...)))
	castLog[6] = nil
end

local function Recast(castGUID, spellId)
	local target = sentTo[castGUID]
	sentTo[castGUID] = nil
	if Secret(spellId) then return Log("secret spell") end
	local name = SpellName(spellId)
	if Secret(name) then name = nil end
	-- only your own buffs have a known duration; anything else stops here
	local duration = durationById[spellId] or (name and durationByName[name])
	local shownTarget = Secret(target) and "<secret>" or target
	if not duration then return Log(spellId, name, "to", shownTarget, "- no known duration") end
	if not AtSelf(target) then return Log(spellId, name, "to", shownTarget, "- not at you") end
	Log(spellId, name, "to", shownTarget, "- restarted at", duration)
	local expires = GetTime() + duration
	byId[spellId] = expires
	if name then byName[name] = expires end
	Queue()
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, unit, a, b, c)
	if event == "UNIT_SPELLCAST_SENT" then
		-- unit, target, castGUID, spellId
		if not Secret(b) and b then sentTo[b] = a end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		-- unit, castGUID, spellId
		if not Secret(a) and a and b then Recast(a, b) end
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		if not Secret(a) and a then sentTo[a] = nil end
	elseif event == "UNIT_AURA" then
		if InCombatLockdown() then return end
		Refresh()
	elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
		wipe(sentTo) -- casts that never reported back
		Refresh()
	else
		Queue()
	end
end)
for _, event in ipairs({ "UNIT_AURA", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
	frame:RegisterUnitEvent(event, "player")
end
for _, event in ipairs({
	"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
	"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
}) do
	frame:RegisterEvent(event)
end

ns.OnChange(Update)

function ns.DebugAuras()
	ns.Print(("in combat: %s, your name: %s"):format(tostring(InCombatLockdown()), tostring(UnitName("player"))))
	for id, d in pairs(durationById) do ns.Print(("known: %s %s = %ss"):format(id, tostring(SpellName(id)), d)) end
	for i, line in ipairs(castLog) do ns.Print(i .. ". " .. line) end
	if not castLog[1] then ns.Print("no casts of your own buffs seen yet") end
end
