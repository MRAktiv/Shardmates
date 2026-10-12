-- Detects the world copy (layer) the player is in from GUIDs of nearby creatures.
local _, ns = ...
local addon, Logic, L = ns.addon, ns.Logic, ns.L

local Layer = addon:NewModule("Layer", "AceEvent-3.0", "AceTimer-3.0")
ns.Layer = Layer

Layer.tracker = Logic.NewLayerTracker()
Layer.lastGUID = nil

function Layer:OnEnable()
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnUnitEvent")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTarget")
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "OnMouseover")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoster")
	ns.SafeRegister(self, "SHARD_TRANSFER", "OnShardTransfer")
	self.groupState = ns.GroupState()
	self:ScheduleRepeatingTimer("ScanPlates", 5)
end

-- Nameplates already on screen never fire NAME_PLATE_UNIT_ADDED again, so read them while the layer is unknown.
function Layer:ScanPlates()
	if self.tracker.current then
		return
	end
	for index = 1, 40 do
		local unit = "nameplate" .. index
		if UnitExists(unit) then
			self:Observe(unit)
		end
	end
end

function Layer:StatusText()
	local label = self:Label()
	if label then
		return L["LAYER_KNOWN"]:format(label)
	end
	if self.tracker.pending then
		return L["LAYER_PENDING"]
	end
	return L["LAYER_UNKNOWN"]
end

function Layer:OnTarget()
	self:Observe("target")
end

function Layer:OnMouseover()
	self:Observe("mouseover")
end

function Layer:OnUnitEvent(_, unit)
	self:Observe(unit)
end

function Layer:Observe(unit)
	if not unit or ns.InInstance() or (UnitOnTaxi and UnitOnTaxi("player")) then
		return
	end
	local guid = UnitGUID(unit)
	if not ns.Usable(guid) then
		return
	end
	local key = Logic.LayerKeyFromGUID(guid)
	if not key then
		return
	end
	local mapID = ns.ZoneMapID()
	if not mapID then
		return
	end
	self.lastGUID = guid
	if Logic.ObserveLayer(self.tracker, mapID, key, guid, GetTime()) then
		ns.Debug("layer", key)
		self:SendMessage("SHARDMATES_LAYER_CHANGED", key)
	end
end

-- Joining someone else's party moves the player into the leader's world.
function Layer:OnRoster()
	local state = ns.GroupState()
	local before = self.groupState
	self.groupState = state
	if state:sub(1, 1) == "m" and before:sub(1, 1) ~= "m" then
		self:Forget()
	end
end

function Layer:OnShardTransfer()
	self:Forget()
end

function Layer:Forget()
	if self.tracker.current then
		Logic.ResetLayer(self.tracker)
		self:SendMessage("SHARDMATES_LAYER_CHANGED", nil)
	end
end

function Layer:Current()
	return self.tracker.current
end

function Layer:Label()
	local key = self.tracker.current
	if not key then
		return nil
	end
	return Logic.LayerLabel(self.tracker, key)
end
