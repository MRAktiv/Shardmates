-- Pure logic: GUID parsing, objective kinds, wire protocol, matching and group decisions.
-- No WoW API calls here, so the whole file runs under the offline test harness.
local _, ns = ...

local Logic = {}
ns.Logic = Logic

local PROTOCOL = "1"
local MAX_QUESTS = 28

Logic.PROTOCOL = PROTOCOL

-- Objective kind letters, also used on the wire.
-- k: kill objective, credit is shared inside a party
-- c: collect or click objective, every drop or click goes to one player
-- e: event objective (escort, explore), shared and tied to the current world
-- g: quest is marked for a group
local KIND_BY_TYPE = {
	monster = "k",
	item = "c",
	object = "c",
	event = "e",
}

function Logic.ObjectiveKind(objectiveType)
	return KIND_BY_TYPE[objectiveType]
end

-- Builds the flag string for one quest from its objectives, counting unfinished ones only.
function Logic.QuestFlags(objectives, suggestedGroup)
	local has = {}
	for _, objective in ipairs(objectives or {}) do
		if not objective.finished then
			local kind = KIND_BY_TYPE[objective.type]
			if kind then
				has[kind] = true
			end
		end
	end
	local flags = (has.k and "k" or "") .. (has.c and "c" or "") .. (has.e and "e" or "")
	if flags ~= "" and suggestedGroup and suggestedGroup > 1 then
		flags = flags .. "g"
	end
	return flags
end

-- Creature GUID: Creature-0-<server>-<instance>-<zoneUID>-<npcID>-<spawnUID>.
-- The server and zoneUID pair identifies the world copy (layer) the creature lives in.
function Logic.ParseCreatureGUID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, server, zoneUID, npcID = guid:match("^(%a+)%-%d+%-(%d+)%-%d+%-(%d+)%-(%d+)%-%x+$")
	if kind ~= "Creature" and kind ~= "Vehicle" then
		return nil
	end
	if zoneUID == "0" or server == "0" then
		return nil
	end
	return server, zoneUID, tonumber(npcID)
end

function Logic.LayerKeyFromGUID(guid)
	local server, zoneUID = Logic.ParseCreatureGUID(guid)
	if server then
		return server .. "-" .. zoneUID
	end
	return nil
end

-- Layer tracker: switches the current layer only after two different creatures agree,
-- so a single odd NPC cannot flip the result.
function Logic.NewLayerTracker()
	return { current = nil, mapID = nil, pending = nil, seen = {} }
end

function Logic.ObserveLayer(tracker, mapID, key, guid, now)
	if not key then
		return false
	end
	if tracker.mapID ~= mapID then
		tracker.mapID = mapID
		tracker.current = nil
		tracker.pending = nil
		tracker.seen = {}
	end
	if not tracker.seen[key] then
		tracker.seen[key] = { first = now, order = 0 }
		local count = 0
		for _ in pairs(tracker.seen) do
			count = count + 1
		end
		tracker.seen[key].order = count
	end
	local entry = tracker.seen[key]
	entry.last = now
	entry.guids = entry.guids or {}
	if guid and not entry.guids[guid] then
		entry.guids[guid] = true
		entry.npcs = (entry.npcs or 0) + 1
	end
	if tracker.current == key then
		tracker.pending = nil
		return false
	end
	local pending = tracker.pending
	if pending and pending.key == key and pending.guid ~= guid then
		tracker.current = key
		tracker.pending = nil
		return true
	end
	if not pending or pending.key ~= key then
		tracker.pending = { key = key, guid = guid }
	end
	return false
end

function Logic.ResetLayer(tracker)
	tracker.current = nil
	tracker.pending = nil
end

-- Short local label for a layer key: A, B, C in the order this client met them on the map.
function Logic.LayerLabel(tracker, key)
	local entry = key and tracker.seen[key]
	if not entry then
		return "?"
	end
	return string.char(64 + math.min(entry.order, 26))
end

-- "4621-37 x3, 4621-41 x1": every layer key met on this map and how many different creatures showed it.
function Logic.LayerSummary(tracker)
	local keys = {}
	for key in pairs(tracker.seen) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		return tracker.seen[a].order < tracker.seen[b].order
	end)
	for index, key in ipairs(keys) do
		keys[index] = key .. " x" .. (tracker.seen[key].npcs or 0)
	end
	return table.concat(keys, ", ")
end

local function toBase36(number)
	local digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	local out = ""
	repeat
		local rest = number % 36
		out = digits:sub(rest + 1, rest + 1) .. out
		number = math.floor(number / 36)
	until number == 0
	return out
end

Logic.ToBase36 = toBase36

local MAX_MESSAGE = 255

