-- Tag helper: when a quest mob is already tagged by another player, offers to invite that player.
local _, ns = ...
local addon, L = ns.addon, ns.L

local Tagging = addon:NewModule("Tagging", "AceEvent-3.0")
ns.Tagging = Tagging

local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

function Tagging:OnEnable()
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "Evaluate")
	self:RegisterEvent("UNIT_TARGET", "OnUnit")
	self:RegisterEvent("UNIT_FLAGS", "OnUnit")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "Evaluate")
end

function Tagging:OnUnit(_, unit)
	if unit == "target" then
		self:Evaluate()
	end
end

local function questRelated(unit)
	local check = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
	if not check then
		return false
	end
	local ok, related = pcall(check, unit)
	return ok and ns.Usable(related) and related == true
end

-- Name of the player who most likely holds the tag: the target's own target.
local function tagHolder()
	if not UnitIsPlayer("targettarget") or UnitIsUnit("targettarget", "player") then
		return nil
	end
	if UnitInParty("targettarget") or not UnitIsFriend("player", "targettarget") then
		return nil
	end
	return ns.QualifiedUnitName("targettarget")
end

function Tagging:Evaluate()
	local candidate
	if ns.db.profile.tagHelper and not ns.InInstance() and ns.GroupState():sub(1, 1) ~= "m"
		and UnitExists("target") and not UnitIsPlayer("target") and not UnitIsDead("target")
		and UnitIsTapDenied("target") and questRelated("target") then
		candidate = tagHolder()
	end
	self.candidate = candidate
	if candidate then
		self:ShowButton(candidate)
	elseif self.button then
		self.button:Hide()
	end
end

function Tagging:ShowButton(name)
	local button = self.button
	if not button then
		button = CreateFrame("Button", "ShardmatesTagButton", UIParent, "UIPanelButtonTemplate")
		button:SetSize(220, 24)
		button:SetScript("OnClick", function()
			Tagging:Invite()
		end)
		button:SetScript("OnEnter", function(widget)
			GameTooltip:SetOwner(widget, "ANCHOR_BOTTOM")
			GameTooltip:SetText(L["TAG_TOOLTIP"]:format(Ambiguate(Tagging.candidate or "", "short")), nil, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		self.button = button
	end
	button:ClearAllPoints()
	if TargetFrame and TargetFrame:IsShown() then
		button:SetPoint("TOP", TargetFrame, "BOTTOM", 0, 4)
	else
		button:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end
	button:SetText(L["TAG_BUTTON"]:format(Ambiguate(name, "short")))
	button:Show()
end

-- Runs from a click, so the whisper is a player action.
function Tagging:Invite()
	local name = self.candidate
	if not name then
		return
	end
	C_PartyInfo.InviteUnit(name)
	if ns.db.profile.tagWhisper then
		pcall(SendChat, L["TAG_WHISPER"], "WHISPER", nil, name)
	end
	if self.button then
		self.button:Hide()
	end
end
