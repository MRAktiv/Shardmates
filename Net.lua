-- Talks to other Shardmates users: zone channel presence, party presence and grouping requests.
local _, ns = ...
local addon, Logic, L = ns.addon, ns.Logic, ns.L

local Net = addon:NewModule("Net", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0")
ns.Net = Net

local PREFIX = "Shardmates"
local CHANNEL_BASE = "Shardmates"
local HEARTBEAT = 90
local PEER_TTL = 240
local REQUEST_TTL = 45
local INVITE_WAIT = 60
local JOIN_WAIT = 60
local MAX_CHANNELS = 20
local ZONE_CHANNEL = Enum.PermanentChatChannelType and Enum.PermanentChatChannelType.Zone or 1

-- True once a game zone channel (General, LocalDefense) holds a number. A channel joined
-- before them takes their number, and /1 stops being General.
local function zoneChannelsJoined()
	if not (C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier) then
		return true
	end
	for index = 1, MAX_CHANNELS do
		local id = GetChannelName(index)
		if type(id) == "number" and id > 0 then
			local info = C_ChatInfo.GetChannelInfoFromIdentifier(tostring(id))
			if info and info.channelType == ZONE_CHANNEL then
				return true
			end
		end
	end
	return false
end

Net.peers = {}
Net.party = {}
Net.pending = {}
Net.expectInvite = {}
Net.managed = nil
Net.lastText = nil
Net.lastSent = 0
Net.lastResult = nil

function Net:OnEnable()
	self.enabledAt = GetTime()
	-- Channels the server kept from the last session come back before the zone channels; give their numbers up.
	if not zoneChannelsJoined() then
		for index = 1, MAX_CHANNELS do
			local id, name = GetChannelName(index)
			if type(id) == "number" and id > 0 and type(name) == "string" and name:match("^" .. CHANNEL_BASE .. "%d+$") then
				self.restored = true
				pcall(LeaveChannelByName, name)
			end
		end
	end
	self:RegisterComm(PREFIX, "OnComm")
	self:RegisterMessage("SHARDMATES_QUESTS_CHANGED", "OnStateChanged")
	self:RegisterMessage("SHARDMATES_LAYER_CHANGED", "OnStateChanged")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoster")
	self:RegisterEvent("PARTY_INVITE_REQUEST", "OnInvite")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnStateChanged")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnStateChanged")
	local filter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if filter then
		for _, event in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL" }) do
			filter(event, Net.HideOwnChannel)
		end
	end
	self:ScheduleRepeatingTimer("Tick", 15)
	self:ScheduleTimer("OnStateChanged", 5)
end

-- Chat filter: hides join notices and text of the Shardmates zone channels.
-- The first argument is the message itself, so only the channel fields after it are checked.
function Net.HideOwnChannel(_, _, ...)
	for index = 2, select("#", ...) do
		local value = select(index, ...)
		if type(value) == "string" and ns.Usable(value) and value:find(CHANNEL_BASE .. "%d") then
			return true
		end
	end
	return false
end

-- Several state changes in a row produce one presence message.
function Net:QueuePresence(delay)
	if self.presenceTimer then
		return
	end
	self.presenceTimer = self:ScheduleTimer(function()
		self.presenceTimer = nil
		self:SendPresence(true)
	end, delay)
end

function Net:Active()
	return ns.db.profile.mode ~= "off" and not ns.InInstance()
end

-- Channel per zone keeps traffic to players who can actually meet.
function Net:ChannelID()
	if not self.channelName then
		return nil
	end
	local id = GetChannelName(self.channelName)
	if type(id) == "number" and id > 0 then
		return id
	end
	return nil
end

function Net:LeaveChannel()
	if self.channelName then
		pcall(LeaveChannelByName, self.channelName)
		self.channelName = nil
	end
end

function Net:UpdateChannel()
	if not self:Active() then
		self:LeaveChannel()
		return
	end
	local zone = ns.ZoneMapID()
	if not zone then
		return
	end
	local name = CHANNEL_BASE .. zone
	if self.channelName == name and self:ChannelID() then
		return
	end
	if not zoneChannelsJoined() and GetTime() - self.enabledAt < JOIN_WAIT then
		return
	end
	self:LeaveChannel()
	self.channelName = name
	local join = JoinTemporaryChannel or JoinChannelByName
	local ok, err = pcall(join, name)
	self.joinResult = ok and "ok" or tostring(err)
	ns.Debug("join", name, self.joinResult)
	-- presence sent before the join reached nobody on the channel
	self:QueuePresence(2)
end

