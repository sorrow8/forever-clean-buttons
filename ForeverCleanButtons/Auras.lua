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
--
-- Each buff's aura instance is remembered out of combat too: when an aura
-- update in combat names a known instance (the game hides most of them, some
-- come through), an updated one starts again from its full duration and a
-- removed one takes its timer with it. The game refuses addons the live
-- duration in combat ("Auras cannot be accessed when secret while tainted").
--
-- A button whose buff is on you gets a coloured frame.

local FAST, SLOW = 0.2, 1 -- seconds between updates: while seconds show (a new one on time), or only minutes
local TEXT_SIZE, TEXT_MIN, TEXT_MAX = 0.45, 12, 22 -- font size: share of the button height, limits

local texts = {}  -- [button] = FontString
local holders = {} -- [button] = the frame holding its text and coloured frame
local byId = {}   -- [spellId] = expirationTime
local byName = {} -- [spell name] = expirationTime
local durationById = {}   -- [spellId] = full duration, kept for recasts in combat
local durationByName = {} -- [spell name] = full duration
local sentTo = {}         -- [castGUID] = who the cast was aimed at
local instById = {}       -- [spellId] = aura instance ID, read out of combat
local instByName = {}     -- [spell name] = aura instance ID
local spellOfInst = {}    -- [aura instance ID] = { id = spellId, name = spell name }
local GLOW = { 0.35, 0.95, 0.45, 1 } -- the frame of a button whose buff is on you
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
	local ids, names, insts, instNames, owners = {}, {}, {}, {}, {}
	local hidden = false
	for i = 1, 255 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or not aura then break end
		if issecrettable and issecrettable(aura) then return false end
		local source, expires, id, name, duration = aura.sourceUnit, aura.expirationTime, aura.spellId, aura.name, aura.duration
		if Secret(source) or Secret(expires) or Secret(id) or Secret(name) or Secret(duration) then
			hidden = true
		elseif source == "player" and expires and expires > 0 then
			if id then ids[id] = expires end
			if name then names[name] = expires end
			local inst = aura.auraInstanceID
			if inst and not Secret(inst) then
				if id then insts[id] = inst end
				if name then instNames[name] = inst end
				owners[inst] = { id = id, name = name }
			end
			if duration and duration > 0 then
				if id then durationById[id] = duration end
				if name then durationByName[name] = duration end
			end
		end
	end
	-- some buffs came back hidden: the timers known before keep running till they end
	if hidden then
		local now = GetTime()
		for k, v in pairs(byId) do if ids[k] == nil and v > now then ids[k] = v end end
		for k, v in pairs(byName) do if names[k] == nil and v > now then names[k] = v end end
		for k, v in pairs(instById) do if insts[k] == nil then insts[k] = v end end
		for k, v in pairs(instByName) do if instNames[k] == nil then instNames[k] = v end end
		for k, v in pairs(spellOfInst) do if owners[k] == nil then owners[k] = v end end
	end
	byId, byName, instById, instByName, spellOfInst = ids, names, insts, instNames, owners
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

-- When the button's buff ends (nil: not known) and whether it is on you.
-- By spell ID or by name, whichever is later: a recast of another rank in
-- combat only updates the name.
local function Expires(button)
	local spell = ButtonSpell(button)
	if not spell then return end
	local name = SpellName(spell)
	if Secret(name) then name = nil end
	local a, b = byId[spell], name and byName[name]
	local known = (a and b) and math.max(a, b) or a or b
	return known, known ~= nil and known > GetTime()
end

-- Showing ----------------------------------------------------------------------------

-- As on the game's own buff icons: seconds up to 90 s, minutes up to 90 m,
-- seconds round down, minutes and hours up. Seconds go without a letter.
function ns.FormatAuraTime(left)
	if left >= 129600 then return ("%dd"):format(math.ceil(left / 86400)) end
	if left >= 5400 then return ("%dh"):format(math.ceil(left / 3600)) end
	if left >= 90 then return ("%dm"):format(math.ceil(left / 60)) end
	return ("%d"):format(math.floor(left)) -- a bare number is seconds
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
		-- a bar that shows up later (in combat only, after Alt+Z) gets its timers
		holder:SetScript("OnShow", function() ns.QueueAuraTimers() end)
		-- the coloured frame of a buff that is on you, inside the button's edge
		holders[button] = holder
		holder.glow = {}
		for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
			local t = holder:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(GLOW[1], GLOW[2], GLOW[3], GLOW[4])
			t:SetPoint(side[1])
			t:SetPoint(side[2])
			t.horizontal = i <= 2
			t:Hide()
			holder.glow[i] = t
		end
		texts[button] = fs
	end
	return fs
end

