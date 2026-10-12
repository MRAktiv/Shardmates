-- Startup: saved settings, options panel, minimap button and slash commands.
local ADDON_NAME, ns = ...
local addon, L = ns.addon, ns.L

local ICON = "Interface\\AddOns\\Shardmates\\Media\\icon"

function ns.SetMode(mode)
	ns.db.profile.mode = mode
	ns.Net:OnStateChanged()
	LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
	ns.UI:Queue()
	ns.UI:Refresh()
end

-- The settings panel opener is restricted in some states; the Ace dialog is the fallback.
function ns.OpenOptions()
	if Settings and Settings.OpenToCategory and ns.optionsCategoryID then
		if pcall(Settings.OpenToCategory, ns.optionsCategoryID) then
			return
		end
	end
	LibStub("AceConfigDialog-3.0"):Open(ADDON_NAME)
end

local function tooltip(tip)
	tip:AddLine(L["TITLE"])
	tip:AddLine(ns.Layer:StatusText(), 1, 1, 1)
	tip:AddLine(L["MODE"] .. ": " .. L["MODE_" .. ns.db.profile.mode], 1, 1, 1)
	tip:AddLine(L["NEIGHBOURS"]:format(#(ns.Net:Matches())), 1, 1, 1)
	tip:AddLine(" ")
	tip:AddLine(L["TOOLTIP_LEFT"], 0.6, 0.6, 0.6)
	tip:AddLine(L["TOOLTIP_RIGHT"], 0.6, 0.6, 0.6)
end

function addon:OnInitialize()
	ns.db = LibStub("AceDB-3.0"):New("ShardmatesDB", ns.DEFAULTS, true)

	LibStub("AceConfig-3.0"):RegisterOptionsTable(ADDON_NAME, ns.BuildOptions)
	local _, categoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(ADDON_NAME, L["TITLE"])
	ns.optionsCategoryID = categoryID

	local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON_NAME, {
		type = "launcher",
		text = L["TITLE"],
		icon = ICON,
		OnClick = function(_, button)
			if button == "RightButton" then
				ns.OpenOptions()
			else
				ns.UI:Toggle()
			end
		end,
		OnTooltipShow = tooltip,
	})
	LibStub("LibDBIcon-1.0"):Register(ADDON_NAME, launcher, ns.db.profile.minimap)

	self:RegisterChatCommand("shardmates", "OnSlash")
	self:RegisterChatCommand("smates", "OnSlash")
end

function addon:OnSlash(input)
	local command, argument = (input or ""):lower():match("^%s*(%S*)%s*(%S*)")
	if command == "diag" then
		ns.Diag:Run()
	elseif command == "mode" and (argument == "ask" or argument == "auto" or argument == "off") then
		ns.SetMode(argument)
		ns.Print(L["MODE"] .. ": " .. L["MODE_" .. argument])
	elseif command == "options" or command == "config" then
		ns.OpenOptions()
	elseif command == "debug" then
		ns.db.profile.debug = not ns.db.profile.debug
		ns.Print("debug", tostring(ns.db.profile.debug))
	else
		ns.UI:Toggle()
	end
end