-- Quests worth grouping for (kill or event objectives) go first, then by quest ID.
local function questOrder(quests)
	local ids = {}
	for questID in pairs(quests) do
		ids[#ids + 1] = questID
	end
	local function rank(questID)
		local flags = quests[questID]
		return (flags:find("k", 1, true) or flags:find("e", 1, true)) and 0 or 1
	end
	table.sort(ids, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	return ids
end

-- Presence: P1;<id>;<faction>;<map>;<layer>;<level>;<class>;<group>;<mode>;<quests>
-- quests: "<questID base36 upper><flags lower>" joined with commas, cut to fit one addon message.
function Logic.EncodePresence(me)
	local header = table.concat({
		"P" .. PROTOCOL,
		me.id or "",
		me.faction or "",
		tostring(me.mapID or 0),
		me.layer or "-",
		tostring(me.level or 0),
		tostring(me.classID or 0),
		me.group or "s",
		me.mode or "a",
	}, ";") .. ";"
	local budget = MAX_MESSAGE - #header
	local parts, used = {}, 0
	local quests = me.quests or {}
	for _, questID in ipairs(questOrder(quests)) do
		if #parts >= MAX_QUESTS then
			break
		end
		local entry = toBase36(questID) .. quests[questID]
		local cost = #entry + (#parts > 0 and 1 or 0)
		if used + cost > budget then
			break
		end
		parts[#parts + 1] = entry
		used = used + cost
	end
	return header .. table.concat(parts, ",")
end

function Logic.DecodePresence(text)
	if type(text) ~= "string" then
		return nil
	end
	local tag, id, faction, mapID, layer, level, classID, group, mode, questList =
		text:match("^(P%d+);([^;]*);([^;]*);(%d+);([^;]*);(%d+);(%d+);([^;]*);([^;]*);([^;]*)$")
	if tag ~= "P" .. PROTOCOL then
		return nil
	end
	local quests = {}
	for entry in questList:gmatch("[^,]+") do
		local idText, flags = entry:match("^([0-9A-Z]+)([kceg]*)$")
		if idText and flags ~= "" then
			quests[tonumber(idText, 36)] = flags
		end
	end
	return {
		id = id,
		faction = faction,
		mapID = tonumber(mapID),
		layer = layer ~= "-" and layer or nil,
		level = tonumber(level),
		classID = tonumber(classID),
		group = group,
		mode = mode,
		quests = quests,
	}
end

-- Request:  R1;<questID>;<dir>   dir "i" = sender invites, "j" = sender asks to be invited
-- Answer:   A1;<questID>;<dir>   accepted, same dir as the request
-- Decline:  D1;<questID>;<reason>
function Logic.EncodeRequest(kind, questID, value)
	return kind .. PROTOCOL .. ";" .. tostring(questID or 0) .. ";" .. (value or "")
end

function Logic.DecodeRequest(text)
	if type(text) ~= "string" then
		return nil
	end
	local kind, version, questID, value = text:match("^([RAD])(%d+);(%d+);(%a*)$")
	if not kind or version ~= PROTOCOL then
		return nil
	end
	return kind, tonumber(questID), value
end

local function hasFlag(flags, letter)
	return flags ~= nil and flags:find(letter, 1, true) ~= nil
end

-- Compares my quests with a peer. Kill and event objectives are worth grouping for,
-- collect objectives make players split the drops.
function Logic.Compare(me, peer)
	local result = { shared = {}, worth = false, kills = 0, events = 0, splits = 0, layer = "unknown" }
	for questID, myFlags in pairs(me.quests or {}) do
		local peerFlags = peer.quests and peer.quests[questID]
		if peerFlags then
			local entry = { questID = questID, group = hasFlag(myFlags, "g") or hasFlag(peerFlags, "g") }
			if hasFlag(myFlags, "k") and hasFlag(peerFlags, "k") then
				entry.kill = true
				result.kills = result.kills + 1
			end
			if hasFlag(myFlags, "e") and hasFlag(peerFlags, "e") then
				entry.event = true
				result.events = result.events + 1
			end
			if hasFlag(myFlags, "c") and hasFlag(peerFlags, "c") then
				entry.split = true
				result.splits = result.splits + 1
			end
			if entry.kill or entry.event or entry.split then
				result.shared[#result.shared + 1] = entry
			end
		end
	end
	table.sort(result.shared, function(a, b)
		return a.questID < b.questID
	end)
	result.worth = result.kills > 0 or result.events > 0
	if me.layer and peer.layer then
		result.layer = me.layer == peer.layer and "same" or "other"
	end
	return result
end

local function groupSize(group)
	return tonumber((group or ""):match("^%a(%d+)$")) or 1
end

-- Who should invite whom. The party leader stays in their world and the joiner moves,
-- so the side whose world matters has to be the one who sends the invite.
-- Returns action ("invite", "join", "none"), who moves ("peer", "me", "nobody") and a reason code.
function Logic.Decide(me, peer, comparison)
	local myGroup = (me.group or "s"):sub(1, 1)
	local peerGroup = (peer.group or "s"):sub(1, 1)
	if me.faction and peer.faction and me.faction ~= "" and peer.faction ~= "" and me.faction ~= peer.faction then
		return "none", "nobody", "faction"
	end
	if myGroup == "m" then
		return "none", "nobody", "you_member"
	end
	if peerGroup == "m" then
		return "none", "nobody", "peer_member"
	end
	if myGroup == "l" and peerGroup == "l" then
		return "none", "nobody", "both_groups"
	end
	local sameLayer = comparison and comparison.layer == "same"
	if myGroup == "l" then
		if groupSize(me.group) >= 5 then
			return "none", "nobody", "full"
		end
		return "invite", sameLayer and "nobody" or "peer", "you_lead"
	end
	if peerGroup == "l" then
		if groupSize(peer.group) >= 5 then
			return "none", "nobody", "full"
		end
		return "join", sameLayer and "nobody" or "me", "peer_leads"
	end
	if sameLayer then
		return "invite", "nobody", "same_layer"
	end
	return "invite", "peer", "you_keep_world"
end

-- After a group formed: is there still something worth doing together?
-- Returns hasWork and whether an event objective (escort) is still running.
function Logic.SharedWork(me, members)
	local hasWork, eventActive = false, false
	for _, member in ipairs(members or {}) do
		local comparison = Logic.Compare(me, member)
		if comparison.worth then
			hasWork = true
		end
		if comparison.events > 0 then
			eventActive = true
		end
	end
	return hasWork, eventActive
end