function Net:BuildMe()
	local mode = ns.db.profile.mode
	return {
		id = ns.MyID(),
		faction = ns.Faction(),
		mapID = ns.Quests.mapID,
		layer = ns.Layer:Current(),
		level = UnitLevel("player"),
		classID = select(3, UnitClass("player")),
		group = ns.GroupState(),
		mode = mode == "auto" and "a" or "q",
		quests = ns.Quests.quests or {},
	}
end

function Net:SendPresence(force)
	if not self:Active() then
		return
	end
	local me = self:BuildMe()
	if not next(me.quests) then
		return
	end
	local text = Logic.EncodePresence(me)
	local now = GetTime()
	if not force and text == self.lastText and now - self.lastSent < HEARTBEAT then
		return
	end
	local id = self:ChannelID()
	if id then
		self:SendCommMessage(PREFIX, text, "CHANNEL", id, "BULK")
	end
	if IsInGroup() and not IsInRaid() then
		self:SendCommMessage(PREFIX, text, "PARTY", nil, "NORMAL")
	end
	self.lastText, self.lastSent = text, now
end

function Net:OnStateChanged()
	self:UpdateChannel()
	-- the channel id appears a moment after joining
	self:QueuePresence(2)
	self:SendMessage("SHARDMATES_PEERS_CHANGED")
end

function Net:Tick()
	self:UpdateChannel()
	self:SendPresence(false)
	self:Expire()
	self:CheckManaged()
end

function Net:Expire()
	local now = GetTime()
	local changed = false
	for name, peer in pairs(self.peers) do
		if now - peer.seen > PEER_TTL then
			self.peers[name] = nil
			changed = true
		end
	end
	for name, request in pairs(self.pending) do
		if now - request.time > REQUEST_TTL then
			self.pending[name] = nil
			ns.Print(L["REQUEST_TIMEOUT"]:format(Ambiguate(name, "short")))
		end
	end
	for name, at in pairs(self.expectInvite) do
		if now - at > INVITE_WAIT then
			self.expectInvite[name] = nil
		end
	end
	if changed then
		self:SendMessage("SHARDMATES_PEERS_CHANGED")
	end
end

function Net:OnComm(_, text, distribution, sender)
	if type(text) ~= "string" or not ns.Usable(sender) then
		return
	end
	local head = text:sub(1, 1)
	if head == "P" then
		local peer = Logic.DecodePresence(text)
		if not peer or peer.id == ns.MyID() or peer.faction ~= ns.Faction() then
			return
		end
		peer.name, peer.seen = sender, GetTime()
		if distribution == "PARTY" then
			self.party[sender] = peer
		else
			self.peers[sender] = peer
			self:SendMessage("SHARDMATES_PEERS_CHANGED")
		end
	elseif head == "T" then
		if ns.Diag then
			ns.Diag:OnEcho(text, sender)
		end
	elseif distribution == "WHISPER" then
		local kind, questID, value = Logic.DecodeRequest(text)
		if kind then
			self:OnRequest(sender, kind, questID, value)
		end
	end
end

