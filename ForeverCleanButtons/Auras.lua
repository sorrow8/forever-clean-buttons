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
-- come through), an updated one starts again from its full duration if you
-- have just cast that spell (a shield taking a hit is an update too) and a
-- removed one takes its timer with it. The game refuses addons the live
-- duration in combat ("Auras cannot be accessed when secret while tainted").
--
-- Some buffs replace each other: only one seal can be on you. The game
-- doesn't tell us in combat that the old one went, so the addon learns it out
-- of combat (a buff of yours that ends early just after you put another one
-- on yourself that wasn't on you, seen twice, is replaced by it) and
-- remembers it. In combat, casting one of them then ends the timers of the
-- others. /fcb forget clears what was learned.
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
local durationKnown = {}  -- [spell name] = true: its duration came from a spell you know
local sentTo = {}         -- [castGUID] = { target = who the cast was aimed at, at = when }
local SENT_KEEP = 10      -- seconds a cast may take to report back, longer than any cast
local castAt = {}         -- [spellId] or [spell name] = when your last cast of it went off
local RECAST_WINDOW = 0.5 -- seconds: an aura update this soon after the cast is the recast
local instById = {}       -- [spellId] = aura instance ID, read out of combat
local instByName = {}     -- [spell name] = aura instance ID
local spellOfInst = {}    -- [aura instance ID] = { id = spellId, name = spell name }
local lastCast            -- { name, at, new }: your last cast aimed at yourself, new: its buff wasn't on you
local replaced = {}       -- { a, b, at }: buff a ended early just after b was cast, waiting for b to show
local LEARN_WINDOW = 2    -- seconds between the cast and the buff it replaced ending
local LEARN_SEEN = 2      -- a pair seen once may be chance (a proc used up, a drink cut short)
local UNKNOWN = math.huge  -- a buff that is on, but how long it lasts isn't known yet
local OUTLINE = "Interface\\AddOns\\ForeverCleanButtons\\media\\outline" -- the skin's outline
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

-- A spell you know, not one set off by another: a Seal of Command hit is a
-- spell of its own with the seal's name, and must not restart the seal.
local function Known(spellId)
	local book = C_SpellBook
	local check = (book and (book.IsSpellKnownOrInSpellBook or book.IsSpellKnown)) or IsPlayerSpell
	if not check or not spellId then return true end
	local ok, yes = pcall(check, spellId)
	if not ok or Secret(yes) then return true end
	return yes
end

-- A buff's full duration as last seen out of combat, kept over a reload: a
-- seal first cast in combat after /reload still gets its timer.
local function SavedDuration(name)
	local db = name and DB()
	return db and db.durations and db.durations[name]
end

-- Buffs that replace each other, by spell name (all ranks), saved:
-- [spell name] = group number.
local function Groups()
	local db = DB()
	if not db then return nil end
	-- groups saved by older versions came from one sighting and may be wrong: start again once
	if (db.exclusiveVersion or 0) < 2 then
		db.exclusive, db.exclusiveSeen, db.exclusiveVersion = {}, {}, 2
	end
	db.exclusive = db.exclusive or {}
	return db.exclusive
end

-- Seals, auras and aspects replace each other by the game's own rules: these
-- need no learning, so a swap in combat ends the old one at once. Other
-- buffs that share a word (Power Word: Shield / Power Word: Fortitude) don't.
-- The spells are also known by ID, so their names in any game language count.
-- Seals, auras, aspects, armors and elemental shields can only go on you; the
-- others can go on a friend too.
local KINDS = {
	seal = { 21084, 20375, 21082, 20164, 20165, 20166, 20163 },
	aura = { 465, 7294, 19746, 19876, 19888, 19891 },
	aspect = { 13165, 13163, 5118, 13159, 20043, 13161 },
	magearmor = { 168, 7302, 6117 },
	demonarmor = { 687, 706 },
	shield = { 324, 408510 }, -- Lightning Shield, Water Shield
	-- one blessing from each paladin, the Greater ones too
	blessing = { 19740, 19742, 20217, 19977, 25782, 25894, 25898, 25890 },
	intellect = { 1459, 23028 },
	fortitude = { 1243, 21562 },
	spirit = { 14752, 27681 },
	shadowprotection = { 976, 27683 },
	wild = { 1126, 21849 },
}
local SELF_ONLY = { seal = true, aura = true, aspect = true, magearmor = true, demonarmor = true, shield = true }
local kindByName
local function Kind(name)
	if not kindByName then
		kindByName = {}
		for kind, ids in pairs(KINDS) do
			for _, id in ipairs(ids) do
				local spell = SpellName(id)
				if spell and not Secret(spell) then kindByName[spell] = kind end
			end
		end
	end
	if kindByName[name] then return kindByName[name] end
	if name:match("^Seal of ") or name:match("^Печать ") then return "seal" end
	if name:match("^Aspect of ") then return "aspect" end
	if name:match(" Aura$") or name:match("^Аура ") then return "aura" end
end

-- Buffs whose length depends on combo points (Slice and Dice, Savage Roar):
-- a recast in combat can't know it, so the button shows the buff is on, and
-- the time comes back once the fight ends.
local VARIES = { 5171, 6774, 407988 }
local variesByName
local function Varies(id, name)
	if not variesByName then
		variesByName = {}
		for _, v in ipairs(VARIES) do
			variesByName[v] = true
			local spell = SpellName(v)
			if spell and not Secret(spell) then variesByName[spell] = true end
		end
	end
	return (id ~= nil and variesByName[id]) or (name ~= nil and variesByName[name]) or false
end

-- One of the kinds that can only be on you.
local function SelfKind(name)
	local kind = name and Kind(name)
	return kind ~= nil and SELF_ONLY[kind] == true
end

-- One more sighting of two buffs replacing each other, saved till it is
-- trusted: ["a\nb"] = times. True once seen often enough; seals, auras and
-- aspects are trusted at once.
local function Seen(a, b)
	if not Groups() then return false end
	local kind = Kind(a)
	if kind and kind == Kind(b) then return true end
	local db = DB()
	db.exclusiveSeen = db.exclusiveSeen or {}
	local key = a < b and a .. "\n" .. b or b .. "\n" .. a
	local times = (db.exclusiveSeen[key] or 0) + 1
	if times < LEARN_SEEN then
		db.exclusiveSeen[key] = times
		return false
	end
	db.exclusiveSeen[key] = nil -- the group keeps it from now on
	return true
end

-- /fcb forget: a wrong group would keep ending the wrong timers.
function ns.ForgetAuraGroups()
	local db = DB()
	if not db then return end
	db.exclusive, db.exclusiveSeen = {}, {}
	wipe(replaced)
end

local function Join(a, b)
	local groups = Groups()
	if not groups or a == b then return end
	local ga, gb = groups[a], groups[b]
	if ga and ga == gb then return end
	if not (ga or gb) then
		local top = 0
		for _, g in pairs(groups) do top = math.max(top, g) end
		ga = top + 1
	end
	ga = ga or gb
	if gb then
		for name, g in pairs(groups) do if g == gb then groups[name] = ga end end
	end
	groups[a], groups[b] = ga, ga
end

-- You cast one of a group: the others are gone.
local function EndOthers(name)
	local groups, kind = Groups(), Kind(name)
	local group = groups and groups[name]
	local function Replaced(other)
		if other == name then return false end
		return (group ~= nil and groups[other] == group) or (kind ~= nil and Kind(other) == kind)
	end
	for other in pairs(byName) do
		if Replaced(other) then byName[other] = nil end
	end
	for id in pairs(byId) do
		local other = SpellName(id)
		if other and not Secret(other) and Replaced(other) then byId[id] = nil end
	end
end

-- Out of combat: a buff that ended early just after you cast another buff on
-- yourself was replaced by it, once that one shows. Only a buff the cast put
-- on you anew counts: a renewed one replaced nothing.
local function Learn(names, now)
	if lastCast and lastCast.new and now - lastCast.at < LEARN_WINDOW then
		for name, expires in pairs(byName) do
			if names[name] == nil and expires > now + 1 and name ~= lastCast.name then
				replaced[#replaced + 1] = { a = name, b = lastCast.name, at = now }
			end
		end
	end
	for i = #replaced, 1, -1 do
		local r = replaced[i]
		if names[r.b] then
			if Seen(r.a, r.b) then Join(r.a, r.b) end
			table.remove(replaced, i)
		elseif now - r.at > LEARN_WINDOW then
			table.remove(replaced, i)
		end
	end
end

-- Reading -----------------------------------------------------------------------

-- The game can hide aura data out of combat too (a battleground, an arena, a
-- keystone): then the last known timers stay and keep counting down.
local function Scan()
	if InCombatLockdown() then return false end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
	local ids, names, insts, instNames, owners = {}, {}, {}, {}, {}
	local hidden = false
	local found = {}  -- your buffs: { id, name, expires, duration, inst, mine }
	local byNameBest = {} -- [spell name] = the one of found the name stands for
	for i = 1, 255 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		-- refused (a battleground, an arena): keep what is known
		if not ok then return false end
		if not aura then break end
		if issecrettable and issecrettable(aura) then return false end
		local source, expires, id, name, duration = aura.sourceUnit, aura.expirationTime, aura.spellId, aura.name, aura.duration
		if Secret(source) or Secret(expires) or Secret(id) or Secret(name) or Secret(duration) then
			hidden = true
		elseif source == "player" and expires then
			-- a permanent one (a paladin aura, an aspect) is on, with no time
			if expires <= 0 then expires = UNKNOWN end
			local inst = aura.auraInstanceID
			if Secret(inst) then inst = nil end
			local f = { id = id, name = name, expires = expires, duration = duration or 0, inst = inst, mine = Known(id) }
			found[#found + 1] = f
			-- two of your buffs can share a name (a seal and a shield its hits
			-- put on you): the one from a spell you know stands for the name,
			-- else the longer one
			local best = name and byNameBest[name]
			if name and (not best or (f.mine and not best.mine) or (f.mine == best.mine and f.duration > best.duration)) then
				byNameBest[name] = f
			end
		end
	end
	for _, f in ipairs(found) do
		local id, inst = f.id, f.inst
		local name = f.name and byNameBest[f.name] == f and f.name or nil
		if id then ids[id] = f.expires end
		if name then names[name] = f.expires end
		if inst then
			if id then insts[id] = inst end
			if name then instNames[name] = inst end
			-- the other one's name stays out: its end mustn't end this one's timer
			owners[inst] = { id = id, name = name }
		end
		if f.duration > 0 then
			if id then durationById[id] = f.duration end
			-- a name's full duration comes from a spell you know once one was seen
			if name and (f.mine or not durationKnown[name]) then
				durationByName[name] = f.duration
				if f.mine then durationKnown[name] = true end
				local db = DB()
				if db then
					db.durations = db.durations or {}
					db.durations[name] = f.duration
				end
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
	else
		Learn(names, GetTime())
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
	-- a macro hands back the spell it shows; for an item or nothing the ID isn't a spell
	if kind == "macro" and subType == "spell" then return id end
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
		-- the coloured frame of a buff that is on you: the same outline as the
		-- gold one of auto attack, so both are equally thin
		holders[button] = holder
		local t = holder:CreateTexture(nil, "OVERLAY")
		t:SetTexture(OUTLINE)
		t:SetVertexColor(GLOW[1], GLOW[2], GLOW[3], GLOW[4])
		t:Hide()
		holder.glow = t
		texts[button] = fs
	end
	return fs
end

-- Where the gold outline of auto attack sits: over the whole button, border
-- included, with or without the skin.
local function Glow(button, on)
	local holder = holders[button]
	local t = holder and holder.glow
	if not t then return end
	if on then
		local checked = button.GetCheckedTexture and button:GetCheckedTexture()
		t:ClearAllPoints()
		if checked and DB() and DB().enabled then t:SetAllPoints(checked) else t:SetAllPoints(holder) end
		t:Show()
	else
		t:Hide()
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
		if left == UNKNOWN then
			fs:Hide() -- on: the frame shows it, there's no time to show
		elseif left and left > 0 then
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

-- A spell that can only go on you: a seal, an aura, an aspect (no range, or
-- the game says its effects are yours alone).
local function SelfOnly(spellId)
	if not spellId or Secret(spellId) or not C_Spell then return false end
	if C_Spell.IsSelfBuff then
		local ok, yes = pcall(C_Spell.IsSelfBuff, spellId)
		if ok and not Secret(yes) and yes then return true end
	end
	if C_Spell.SpellHasRange then
		local ok, ranged = pcall(C_Spell.SpellHasRange, spellId)
		if ok and not Secret(ranged) and ranged == false then return true end
	end
	return false
end

-- Whether a cast went to you: no target (seals, self-only buffs), your own
-- name, or, when the name can't be read, a spell that can only go on you, no
-- target or an enemy one. A buff on a friend whose name is hidden is not
-- yours: a Renew on the tank mustn't restart your own.
local function AtSelf(target, spellId)
	if Secret(target) then
		local spell = spellId and not Secret(spellId) and SpellName(spellId)
		if SelfOnly(spellId) or (spell and not Secret(spell) and SelfKind(spell)) then return true end
		local exists, friend, me = UnitExists("target"), UnitIsFriend("player", "target"), UnitIsUnit("target", "player")
		if not Secret(exists) and not exists then return true end
		if not Secret(friend) and not friend then return true end
		if Secret(exists) or Secret(friend) or Secret(me) then return false end
		return me
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
	local sent = sentTo[castGUID]
	sentTo[castGUID] = nil
	if Secret(spellId) then return Log("secret spell") end
	local name = SpellName(spellId)
	if Secret(name) then name = nil end
	if not Known(spellId) then return Log(spellId, name, "- not a spell of yours (a proc)") end
	local now = GetTime()
	castAt[spellId] = now
	if name then castAt[name] = now end
	-- no SENT seen for it (the game may keep it from addons in combat): only a
	-- spell that can go on you alone, like a seal, counts as yours
	local target = sent and sent.target
	local atSelf
	if sent then atSelf = AtSelf(target, spellId) else atSelf = SelfOnly(spellId) or SelfKind(name) end
	if name and atSelf then
		EndOthers(name)
		Queue()
	end
	-- only your own buffs have a known duration; anything else stops here
	local duration = durationById[spellId] or (name and (durationByName[name] or SavedDuration(name)))
	local shownTarget = not sent and "<unknown>" or Secret(target) and "<secret>" or target
	if not duration then
		-- a seal, aura or aspect not seen out of combat yet: on, time not known
		if name and atSelf and SelfKind(name) then
			byName[name] = UNKNOWN
			Queue()
			return Log(spellId, name, "to", shownTarget, "- on, time not known yet")
		end
		return Log(spellId, name, "to", shownTarget, "- no known duration")
	end
	if not atSelf then return Log(spellId, name, "to", shownTarget, "- not at you") end
	if Varies(spellId, name) then
		byId[spellId] = UNKNOWN
		if name then byName[name] = UNKNOWN end
		Queue()
		return Log(spellId, name, "to", shownTarget, "- on, its time depends on combo points")
	end
	Log(spellId, name, "to", shownTarget, "- restarted at", duration)
	local expires = now + duration
	byId[spellId] = expires
	if name then byName[name] = expires end
	Queue()
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, unit, a, b, c)
	if event == "UNIT_SPELLCAST_SENT" then
		-- unit, target, castGUID, spellId
		if not Secret(b) and b then sentTo[b] = { target = a, at = GetTime() } end
		-- the buff may change before the cast reports back
		local name = c and not Secret(c) and SpellName(c)
		if name and not Secret(name) and AtSelf(a, c) then
			local now, known = GetTime(), byName[name]
			lastCast = { name = name, at = now, new = not (known and known > now) }
		end
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
		-- casts that never reported back; one still going keeps its target
		local now = GetTime()
		for guid, sent in pairs(sentTo) do
			if now - sent.at > SENT_KEEP then sentTo[guid] = nil end
		end
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
	local duration = (owner.id and durationById[owner.id]) or (owner.name and (durationByName[owner.name] or SavedDuration(owner.name)))
	if not duration then return end
	local expires = Varies(owner.id, owner.name) and UNKNOWN or GetTime() + duration
	if owner.id then byId[owner.id] = expires end
	if owner.name then byName[owner.name] = expires end
end

-- An update also comes when a shield soaks a hit or charges are used: only
-- one right after your own cast of that spell is a recast.
local function JustCast(owner)
	local at = math.max((owner.id and castAt[owner.id]) or 0, (owner.name and castAt[owner.name]) or 0)
	return GetTime() - at < RECAST_WINDOW
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
			if owner and JustCast(owner) then Restart(owner) end
		end
	end
	if type(added) == "table" and Visible(added) then
		for _, aura in ipairs(added) do
			if type(aura) == "table" and Visible(aura) then
				local inst, id = aura.auraInstanceID, aura.spellId
				if Visible(inst) and inst then
					local owner = spellOfInst[inst]
					if not owner and Visible(id) and id and durationById[id] then
						-- a buff a proc put on you keeps to its own ID, not the name it shares
						owner = { id = id, name = Known(id) and SpellName(id) or nil }
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
	for name, g in pairs(Groups() or {}) do ns.Print(("replace each other (%d): %s"):format(g, name)) end
	for i, line in ipairs(castLog) do ns.Print(i .. ". " .. line) end
	if not castLog[1] then ns.Print("no casts of your own buffs seen yet") end
end
