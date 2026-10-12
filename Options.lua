-- Settings panel built with AceConfig.
local ADDON_NAME, ns = ...
local L = ns.L

local function getter(key)
	return function()
		return ns.db.profile[key]
	end
end

local function setter(key)
	return function(_, value)
		ns.db.profile[key] = value
	end
end

function ns.BuildOptions()
	return {
		type = "group",
		name = L["TITLE"],
		args = {
			mode = {
				order = 1,
				type = "select",
				name = L["OPT_MODE"],
				desc = L["OPT_MODE_DESC"],
				values = { ask = L["MODE_ask"], auto = L["MODE_auto"], off = L["MODE_off"] },
				sorting = { "ask", "auto", "off" },
				get = getter("mode"),
				set = function(_, value)
					ns.SetMode(value)
				end,
				width = "double",
			},
			tagHelper = {
				order = 2,
				type = "toggle",
				name = L["OPT_TAG"],
				desc = L["OPT_TAG_DESC"],
				get = getter("tagHelper"),
				set = setter("tagHelper"),
				width = "full",
			},
			tagWhisper = {
				order = 3,
				type = "toggle",
				name = L["OPT_TAG_WHISPER"],
				get = getter("tagWhisper"),
				set = setter("tagWhisper"),
				width = "full",
			},
			dissolvePrompt = {
				order = 4,
				type = "toggle",
				name = L["OPT_DISSOLVE"],
				get = getter("dissolvePrompt"),
				set = setter("dissolvePrompt"),
				width = "full",
			},
			minimap = {
				order = 5,
				type = "toggle",
				name = L["OPT_MINIMAP"],
				get = function()
					return not ns.db.profile.minimap.hide
				end,
				set = function(_, value)
					ns.db.profile.minimap.hide = not value
					local icon = LibStub("LibDBIcon-1.0")
					if value then
						icon:Show(ADDON_NAME)
					else
						icon:Hide(ADDON_NAME)
					end
				end,
				width = "full",
			},
			debug = {
				order = 6,
				type = "toggle",
				name = L["OPT_DEBUG"],
				get = getter("debug"),
				set = setter("debug"),
				width = "full",
			},
		},
	}
end
