local _, ns = ...

-- English is the base; a locale file (Locales/*.lua) only overrides what it
-- translates. The game's language is used unless one is picked in the
-- window's language menu or with /fcb lang.
local L = {
	TITLE = "Forever Clean Buttons",

	ENABLED = "Addon enabled",
	ENABLED_HELP = "Off: the buttons get their usual look back.",

	PREVIEW = "Preview",

	BORDER = "Border",
	BORDER_HELP = "Thickness of the frame around every button, in screen pixels.",
	BORDER_NONE = "none",
	BORDER_PX = "%d px",

	COLOR = "Border colour",
	COLOR_BLACK = "Black",
	COLOR_GRAPHITE = "Graphite",
	COLOR_CLASS = "Class",
	COLOR_GOLD = "Gold",

	ZOOM = "Icon zoom",
	ZOOM_HELP = "Cuts the edges of the icons, where the game draws a border into the picture itself.",
	ZOOM_PCT = "%d%%",

	BAGS = "Bag buttons",
	BAGS_HELP = "The backpack and bag slots get the same square look.",
	MICRO = "Menu buttons",
	MICRO_HELP = "The small buttons for the character, spellbook, quest log and the rest.",

	AURAS = "Buff timers on buttons",
	AURAS_HELP = "Your own buffs show how long they have left on their spell's button. In combat the game hides buff data from addons, so the time keeps counting from before the fight.",

	RESET = "Reset settings",
	CMD_HINT = "Open this window:",
	LANG_AUTO = "Auto",

	MSG_WELCOME = "installed. Your buttons are now square. Settings: type |cffebbd61/fcb|r",
	MSG_LOADED = "loaded. Settings: |cffebbd61/fcb|r",
	MSG_ON = "on.",
	MSG_OFF = "off, the buttons look as usual again.",
	MSG_RESET = "settings reset.",
	MSG_HELP = "/fcb: window, /fcb on, /fcb off, /fcb lang auto/en/ru, /fcb reset",

	OPTIONS_OPEN = "Open the settings window",
	OPTIONS_TEXT = "Every setting lives in the addon's own window.",
}

ns.LOCALES = {}

-- The language menu.
ns.LANGUAGES = {
	{ code = "enUS", short = "en", name = "English" },
	{ code = "ruRU", short = "ru", name = "Русский" },
}

function ns.LanguageAvailable(lang)
	return not lang.cjk or GetLocale() == lang.code
end

-- "ruRU" or "ru" -> "ruRU"; nil, "auto" or anything unknown -> nil.
function ns.LanguageCode(choice)
	if type(choice) ~= "string" then return nil end
	choice = choice:lower()
	for _, lang in ipairs(ns.LANGUAGES) do
		if choice == lang.short or choice == lang.code:lower() then return lang.code end
	end
end

local EN = {}
for k, v in pairs(L) do EN[k] = v end

-- The game's language as one of ns.LANGUAGES' codes.
function ns.ClientLocale()
	local code = GetLocale()
	if code == "enGB" then return "enUS" end
	return code
end

-- The table stays the same object, so every file holding ns.L sees the change.
function ns.ApplyLocale(choice)
	local code = ns.LanguageCode(choice) or ns.ClientLocale()
	for k, v in pairs(EN) do L[k] = v end
	local over = ns.LOCALES[code]
	if over then
		for k, v in pairs(over) do L[k] = v end
	end
	ns.activeLocale = over and code or "enUS"
end

ns.L = L
