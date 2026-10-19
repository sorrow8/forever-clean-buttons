local ADDON, ns = ...
local L = ns.L

-- A button on the edge of the minimap, made with LibDBIcon so that minimap
-- button collectors (Leatrix Plus and others) take it in with its own
-- tooltip. Left-click opens the window, right-click turns the addon on or
-- off. The icon goes grey while the addon is off.

local ICON = "Interface\\Icons\\INV_Misc_Gem_Pearl_04"
local DBIcon = LibStub("LibDBIcon-1.0")

local broker = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON, {
	type = "launcher",
	icon = ICON,
	OnClick = function(_, mouse)
		if mouse == "RightButton" then
			ns.SetEnabled(not ns.DB().enabled)
		else
			ns.ToggleWindow()
		end
	end,
	OnTooltipShow = function(tip)
		tip:AddLine(L.TITLE, 1, 1, 1)
		tip:AddLine(L.MM_LEFT, 0.8, 0.8, 0.8)
		tip:AddLine(L.MM_RIGHT, 0.8, 0.8, 0.8)
	end,
})

-- LibDBIcon keeps the spot in db.minimapIcon; a reset gives a new table.
local registeredWith

-- Shown or hidden by the setting, grey while the addon is off.
function ns.UpdateMinimapButton()
	local db = ns.DB()
	db.minimapIcon = db.minimapIcon or { minimapPos = db.minimapAngle }
	db.minimapIcon.hide = not db.minimapShow
	if not registeredWith then
		DBIcon:Register(ADDON, broker, db.minimapIcon)
	elseif registeredWith ~= db.minimapIcon then
		DBIcon:Refresh(ADDON, db.minimapIcon)
	end
	registeredWith = db.minimapIcon
	if db.minimapShow then DBIcon:Show(ADDON) else DBIcon:Hide(ADDON) end
	local button = DBIcon:GetMinimapButton(ADDON)
	if button and button.icon then button.icon:SetDesaturated(not db.enabled) end
end
