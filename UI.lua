-- Main window with players on the same quests, request and leave dialogs.
local _, ns = ...
local addon, L = ns.addon, ns.L

local UI = addon:NewModule("UI", "AceEvent-3.0", "AceTimer-3.0")
ns.UI = UI

local ROWS = 8
local ROW_HEIGHT = 40
local WIDTH = 460
local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

local GREEN, ORANGE, GREY = "|cff40ff40", "|cffffb000", "|cff9d9d9d"
local MODES = { "ask", "auto", "off" }

function UI:OnEnable()
	self:RegisterMessage("SHARDMATES_PEERS_CHANGED", "Queue")
	self:RegisterMessage("SHARDMATES_QUESTS_CHANGED", "Queue")
	self:RegisterMessage("SHARDMATES_LAYER_CHANGED", "Queue")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "Queue")

	StaticPopupDialogs["SHARDMATES_REQUEST"] = {
		text = "%s",
		button1 = L["REQUEST_ACCEPT"],
		button2 = L["REQUEST_DECLINE"],
		OnAccept = function(_, data)
			ns.Net:AcceptRequest(data)
		end,
		OnCancel = function(_, data)
			ns.Net:DeclineRequest(data)
		end,
		timeout = 40,
		whileDead = false,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopupDialogs["SHARDMATES_DISSOLVE"] = {
		text = L["DISSOLVE_TEXT"],
		button1 = L["DISSOLVE_LEAVE"],
		button2 = L["DISSOLVE_STAY"],
		OnAccept = function()
			pcall(SendChat, L["THANKS_MESSAGE"], "PARTY")
			C_PartyInfo.LeaveParty()
		end,
		timeout = 60,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

function UI:Queue()
	if self.frame and self.frame:IsShown() and not self.refreshTimer then
		self.refreshTimer = self:ScheduleTimer(function()
			self.refreshTimer = nil
			self:Refresh()
		end, 0.3)
	end
end

local function classColor(classID)
	local info = classID and C_CreatureInfo.GetClassInfo(classID)
	local color = info and RAID_CLASS_COLORS[info.classFile]
	return color and color.colorStr and ("|c" .. color.colorStr) or "|cffffffff"
end

-- Cuts by characters, not bytes, so Cyrillic titles never break mid-letter.
local function shorten(text, size)
	local count, cut = 0, nil
	for start in text:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
		count = count + 1
		if count == size then
			cut = start
		end
	end
	if count > size and cut then
		return text:sub(1, cut - 1) .. "..."
	end
	return text
end

ns.Shorten = shorten

-- One line per shared quest: title and what grouping does for it.
function UI:SharedSummary(comparison, limit)
	local lines = {}
	for index, entry in ipairs(comparison.shared) do
		if index > limit then
			lines[#lines + 1] = GREY .. "+" .. (#comparison.shared - limit) .. "|r"
			break
		end
		local tags = {}
		if entry.kill then
			tags[#tags + 1] = GREEN .. L["KILL"] .. "|r"
		end
		if entry.event then
			tags[#tags + 1] = GREEN .. L["EVENT"] .. "|r"
		end
		if entry.split then
			tags[#tags + 1] = ORANGE .. L["SPLIT"] .. "|r"
		end
		if entry.group then
			tags[#tags + 1] = L["GROUP_QUEST"]
		end
		lines[#lines + 1] = shorten(ns.Quests:Title(entry.questID), 34) .. ": " .. table.concat(tags, ", ")
	end
	return table.concat(lines, "\n")
end

local function layerText(layer)
	if layer == "same" then
		return GREEN .. L["SAME_LAYER"] .. "|r"
	elseif layer == "other" then
		return ORANGE .. L["OTHER_LAYER"] .. "|r"
	end
	return GREY .. L["UNKNOWN_LAYER"] .. "|r"
end

function UI:CreateRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(WIDTH - 36, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -56 - (index - 1) * ROW_HEIGHT)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", 0, -2)
	row.name:SetJustifyH("LEFT")

	row.layer = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.layer:SetPoint("LEFT", row.name, "RIGHT", 8, 0)

	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.detail:SetWidth(WIDTH - 160)
	row.detail:SetJustifyH("LEFT")
	row.detail:SetMaxLines(2)

	row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.button:SetSize(110, 22)
	row.button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.button:SetScript("OnClick", function()
		if row.match then
			ns.Net:Request(row.match)
		end
	end)
	row.button:SetScript("OnEnter", function(widget)
		local match = row.match
		if not match then
			return
		end
		GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
		if match.action == "none" then
			GameTooltip:SetText(L["REASON_" .. match.reason] or match.reason, 1, 0.82, 0, 1, true)
		else
			GameTooltip:SetText(L["MOVE_" .. match.moves], 1, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	row.button:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

function UI:Create()
	local frame = CreateFrame("Frame", "ShardmatesFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(WIDTH, 100 + ROWS * ROW_HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetScript("OnShow", function()
		UI:Refresh()
	end)
	frame:Hide()
	frame.TitleText:SetText(L["TITLE"])
	tinsert(UISpecialFrames, "ShardmatesFrame")

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.status:SetPoint("TOPLEFT", 16, -32)
	frame.status:SetJustifyH("LEFT")

	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("CENTER", 0, 10)
	frame.empty:SetWidth(WIDTH - 60)

	frame.rows = {}
	for index = 1, ROWS do
		frame.rows[index] = self:CreateRow(frame, index)
	end

	frame.modeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.modeButton:SetSize(200, 22)
	frame.modeButton:SetPoint("BOTTOMLEFT", 14, 12)
	frame.modeButton:SetScript("OnClick", function()
		UI:CycleMode()
	end)

	frame.optionsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.optionsButton:SetSize(120, 22)
	frame.optionsButton:SetPoint("BOTTOMRIGHT", -14, 12)
	frame.optionsButton:SetText(L["BTN_OPTIONS"])
	frame.optionsButton:SetScript("OnClick", function()
		ns.OpenOptions()
	end)

	self.frame = frame
end

function UI:CycleMode()
	local current = ns.db.profile.mode
	local nextMode = MODES[1]
	for index, mode in ipairs(MODES) do
		if mode == current then
			nextMode = MODES[index % #MODES + 1]
		end
	end
	ns.SetMode(nextMode)
end

function UI:Toggle()
	if not self.frame then
		self:Create()
	end
	self.frame:SetShown(not self.frame:IsShown())
end

function UI:StatusLine(count)
	return ns.Layer:StatusText() .. "\n" .. L["NEIGHBOURS"]:format(count)
end

function UI:Refresh()
	local frame = self.frame
	if not frame or not frame:IsShown() then
		return
	end
	local matches = ns.Net:Matches()
	frame.status:SetText(self:StatusLine(#matches))
	frame.modeButton:SetText(L["BTN_MODE"]:format(L["MODE_" .. ns.db.profile.mode]))

	local emptyText
	if ns.InInstance() then
		emptyText = L["INSTANCE"]
	elseif ns.db.profile.mode == "off" then
		emptyText = L["OFF_HINT"]
	elseif not next(ns.Quests.quests or {}) then
		emptyText = L["NO_QUESTS"]
	elseif #matches == 0 then
		emptyText = L["NO_PEERS"]
	end
	frame.empty:SetText(emptyText or "")
	frame.empty:SetShown(emptyText ~= nil)

	for index, row in ipairs(frame.rows) do
		local match = not emptyText and matches[index]
		row.match = match or nil
		if match then
			local peer = match.peer
			row.name:SetText(classColor(peer.classID) .. Ambiguate(match.name, "short") .. "|r " .. GREY .. (peer.level or "?") .. "|r")
			row.layer:SetText(layerText(match.cmp.layer))
			row.detail:SetText(self:SharedSummary(match.cmp, 2))
			if match.action == "join" then
				row.button:SetText(L["BTN_JOIN"])
			else
				row.button:SetText(L["BTN_INVITE"])
			end
			row.button:SetEnabled(match.action ~= "none" and not ns.Net.pending[match.name])
			row:Show()
		else
			row:Hide()
		end
	end
end

function UI:ShowRequest(request)
	local summary = self:SharedSummary(request.cmp, 3)
	local text = L["REQUEST_TEXT"]:format(Ambiguate(request.sender, "short"), summary, L["MOVE_" .. request.moves])
	StaticPopup_Show("SHARDMATES_REQUEST", text, nil, request)
end

function UI:ShowDissolve()
	StaticPopup_Show("SHARDMATES_DISSOLVE")
end