-- Players I can group with in this zone, best first.
function Net:Matches()
	local me = self:BuildMe()
	local now = GetTime()
	local list = {}
	for name, peer in pairs(self.peers) do
		if now - peer.seen <= PEER_TTL and peer.mapID == me.mapID and not UnitInParty(Ambiguate(name, "none")) then
			local comparison = Logic.Compare(me, peer)
			if #comparison.shared > 0 then
				local action, moves, reason = Logic.Decide(me, peer, comparison)
				list[#list + 1] = { name = name, peer = peer, cmp = comparison, action = action, moves = moves, reason = reason }
			end
		end
	end
	local layerRank = { same = 0, unknown = 1, other = 2 }
	table.sort(list, function(a, b)
		if a.cmp.worth ~= b.cmp.worth then
			return a.cmp.worth
		end
		if a.cmp.layer ~= b.cmp.layer then
			return layerRank[a.cmp.layer] < layerRank[b.cmp.layer]
		end
		if a.cmp.kills ~= b.cmp.kills then
			return a.cmp.kills > b.cmp.kills
		end
		return a.name < b.name
	end)
	return list, me
end

function Net:FirstSharedQuest(comparison)
	local shared = comparison.shared[1]
	return shared and shared.questID or 0
end

-- action "invite": I lead and the peer joins me; "join": the peer leads and I join.
function Net:Request(match)
	if match.action ~= "invite" and match.action ~= "join" then
		return
	end
	local direction = match.action == "invite" and "i" or "j"
	local questID = self:FirstSharedQuest(match.cmp)
	self.pending[match.name] = { direction = direction, questID = questID, time = GetTime() }
	self:SendCommMessage(PREFIX, Logic.EncodeRequest("R", questID, direction), "WHISPER", match.name, "ALERT")
	ns.Print(L["REQUEST_SENT"]:format(Ambiguate(match.name, "short")))
end

function Net:OnRequest(sender, kind, questID, value)
	if kind == "R" then
		self:OnIncomingRequest(sender, questID, value)
	elseif kind == "A" then
		local request = self.pending[sender]
		if not request or request.direction ~= value then
			return
		end
		self.pending[sender] = nil
		self.managed = { since = GetTime(), partner = sender }
		if value == "i" then
			C_PartyInfo.InviteUnit(sender)
		else
			self.expectInvite[sender] = GetTime()
		end
	elseif kind == "D" then
		if self.pending[sender] then
			self.pending[sender] = nil
			ns.Print(L["REQUEST_DECLINED"]:format(Ambiguate(sender, "short")))
		end
	end
end

-- The request direction is from the sender's side: "i" means the sender will invite me.
function Net:OnIncomingRequest(sender, questID, direction)
	if direction ~= "i" and direction ~= "j" then
		return
	end
	local mode = ns.db.profile.mode
	if mode == "off" or ns.InInstance() then
		self:SendCommMessage(PREFIX, Logic.EncodeRequest("D", questID, "off"), "WHISPER", sender, "ALERT")
		return
	end
	local me = self:BuildMe()
	local peer = self.peers[sender] or { quests = {}, group = direction == "i" and "l" or "s" }
	local comparison = Logic.Compare(me, peer)
	-- From my side: "i" means I will be invited and move, "j" means they join me.
	local myAction = direction == "i" and "join" or "invite"
	local moves
	if comparison.layer == "same" then
		moves = "nobody"
	else
		moves = myAction == "join" and "me" or "peer"
	end
	local request = { sender = sender, questID = questID, direction = direction, moves = moves, cmp = comparison }
	if mode == "auto" and comparison.worth and moves ~= "me" then
		self:AcceptRequest(request)
		return
	end
	if ns.UI then
		ns.UI:ShowRequest(request)
	end
end

function Net:AcceptRequest(request)
	local sender = request.sender
	self:SendCommMessage(PREFIX, Logic.EncodeRequest("A", request.questID, request.direction), "WHISPER", sender, "ALERT")
	self.managed = { since = GetTime(), partner = sender }
	if request.direction == "j" then
		C_PartyInfo.InviteUnit(sender)
	else
		self.expectInvite[sender] = GetTime()
	end
end

function Net:DeclineRequest(request)
	self:SendCommMessage(PREFIX, Logic.EncodeRequest("D", request.questID, "busy"), "WHISPER", request.sender, "ALERT")
end

-- Accept only the invite this addon agreed to, matched by the inviter's GUID suffix.
function Net:OnInvite(_, name, _, _, _, _, _, inviterGUID)
	local now = GetTime()
	for sender, at in pairs(self.expectInvite) do
		local peer = self.peers[sender]
		local guidMatch = ns.Usable(inviterGUID) and peer and peer.id ~= "" and inviterGUID:sub(-8) == peer.id
		local nameMatch = ns.Usable(name) and Ambiguate(name, "none") == Ambiguate(sender, "none")
		if now - at <= INVITE_WAIT and (guidMatch or nameMatch) then
			self.expectInvite[sender] = nil
			AcceptGroup()
			StaticPopup_Hide("PARTY_INVITE")
			return
		end
	end
end

function Net:OnRoster()
	if not IsInGroup() then
		self.managed = nil
		self.party = {}
		self.dissolveShown = nil
	end
	self:QueuePresence(1)
	self:SendMessage("SHARDMATES_PEERS_CHANGED")
end

-- Members of the current party with fresh presence data.
function Net:PartyData()
	local now = GetTime()
	local members = {}
	for name, peer in pairs(self.party) do
		if now - peer.seen <= PEER_TTL and UnitInParty(Ambiguate(name, "none")) then
			members[#members + 1] = peer
		end
	end
	return members
end

-- A party formed by this addon gets an offer to part ways once nothing is shared.
function Net:CheckManaged()
	if not self.managed or not IsInGroup() or IsInRaid() or InCombatLockdown() or ns.InInstance() then
		return
	end
	if GetTime() - self.managed.since < 60 then
		return
	end
	local members = self:PartyData()
	if #members == 0 then
		return
	end
	local hasWork, eventActive = Logic.SharedWork(self:BuildMe(), members)
	if eventActive then
		if not self.escortWarned then
			self.escortWarned = true
			ns.Print(L["ESCORT_WARNING"])
		end
		return
	end
	self.escortWarned = nil
	if not hasWork and ns.db.profile.dissolvePrompt and not self.dissolveShown and ns.UI then
		self.dissolveShown = true
		ns.UI:ShowDissolve()
	end
end
