-- Reads the player's unfinished quests in the current zone and their objective kinds.
local _, ns = ...
local addon, Logic = ns.addon, ns.Logic

local Quests = addon:NewModule("Quests", "AceEvent-3.0", "AceTimer-3.0")
ns.Quests = Quests

Quests.mapID = nil
Quests.quests = {}
Quests.titles = {}
Quests.signature = ""

function Quests:OnEnable()
	self:RegisterEvent("QUEST_LOG_UPDATE", "Schedule")
	self:RegisterEvent("QUEST_ACCEPTED", "Schedule")
	self:RegisterEvent("QUEST_REMOVED", "Schedule")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "Schedule")
	self:RegisterEvent("ZONE_CHANGED", "Schedule")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Schedule")
	self:Schedule()
end

-- QUEST_LOG_UPDATE fires in bursts; one read after the burst is enough.
function Quests:Schedule()
	if not self.timer then
		self.timer = self:ScheduleTimer("Refresh", 1.5)
	end
end

local function questsOnMap(mapID)
	local set = {}
	local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
	if ok and type(list) == "table" then
		for _, info in ipairs(list) do
			if info.questID then
				set[info.questID] = true
			end
		end
	end
	return set
end

function Quests:Read()
	local mapID = ns.ZoneMapID()
	local quests, titles = {}, {}
	if not mapID then
		return mapID, quests, titles
	end
	local onMap = questsOnMap(mapID)
	local playerMap = C_Map.GetBestMapForUnit("player")
	if playerMap and playerMap ~= mapID then
		for questID in pairs(questsOnMap(playerMap)) do
			onMap[questID] = true
		end
	end
	local entries = C_QuestLog.GetNumQuestLogEntries()
	for index = 1, entries or 0 do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
			titles[info.questID] = info.title
			if (onMap[info.questID] or info.isOnMap) and not C_QuestLog.IsComplete(info.questID) then
				local flags = Logic.QuestFlags(C_QuestLog.GetQuestObjectives(info.questID), info.suggestedGroup)
				if flags ~= "" then
					quests[info.questID] = flags
				end
			end
		end
	end
	return mapID, quests, titles
end

function Quests:Refresh()
	self.timer = nil
	local mapID, quests, titles = self:Read()
	self.mapID, self.quests, self.titles = mapID, quests, titles
	local signature = tostring(mapID) .. ":" .. Logic.EncodePresence({ quests = quests })
	if signature ~= self.signature then
		self.signature = signature
		self:SendMessage("SHARDMATES_QUESTS_CHANGED")
	end
end

function Quests:Title(questID)
	return self.titles[questID] or C_QuestLog.GetTitleForQuestID(questID) or ("#" .. questID)
end
