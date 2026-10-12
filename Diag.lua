-- /shardmates diag: checks in the live client every assumption the offline tests cannot cover.
local _, ns = ...
local addon, Logic, L = ns.addon, ns.Logic, ns.L

local Diag = addon:NewModule("Diag", "AceTimer-3.0")
ns.Diag = Diag

local PREFIX = "Shardmates"

Diag.lines = {}

-- Every diagnostic line goes to chat and to the copy window.
local function out(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(index, ...)))
	end
	local line = table.concat(parts, " ")
	Diag.lines[#Diag.lines + 1] = line
	print("|cff7fbfffSM|r", line)
	Diag:UpdateCopy()
end

local function shape(name)
	return (tostring(name or ""):gsub("[^%s%-]", "x"))
end

local function has(path)
	local value = _G
	for part in path:gmatch("[^%.]+") do
		value = type(value) == "table" and value[part] or nil
	end
	return value ~= nil and "yes" or "NO"
end

local function resultName(code)
	if type(code) ~= "number" or not Enum.SendAddonMessageResult then
		return tostring(code)
	end
	for name, value in pairs(Enum.SendAddonMessageResult) do
		if value == code then
			return name
		end
	end
	return tostring(code)
end

function Diag:Run()
	self.lines = {}
	self:ShowCopy()
	self:Collect(out)
	self:Echo()
end

-- Every check except the echo, written through out.
function Diag:Collect(out)
	out(L["DIAG_HEADER"])
	local version, build, _, interface = GetBuildInfo()
	out("client", version, build, "interface", interface, "project", tostring(WOW_PROJECT_ID), "locale", GetLocale())

	local apis = {
		"JoinTemporaryChannel", "JoinChannelByName", "LeaveChannelByName", "GetChannelName",
		"C_ChatInfo.SendAddonMessage", "C_QuestLog.GetQuestsOnMap", "C_QuestLog.UnitIsRelatedToActiveQuest",
		"C_PartyInfo.InviteUnit", "AcceptGroup", "issecretvalue", "ChatFrameUtil.AddMessageEventFilter",
	}
	local parts = {}
	for _, name in ipairs(apis) do
		parts[#parts + 1] = name .. "=" .. has(name)
	end
	out("api", table.concat(parts, " "))

	local zone = ns.ZoneMapID()
	local best = C_Map.GetBestMapForUnit("player")
	local info = zone and C_Map.GetMapInfo(zone)
	out("map zone", tostring(zone), info and info.name or "?", "best", tostring(best), "instance", tostring(ns.InInstance()), "group", ns.GroupState())

	local net = ns.Net
	out("channel", tostring(net.channelName), "id", tostring(net:ChannelID()), "join", tostring(net.joinResult), "mode", ns.db.profile.mode)

	local tracker = ns.Layer.tracker
	local seen = 0
	for _ in pairs(tracker.seen) do
		seen = seen + 1
	end
	out("layer", tostring(tracker.current), "label", tostring(ns.Layer:Label()), "pending", tracker.pending and tracker.pending.key or "-", "keys seen", seen)
	out("layer keys", Logic.LayerSummary(tracker))
	local guid = UnitGUID("target")
	if ns.Usable(guid) then
		local server, zoneUID, npcID = Logic.ParseCreatureGUID(guid)
		out("target guid", guid, "parsed", tostring(server), tostring(zoneUID), tostring(npcID))
	elseif guid ~= nil then
		out("target guid is SECRET")
	else
		out("target: none (target an NPC and run diag again)")
	end

	local count, shown = 0, 0
	for questID, flags in pairs(ns.Quests.quests or {}) do
		count = count + 1
		if shown < 6 then
			shown = shown + 1
			local types = {}
			for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
				types[#types + 1] = tostring(objective.type) .. (objective.finished and "+" or "")
			end
			out("quest", questID, ns.Shorten(ns.Quests:Title(questID), 30), flags, table.concat(types, ","))
		end
	end
	out("quests in zone", count)

	local fresh = 0
	for _, peer in pairs(net.peers) do
		if GetTime() - peer.seen < 240 then
			fresh = fresh + 1
		end
	end
	out("peers fresh", fresh, "party data", #net:PartyData(), "matches", #(net:Matches()))

	local regional = RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() or false
	out("names regional", tostring(regional), "mine", shape(ns.QualifiedUnitName("player")))
	for sender in pairs(net.peers) do
		out("peer name", shape(sender))
		break
	end
end

-- Sends a ping to the zone channel and waits for our own copy to come back.
function Diag:Echo()
	local id = ns.Net:ChannelID()
	if not id then
		out(L["DIAG_ECHO_FAIL"], "(no channel id)")
		return
	end
	self.nonce = tostring(math.random(100000, 999999))
	self.sentAt = GetTime()
	local ok, code = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "T1;" .. self.nonce, "CHANNEL", id)
	out("send channel", ok and resultName(code) or ("error " .. tostring(code)))
	if IsInGroup() and not IsInRaid() then
		local okParty, codeParty = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "T1;p" .. self.nonce, "PARTY")
		out("send party", okParty and resultName(codeParty) or ("error " .. tostring(codeParty)))
	end
	self.echoTimer = self:ScheduleTimer(function()
		if self.nonce then
			out(L["DIAG_ECHO_FAIL"])
			self.nonce = nil
		end
	end, 5)
end

function Diag:OnEcho(text, sender)
	local nonce = text:match("^T1;p?(%d+)$")
	if nonce and nonce == self.nonce then
		out(L["DIAG_ECHO_OK"]:format(GetTime() - self.sentAt), text:find(";p", 1, true) and "party" or "channel", "sender", shape(sender))
		if not text:find(";p", 1, true) then
			self.nonce = nil
		end
	end
end

-- Chat text cannot be copied in WoW, so the report also sits in a selectable box.
function Diag:ShowCopy()
	local AceGUI = LibStub("AceGUI-3.0", true)
	if not AceGUI then
		return
	end
	if not self.window then
		local window = AceGUI:Create("Frame")
		window:SetTitle(L["TITLE"])
		window:SetStatusText(L["DIAG_COPY"])
		window:SetLayout("Fill")
		window:SetWidth(640)
		window:SetHeight(420)
		window:SetCallback("OnClose", function(widget)
			AceGUI:Release(widget)
			Diag.window, Diag.box = nil, nil
		end)
		local box = AceGUI:Create("MultiLineEditBox")
		box:SetLabel("")
		box:DisableButton(true)
		window:AddChild(box)
		self.window, self.box = window, box
	end
	self:UpdateCopy()
end

function Diag:UpdateCopy()
	if self.box then
		self.box:SetText(table.concat(self.lines, "\n"))
		self.box:HighlightText()
		self.box:SetFocus()
	end
end