-- Two screen pixels wide, whatever the bar's scale.
local function Glow(button, on)
	local holder = holders[button]
	if not holder or not holder.glow then return end
	local px = 1
	if PixelUtil and PixelUtil.GetPixelToUIUnitFactor then
		px = PixelUtil.GetPixelToUIUnitFactor() / button:GetEffectiveScale()
	end
	for _, t in ipairs(holder.glow) do
		if t.horizontal then t:SetHeight(2 * px) else t:SetWidth(2 * px) end
		if on then t:Show() else t:Hide() end
	end
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
		local expires, isOn
		if on and button:IsVisible() then expires, isOn = Expires(button) end
		Glow(button, isOn)
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

ns.QueueAuraTimers = Queue

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
	-- the name may come with the realm ("Name-Realm"): yours only on your realm
	local name, realm = target:match("^(.-)%-(.+)$")
	if name then
		local own = GetNormalizedRealmName and GetNormalizedRealmName()
		if own ~= nil and realm ~= own then return false end
		target = name
	end
	-- Forever adds a surname to the name ("Adibas Originals")
	local me = UnitName("player")
	return target == me or target:sub(1, #me + 1) == me .. " "
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
		pcall(ns.NoteAuraUpdate, a) -- a note for /fcb debug must never break anything
		if InCombatLockdown() then
			pcall(ns.FollowAuraUpdate, a)
			return Queue()
		end
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

-- A known buff starts again from its full duration (a recast) or ends.
local function Restart(owner)
	local duration = (owner.id and durationById[owner.id]) or (owner.name and durationByName[owner.name])
	if not duration then return end
	local expires = GetTime() + duration
	if owner.id then byId[owner.id] = expires end
	if owner.name then byName[owner.name] = expires end
end

local function Ended(owner)
	if owner.id then byId[owner.id] = nil end
	if owner.name then byName[owner.name] = nil end
end

local function Visible(v)
	return not (Secret(v) or (issecrettable and issecrettable(v)))
end

-- In combat: what the aura update names, without reading any aura data.
function ns.FollowAuraUpdate(info)
	if type(info) ~= "table" or not Visible(info) then return end
	local updated, added, removed = info.updatedAuraInstanceIDs, info.addedAuras, info.removedAuraInstanceIDs
	if type(updated) == "table" and Visible(updated) then
		for _, inst in ipairs(updated) do
			local owner = Visible(inst) and spellOfInst[inst]
			if owner then Restart(owner) end
		end
	end
	if type(added) == "table" and Visible(added) then
		for _, aura in ipairs(added) do
			if type(aura) == "table" and Visible(aura) then
				local inst, id = aura.auraInstanceID, aura.spellId
				if Visible(inst) and inst then
					local owner = spellOfInst[inst]
					if not owner and Visible(id) and id and durationById[id] then
						owner = { id = id, name = SpellName(id) }
						spellOfInst[inst] = owner
						instById[id] = inst
					end
					if owner then Restart(owner) end
				end
			end
		end
	end
	if type(removed) == "table" and Visible(removed) then
		for _, inst in ipairs(removed) do
			local owner = Visible(inst) and spellOfInst[inst]
			if owner then Ended(owner) end
		end
	end
end

-- What the last aura update said, for /fcb debug.
local lastUpdate = "none yet"
local function Hidden(v)
	return Secret(v) or (issecrettable and issecrettable(v))
end

function ns.NoteAuraUpdate(info)
	if type(info) ~= "table" or Hidden(info) then lastUpdate = "no details"; return end
	local function ids(list)
		if Hidden(list) then return "<secret>" end
		if type(list) ~= "table" then return "-" end
		local out = {}
		for _, v in ipairs(list) do
			local id = type(v) == "table" and v.auraInstanceID or v
			out[#out + 1] = Secret(id) and "<secret>" or tostring(id)
		end
		return table.concat(out, ",")
	end
	lastUpdate = ("full=%s added=%s updated=%s removed=%s"):format(tostring(info.isFullUpdate),
		ids(info.addedAuras), ids(info.updatedAuraInstanceIDs), ids(info.removedAuraInstanceIDs))
end

function ns.DebugAuras()
	ns.Print(("in combat: %s, your name: %s"):format(tostring(InCombatLockdown()), tostring(UnitName("player"))))
	for id, inst in pairs(instById) do ns.Print(("instance: %s %s #%s"):format(id, tostring(SpellName(id)), inst)) end
	ns.Print("last aura update: " .. lastUpdate)
	for id, d in pairs(durationById) do ns.Print(("known: %s %s = %ss"):format(id, tostring(SpellName(id)), d)) end
	for i, line in ipairs(castLog) do ns.Print(i .. ". " .. line) end
	if not castLog[1] then ns.Print("no casts of your own buffs seen yet") end
end
