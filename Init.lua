-- Addon object, saved settings and small helpers shared by all modules.
local ADDON_NAME, ns = ...

local addon = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
ns.addon = addon
ns.L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

ns.DEFAULTS = {
	profile = {
		mode = "ask",
		tagHelper = true,
		tagWhisper = true,
		dissolvePrompt = true,
		debug = false,
		minimap = { hide = false },
	},
}

-- Secret values arrive from restricted APIs; treat them as missing data.
local issecretvalue = issecretvalue or function()
	return false
end

function ns.Usable(value)
	return value ~= nil and not issecretvalue(value)
end

-- Registers an event that may be missing on other clients without breaking the load.
function ns.SafeRegister(module, event, handler)
	local ok = pcall(module.RegisterEvent, module, event, handler)
	return ok
end

function ns.Debug(...)
	if ns.db and ns.db.profile.debug then
		print("|cff7fbfffShardmates|r", ...)
	end
end

function ns.Print(...)
	print("|cff7fbfffShardmates|r", ...)
end

-- "s" solo, "l<count>" party leader, "m<count>" party member.
function ns.GroupState()
	if not IsInGroup() then
		return "s"
	end
	local count = GetNumGroupMembers()
	if UnitIsGroupLeader("player") then
		return "l" .. count
	end
	return "m" .. count
end

function ns.MyID()
	local guid = UnitGUID("player")
	if ns.Usable(guid) then
		return guid:sub(-8)
	end
	return ""
end

-- "A" or "H": players of the other faction cannot group with us and are never listed.
function ns.Faction()
	return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

function ns.InInstance()
	local inInstance = IsInInstance()
	return inInstance and true or false
end

-- Zone-level map for the player: caves and sub-maps roll up to their zone,
-- so players inside and outside a cave land on the same channel.
function ns.ZoneMapID()
	local mapID = C_Map.GetBestMapForUnit("player")
	local guard = 0
	while mapID and guard < 8 do
		local info = C_Map.GetMapInfo(mapID)
		if not info or info.mapType <= Enum.UIMapType.Zone or not info.parentMapID or info.parentMapID == 0 then
			break
		end
		mapID = info.parentMapID
		guard = guard + 1
	end
	return mapID
end

-- Name usable for invites and whispers. Forever has region-unique two-part names
-- ("Given Family"); other clients use "Name-Realm".
function ns.QualifiedUnitName(unit)
	local getName = UnitNameUnmodified or UnitName
	local name, qualifier = getName(unit)
	if not ns.Usable(name) or name == "" then
		return nil
	end
	if not ns.Usable(qualifier) or qualifier == "" then
		qualifier = nil
	end
	if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
		local separators = Constants and Constants.CharacterNameSeparatorConsts
		local separator = separators and separators.CHARACTERNAME_SURNAME_SEPARATOR or " "
		if qualifier and not name:find(separator, 1, true) then
			return name .. separator .. qualifier
		end
		return name
	end
	if qualifier then
		return name .. "-" .. qualifier
	end
	return name
end
