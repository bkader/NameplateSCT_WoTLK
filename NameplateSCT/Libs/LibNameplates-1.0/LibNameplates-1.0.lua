--[[
	Name: LibNameplates-1.0
	Author(s): Kader (bkader@mail.com)
	Description:
		Alerts addons when a nameplate is shown or hidden.
		Has API to get info such as name, level, class, ect from the nameplate.
		LibNameplates tries to function with the default nameplates, Aloft, caelNamePlates and TidyPlates.
	Dependencies: LibStub, CallbackHandler-1.0
]]
local MAJOR, MINOR = "LibNameplates-1.0", 31
if not LibStub then
	error(MAJOR .. " requires LibStub.")
	return
end

-- Create lib
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- Make sure CallbackHandler exists.
lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)
if not lib.callbacks then
	error(MAJOR .. " CallbackHandler-1.0.")
	return
end

local pairs = pairs
local ipairs = ipairs
local select = select
local wipe = wipe
local tonumber = tonumber
local math_floor = math.floor
local table_insert = table.insert
local format = string.format
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitIsUnit = UnitIsUnit
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local _

local fastOnFinishThrottle = 0.25 -- check combat & threat every x seconds.
local slowOnFinishThrottle = 1 -- Check for lingering mouseover texture and for TidyPlates frame.

local regionOrder = {
	[1] = "threatTexture",
	[2] = "healthBorder",
	[3] = "castBorder",
	[4] = "castShieldIcon",
	[5] = "spellIcon",
	[6] = "highlightTexture",
	[7] = "nameText",
	[8] = "levelText",
	[9] = "skullIcon",
	[10] = "raidIcon",
	[11] = "eliteIcon"
}

local childOrder = {
	[1] = "healthBar",
	[2] = "castBar"
}

local regionIndex = {}
local childIndex = {}

for i, name in ipairs(regionOrder) do
	regionIndex[name] = i
end
for i, name in ipairs(childOrder) do
	childIndex[name] = i
end

local callbackOnHide = "LibNameplates_RecycleNameplate"
local callbackOnShow = "LibNameplates_NewNameplate"
local callbackFoundGUID = "LibNameplates_FoundGUID"
local callbackOnTarget = "LibNameplates_TargetNameplate"
local callbackHealthChanged = "LibNameplates_HealthChange"
local callbackCombatChanged = "LibNameplates_CombatChange"
local callbackThreatChanged = "LibNameplates_ThreatChange"

lib.combatStatus = lib.combatStatus or {}
lib.fakePlate = lib.fakePlate or {}
lib.healthOnValueChangedHooks = lib.healthOnValueChangedHooks or {}
lib.isOnScreen = lib.isOnScreen or {}
lib.nameplates = lib.nameplates or {}
lib.realPlate = lib.realPlate or {}
lib.threatStatus = lib.threatStatus or {}

local debugPrint
do
	local DEBUG = false
	local function CmdHandler()
		DEBUG = not DEBUG
	end
	_G.SlashCmdList["LIBNAMEPLATEDEBUG"] = CmdHandler
	_G.SLASH_LIBNAMEPLATEDEBUG1 = "/lnpbug"

	local print = print
	function debugPrint(...)
		if DEBUG then
			print(MAJOR, ...)
		end
	end
end

local UnitIterator
do
	local GetNumPartyMembers = GetNumPartyMembers
	local GetNumRaidMembers = GetNumRaidMembers
	local rmem, pmem, step, count

	local function SelfIterator()
		while step do
			local unit
			if step == 1 then
				unit, step = "player", 2
			elseif step == 2 then
				unit = "playerpet"
				step = nil
			end
			if unit and UnitExists(unit) then
				return unit
			end
		end
	end

	local function PartyIterator()
		while step do
			local unit
			if step <= 2 then
				unit = SelfIterator()
				step = step or 3
			elseif step == 3 then
				unit, step = format("party%d", count), 4
			elseif step == 4 then
				unit = format("partypet%d", count)
				count = count + 1
				step = count <= pmem and 3 or nil
			end
			if unit and UnitExists(unit) then
				return unit
			end
		end
	end

	local function RaidIterator()
		while step do
			local unit
			if step == 1 then
				unit, step = format("raid%d", count), 2
			elseif step == 2 then
				unit = format("raidpet%d", count)
				count = count + 1
				step = count <= rmem and 1 or nil
			end
			if unit and UnitExists(unit) then
				return unit
			end
		end
	end

	function UnitIterator()
		rmem, step = GetNumRaidMembers(), 1
		if rmem == 0 then
			pmem = GetNumPartyMembers()
			if pmem == 0 then
				return SelfIterator
			end
			count = 1
			return PartyIterator
		end
		count = 1
		return RaidIterator
	end
end

local function IsNamePlateFrame(frame)
	if frame.extended or frame.aloftData or frame.kui then
		--Tidyplates = extended, Aloft = aloftData, KuiNameplates = kui
		--They sometimes remove & replace the children so this needs to be checked first.
		return true
	end

	if frame.done then --caelNP
		return true
	end

	if frame:GetName() then
		debugPrint("GetName", frame:GetName())
		return false
	end

	if frame:GetID() ~= 0 then
		debugPrint("GetID", frame:GetID())
		return false
	end

	if frame:GetObjectType() ~= "Frame" then
		debugPrint("GetObjectType", frame:GetObjectType())
		return false
	end

	if frame:GetNumChildren() == 0 then
		debugPrint("GetNumChildren", frame:GetNumChildren())
		return false
	end

	if frame:GetNumRegions() == 0 then
		debugPrint("GetNumRegions", frame:GetNumRegions())
		return false
	end

	return true
end

local ScanWorldFrameChildren
function ScanWorldFrameChildren(frame, ...)
	if not frame then return end
	if frame:IsShown() and not lib.nameplates[frame] and IsNamePlateFrame(frame) then
		lib:NameplateFirstLoad(frame)
	end
	return ScanWorldFrameChildren(...)
end

do
	local WorldFrame = WorldFrame
	local prevChildren, curChildren = 0, nil
	local lastUpdated = 0
	local function onUpdate(this, elapsed)
		lastUpdated = lastUpdated + elapsed
		if lastUpdated > 0.01 then
			lastUpdated = 0
			curChildren = WorldFrame:GetNumChildren()
			if curChildren ~= prevChildren then
				prevChildren = curChildren
				ScanWorldFrameChildren(WorldFrame:GetChildren())
			end
		end
	end

	lib.scanForPlate = lib.scanForPlate or CreateFrame("frame")
	lib.scanForPlate:SetScript("OnUpdate", onUpdate)
end

local function FoundPlateGUID(frame, GUID, unitID, from)
	lib.nameplates[frame] = GUID
	lib.callbacks:Fire(callbackFoundGUID, lib.fakePlate[frame] or frame, GUID, unitID)
end

do
	local checkFrames = {}
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function(self)
		for frame in pairs(checkFrames) do
			if (not lib.nameplates[frame] or lib.nameplates[frame] == true) and lib:IsTarget(frame) then
				lib.callbacks:Fire(callbackOnTarget, lib.fakePlate[frame] or frame)
				FoundPlateGUID(frame, UnitGUID("target"), "target")
			end
		end
		wipe(checkFrames)
		self:Hide()
	end)

	function lib:CheckFrameForTargetGUID(frame)
		checkFrames[frame] = true
		f:Show()
	end
end

function lib:SetupNameplate(frame)
	self.isOnScreen[frame] = true
	self.nameplates[frame] = true

	local f = frame.extended or frame.kui or frame.aloftData
	if f and not self.fakePlate[frame] then
		self.fakePlate[frame] = f
		self.realPlate[f] = frame
	end

	self.callbacks:Fire(callbackOnShow, self.fakePlate[frame] or frame)

	self:CheckFrameForTargetGUID(frame)
end

function lib:NameplateOnShow(frame)
	self:SetupNameplate(frame)
end

function lib:RecycleNameplate(frame)
	self.nameplates[frame] = nil

	if self.fakePlate[frame] then
		self.callbacks:Fire(callbackOnHide, self.fakePlate[frame])
		self.realPlate[self.fakePlate[frame]] = nil
		self.fakePlate[frame] = nil
	end

	self.callbacks:Fire(callbackOnHide, frame)
end

lib.plateAnimations = lib.plateAnimations or {}
function lib:NameplateOnHide(frame)
	-- silly KuiNameplates
	if frame and frame.MOVING then return end
	self.isOnScreen[frame] = false
	for i, group in ipairs(self.onFinishedGroups[frame]) do
		group:Play()
	end

	self:RecycleNameplate(frame)
end

local FindGUIDByRaidIcon
do
	local GetRaidTargetIndex = GetRaidTargetIndex
	local tostring = tostring

	local function CheckRaidIconOnUnit(unitID, frame, raidNum, from)
		local targetID = format("%starget", unitID)
		if UnitExists(targetID) and not UnitIsUnit("target", targetID) then
			local targetIndex = GetRaidTargetIndex(targetID)
			if targetIndex and targetIndex == raidNum then
				debugPrint(
					"FindGUIDByRaidIcon", from,
					format("Icon: %s", tostring(raidNum)),
					format("unitID: %s", tostring(targetID)),
					format("GUID: %s", tostring(UnitGUID(targetID)))
				)
				FoundPlateGUID(frame, UnitGUID(targetID), targetID, from)
				return true
			end
		end
		return false
	end

	function FindGUIDByRaidIcon(frame, raidNum, from)
		for unitID in UnitIterator() do
			if CheckRaidIconOnUnit(unitID, frame, raidNum, from) then
				return
			end
		end
	end
end

do
	local inCombat
	local function CheckCombatStatus(frame)
		inCombat = lib:IsInCombat(frame)
		if lib.combatStatus[frame] ~= inCombat then
			lib.combatStatus[frame] = inCombat
			lib.callbacks:Fire(callbackCombatChanged, lib.fakePlate[frame] or frame, inCombat)
		end
	end

	local threatSit
	local function CheckThreatStatus(frame)
		threatSit = lib:GetThreatSituation(frame)
		if lib.threatStatus[frame] ~= threatSit then
			lib.threatStatus[frame] = threatSit
			lib.callbacks:Fire(callbackThreatChanged, lib.fakePlate[frame] or frame, threatSit)
		end
	end

	function lib:NameplateFastAnimation(frame)
		CheckCombatStatus(frame)
		CheckThreatStatus(frame)
	end
end

do
	local function CheckForFakePlate(frame)
		local f = frame.extended or frame.kui or frame.aloftData
		if f then
			lib.realPlate[f] = frame
			lib.fakePlate[frame] = f
			lib.callbacks:Fire(callbackOnHide, frame)
		end
	end

	function lib:NameplateSlowAnimation(frame)
		if self:IsMouseover(frame) and not UnitExists("mouseover") then
			self:HideMouseoverRegion(frame)
		end
		if not self.fakePlate[frame] then
			CheckForFakePlate(frame)
		end
	end
end

do
	local function CheckUnitIDForMatchingHP(unitID, frameName, current, max)
		local targetID = format("%starget", unitID)
		if UnitName(targetID) == frameName then
			local health = UnitHealth(targetID)
			local maxHealth = UnitHealthMax(targetID)

			if health == current and maxHealth == max then
				return true
			end
		end
		return false
	end

	local possibleUnits = {}
	function lib:NewNameplateCheckHP(frame, current)
		local bar = self.plateChildren[frame].healthBar
		if bar and bar.GetValue then
			local _, maxhp = bar:GetMinMaxValues()
			if current > 0 and current ~= maxhp then
				wipe(possibleUnits)
				local frameName = self:GetName(frame)

				for unitID in UnitIterator() do
					if CheckUnitIDForMatchingHP(unitID, frameName, current, maxhp) then
						table_insert(possibleUnits, #possibleUnits + 1, unitID .. "target")
					end
				end

				if #possibleUnits == 1 then
					FoundPlateGUID(frame, UnitGUID(possibleUnits[1]), possibleUnits[1])
					return true
				end
			end
		end
	end

	lib.prevHealth = lib.prevHealth or {}
	--------------------------------------------------------------------------------------
	function lib:healthOnValueChanged(bar, ...) --
	-- This fires before OnShow fires and the regions haven't been updated yet. 		--
	-- So I make sure lib.isOnScreen[plate] is true before working on the HP change.	--
	--------------------------------------------------------------------------------------
		local plate = bar:GetParent()
		local currentHP = ...

		--strange, when a nameplate's not on screen, we still get HP changes. It's not relyable but might be of use somehow...
		if plate and self.isOnScreen[plate] and (not self.prevHealth[plate] or self.prevHealth[plate] ~= currentHP) then
			self.callbacks:Fire(callbackHealthChanged, plate, ...)
			if not self.nameplates[plate] then
				self:NewNameplateCheckHP(plate, ...)
			end
			self.prevHealth[plate] = currentHP
		end
	end
end

do
	local function ourOnShow(...)
		lib:NameplateOnShow(...)
	end
	local function ourOnHide(...)
		lib:NameplateOnHide(...)
	end
	local function ourHealthOnValueChanged(...)
		return lib:healthOnValueChanged(...)
	end
	local function onFinishFastAnimation(animation)
		lib:NameplateFastAnimation(animation.frame)
	end
	local function onFinishSlowAnimation(animation)
		lib:NameplateSlowAnimation(animation.frame)
	end

	lib.onHideHooks = lib.onHideHooks or {}
	lib.onShowHooks = lib.onShowHooks or {}
	lib.healthOnValueChangedHooks = lib.healthOnValueChangedHooks or {}
	lib.onFinishedGroups = lib.onFinishedGroups or {}

	local aFrame = CreateFrame("Frame")
	function lib:HookNameplate(frame)
		if frame:HasScript("OnHide") and not self.onHideHooks[frame] then
			self.onHideHooks[frame] = true
			frame:HookScript("OnHide", ourOnHide)
		end

		if frame:HasScript("OnShow") and not self.onShowHooks[frame] then
			self.onShowHooks[frame] = true
			frame:HookScript("OnShow", ourOnShow)
		end

		if not self.onFinishedGroups[frame] then
			self.onFinishedGroups[frame] = self.onFinishedGroups[frame] or {}
			local group = aFrame:CreateAnimationGroup()
			group:SetLooping("REPEAT")
			local animation = group:CreateAnimation("Animation")
			animation:SetDuration(fastOnFinishThrottle)
			animation:SetScript("OnFinished", onFinishFastAnimation)
			animation.frame = frame
			table_insert(self.onFinishedGroups[frame], group)

			group = aFrame:CreateAnimationGroup()
			group:SetLooping("REPEAT")
			animation = group:CreateAnimation("Animation")
			animation:SetDuration(slowOnFinishThrottle)
			animation:SetScript("OnFinished", onFinishSlowAnimation)
			animation.frame = frame
			table_insert(self.onFinishedGroups[frame], group)
		end

		local healthBar = self.plateChildren[frame].healthBar
		if healthBar and not self.healthOnValueChangedHooks[frame] then
			self.healthOnValueChangedHooks[frame] = true
			healthBar:HookScript("OnValueChanged", ourHealthOnValueChanged)
		end
	end
end

function lib:NameplateFirstLoad(frame)
	if not self.nameplates[frame] then
		self:HookNameplate(frame)
		self:SetupNameplate(frame)
	end
end

do
	lib.plateRegions = lib.plateRegions or setmetatable({}, {__index = function(t, frame)
		t[frame] = {
			nameText = lib:GetNameRegion(frame),
			levelText = lib:GetLevelRegion(frame),
			bossIcon = lib:GetBossRegion(frame),
			eliteIcon = lib:GetEliteRegion(frame),
			threatTexture = lib:GetThreatRegion(frame),
			highlightTexture = lib:GetHightlightRegion(frame),
			raidIcon = lib:GetRaidIconRegion(frame)
		}
		return t[frame]
	end})

	lib.plateChildren = lib.plateChildren or setmetatable({}, {__index = function(t, frame)
		t[frame] = {healthBar = lib:GetHealthBar(frame), castBar = lib:GetCastBar(frame)}
		return t[frame]
	end})
end

local noColorText = setmetatable({}, {__index = function(t, inputString)
	if inputString then
		if inputString:find("|c") then
			local input = inputString
			local found = inputString:find("|c")
			inputString = inputString:sub(found + 10)
			inputString = inputString:gsub("|r", "")
			t[input] = inputString
			return inputString
		end
		t[inputString] = inputString
	end
	return inputString or "UNKNOWN"
end})

local noColorNum = setmetatable({}, {__index = function(t, inputString)
	if inputString then
		if inputString:find("|c") then
			local input = inputString
			local found = inputString:find("|c")
			inputString = inputString:sub(found + 10)
			inputString = inputString:gsub("|r", "")
			inputString = tonumber(inputString) or 0
			t[input] = inputString
			return inputString
		end
		t[inputString] = tonumber(inputString) or 0
	end
	return tonumber(inputString) or 0
end})

local threatByColor
do
	local redCan, greenCan
	function threatByColor(region)
		if not region:IsShown() then
			return "LOW"
		end
		redCan, greenCan = region:GetVertexColor()
		if greenCan > .7 then
			return "MEDIUM"
		end
		if redCan > .7 then
			return "HIGH"
		end
	end
end
--------------------------------------------------------------------------------------------------------------------------------------------

local function GetHealthBarColor(frame)
	if frame.aloftData then
		return frame.aloftData.originalHealthBarR, frame.aloftData.originalHealthBarG, frame.aloftData.originalHealthBarB
	end

	if frame.originalR and frame.originalG and frame.originalB then
		--dNamePlates changes the color of the healthbar. r7 now saves the original colors. TY Dawn.
		return frame.originalR, frame.originalG, frame.originalB
	end

	local bar = lib.plateChildren[frame].healthBar
	if bar and bar.GetStatusBarColor then
		return bar:GetStatusBarColor()
	end
end

local function reactionByColor(red, green, blue, a)
	if red < .01 and blue < .01 and green > .99 then
		return "FRIENDLY", "NPC"
	elseif red < .01 and blue > .99 and green < .01 then
		return "FRIENDLY", "PLAYER"
	elseif red > .99 and blue < .01 and green > .99 then
		return "NEUTRAL", "NPC"
	elseif red > .99 and blue < .01 and green < .01 then
		return "HOSTILE", "NPC"
	else
		return "HOSTILE", "PLAYER"
	end
end

local function combatByColor(r, g, b, a)
	return (r > .5 and g < .5)
end

do
	local GetMouseFocus = GetMouseFocus

	local f = CreateFrame("Frame")
	f:Hide()
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	f:RegisterEvent("RAID_TARGET_UPDATE")

	local mouseoverPlate
	f:SetScript("OnEvent", function(self, event, ...)
		if event == "PLAYER_TARGET_CHANGED" then
			if UnitExists("target") and not UnitIsUnit("target", "player") then
				self.unitID = "target"
				self:Show()
			end
		elseif event == "UPDATE_MOUSEOVER_UNIT" then
			if UnitExists("mouseover") and not UnitIsUnit("mouseover", "player") then
				self.unitID = "mouseover"
				self:Show()
			end
		elseif event == "RAID_TARGET_UPDATE" then
			for frame, guid in pairs(lib.nameplates) do
				if frame:IsShown() and guid == true and lib:IsMarked(frame) then
					local raidNum = lib:GetRaidIcon(frame)
					if raidNum and raidNum > 0 then
						FindGUIDByRaidIcon(frame, raidNum, event)
					end
				end
			end
		end
	end)
	f:SetScript("OnUpdate", function(self, elapsed)
		for frame, guid in pairs(lib.nameplates) do
			if self.unitID == "target" and frame:IsShown() and lib:IsTarget(frame, true) then
				if guid == true then -- already set
					FoundPlateGUID(frame, UnitGUID("target"), "target", "PLAYER_TARGET_CHANGED")
				end
				break
			elseif self.unitID == "mouseover" and frame:IsShown() and lib:IsMouseover(frame) then
				if guid == true then -- already set
					FoundPlateGUID(frame, UnitGUID("mouseover"), "mouseover", "UPDATE_MOUSEOVER_UNIT")
				end
				break
			end
		end
		self.unitID = nil
		self:Hide()
	end)
end

do
	local throttle = 1 --Fire our fix hooks every second.

	local function onFinished(animation)
		for frame, value in pairs(lib.isOnScreen) do
			if (value == true and not frame:IsShown()) then --OnHide fail
				lib.onHideHooks[frame] = false
				lib.isOnScreen[frame] = false
				lib:NameplateOnHide(frame)
				lib:HookNameplate(frame)
			elseif (value == false and frame:IsShown()) then --OnShow fail
				debugPrint("OnShow fail", frame, value, frame:IsShown())
				lib.onShowHooks[frame] = false
				lib.isOnScreen[frame] = false
				lib:HookNameplate(frame)
				lib:SetupNameplate(frame, true)
			end
		end
	end

	if not lib.fixHooks then
		lib.fixHooks = CreateFrame("Frame")
		lib.fixHooks.animGroup = lib.fixHooks:CreateAnimationGroup() --"TimerAnimGroup"
		lib.fixHooks.anim = lib.fixHooks.animGroup:CreateAnimation("Animation") --, "TimerAnim"
		lib.fixHooks.anim:SetDuration(throttle)
		lib.fixHooks.anim:SetScript("OnFinished", onFinished)
		lib.fixHooks.animGroup:SetLooping("REPEAT")
		lib.fixHooks.animGroup:Play()
	end
end

function lib:GetNameRegion(frame)
	if frame.extended and frame.extended.regions and frame.extended.regions.name then --TidyPlates
		return frame.extended.regions.name
	elseif frame.aloftData and frame.aloftData.nameTextRegion then --Aloft
		return frame.aloftData.nameTextRegion
	elseif frame.oldName then --KuiNameplates
		return frame.oldName
	elseif frame.oldname then --dNameplates
		return frame.oldname
	end
	return select(regionIndex.nameText, frame:GetRegions())
end

function lib:GetLevelRegion(frame)
	if frame.extended and frame.extended.regions and frame.extended.regions.level then --TidyPlates
		return frame.extended.regions.level
	elseif frame.aloftData and frame.aloftData.levelTextRegion then --Aloft
		return frame.aloftData.levelTextRegion
	elseif frame.level then --dNameplates & KuiNameplates
		return frame.level
	end
	return select(regionIndex.levelText, frame:GetRegions())
end

function lib:GetBossRegion(frame)
	if frame.extended and frame.extended.regions and frame.extended.regions.dangerskull then --tidyPlates
		return frame.extended.regions.dangerskull
	elseif frame.aloftData and frame.aloftData.bossIconRegion then --aloft
		return frame.aloftData.bossIconRegion
	elseif frame.boss then --dNameplates & KuiNameplates
		return frame.boss
	end
	return select(regionIndex.skullIcon, frame:GetRegions())
end

function lib:GetEliteRegion(frame)
	if frame.extended and frame.extended.regions and frame.extended.regions.eliteicon then --tidyPlates
		return frame.extended.regions.eliteicon
	elseif frame.aloftData and frame.aloftData.stateIconRegion then --aloft
		return frame.aloftData.stateIconRegion
	elseif frame.state then --KuiNameplates
		return frame.state
	elseif frame.elite then --dNameplates
		return frame.elite
	end
	return select(regionIndex.eliteIcon, frame:GetRegions())
end

function lib:GetThreatRegion(frame)
	if frame.extended and frame.extended.regions and frame.extended.regions.threatGlow then
		return frame.extended.regions.threatGlow
	elseif frame.aloftData and frame.aloftData.nativeGlowRegion then
		return frame.aloftData.nativeGlowRegion
	elseif frame.glow then --KuiNameplates
		return frame.glow
	elseif frame.oldglow then --dNameplates
		return frame.oldglow
	end
	return select(regionIndex.threatTexture, frame:GetRegions())
end

function lib:GetHightlightRegion(frame)
	if frame.extended then
		if frame.extended.regions then
			if frame.extended.regions.highlight then
				return frame.extended.regions.highlight
			elseif frame.extended.regions.highlightTexture then --old tidyplates
				return frame.extended.regions.highlightTexture
			end
		end
	elseif frame.aloftData and frame.aloftData.highlightRegion then
		return frame.aloftData.highlightRegion
	elseif frame.highlight then --dNameplates or KuiNameplates
		return frame.highlight
	end
	return select(regionIndex.highlightTexture, frame:GetRegions())
end

function lib:GetRaidIconRegion(frame)
	if frame.extended and frame.extended.regions and frame.extended.regions.raidicon then
		return frame.extended.regions.raidicon
	elseif frame.aloftData and frame.aloftData.raidIconRegion then
		return frame.aloftData.raidIconRegion
	end
	return select(regionIndex.raidIcon, frame:GetRegions())
end

function lib:IsTarget(frame, quick)
	quick = quick or (frame:IsShown() and UnitExists("target"))

	if frame.UnitFrame then -- ElvUI
		if not self.fakePlate[frame] then
			self.fakePlate[frame] = frame.UnitFrame
			self.realPlate[frame.UnitFrame] = frame
		end
		return quick and (frame.UnitFrame.alpha == 1) or false
	end

	frame = self.realPlate[frame] or frame
	return quick and (frame:GetAlpha() == 1) or false
end

function lib:GetHealthBar(frame)
	if frame.extended and frame.extended.bars and frame.extended.bars.health then
		-- Aloft changes the bar color. Our functions will have to use aloftData.originalHealthBarR
		return frame.extended.bars.health
	elseif frame.oldHealth then --KuiNameplates
		return frame.oldHealth
	elseif frame.healthOriginal then -- dNameplates
		return frame.healthOriginal
	end
	return select(childIndex.healthBar, frame:GetChildren())
end

function lib:GetCastBar(frame)
	if frame.extended and frame.extended.bars and frame.extended.bars.castbar then
		return frame.extended.bars.castbar
	elseif frame.aloftData and frame.aloftData.castBar then
		return frame.aloftData.castBar
	end
	return select(childIndex.castBar, frame:GetChildren())
end

function lib:GetName(frame)
	frame = self.realPlate[frame] or frame
	local region = self.plateRegions[frame].nameText
	if region and region.GetText then
		return noColorText[region:GetText()]
	end
end

function lib:IsInCombat(frame)
	frame = self.realPlate[frame] or frame
	local region = self.plateRegions[frame].nameText
	if region and region.GetTextColor then
		return combatByColor(region:GetTextColor()) and true or false
	end
end

do
	function lib:GetLevel(frame)
		frame = self.realPlate[frame] or frame
		local region = self.plateRegions[frame].levelText
		if region and region.GetText then
			return noColorNum[region:GetText()]
		end
		return 0
	end

	local greenRange = 5 --GetQuestGreenRange()
	local UnitLevel = UnitLevel
	function lib:GetLevelDifficulty(frame)
		local level = self:GetLevel(frame)
		diff = level - UnitLevel("player")
		if (diff >= 5) then
			return "impossible"
		elseif (diff >= 3) then
			return "verydifficult"
		elseif (diff >= -2) then
			return "difficult"
		elseif (-diff <= greenRange) then
			return "standard"
		else
			return "trivial"
		end
	end
end

function lib:IsBoss(frame)
	frame = self.realPlate[frame] or frame
	local region = self.plateRegions[frame].bossIcon
	if region and region.IsShown then
		return region:IsShown() and true or false
	end
	return false
end

function lib:IsElite(frame)
	frame = self.realPlate[frame] or frame
	local region = self.plateRegions[frame].eliteIcon
	if region and region.IsShown then
		return region:IsShown() and true or false
	end
	return false
end

function lib:GetThreatSituation(frame)
	frame = self.realPlate[frame] or frame
	local region = self.plateRegions[frame].threatTexture
	if region and region.GetVertexColor then
		return threatByColor(region)
	end
end

function lib:IsMouseover(frame)
	frame = self.realPlate[frame] or frame
	local region = self.plateRegions[frame].highlightTexture
	if region and region.IsShown then
		return region:IsShown() and (region:GetAlpha() > 0) or false
	end
end

------------------------------------------------------------------------------------------------------------------
function lib:HideMouseoverRegion(frame) --
-- If we move the camera angle while the mouse is over a plate, that plate won't hide the mouseover texture.	--
-- So if we're mousing over someone's feet and a plate has the mouseover texture visible, 						--
-- it fools our code into thinking we're mousing over that plate.												--
-- This can be recreated by placing the mouse over a nameplate then holding rightclick and moving the camera.	--
-- If our UpdateNameplateInfo sees the mouseover texture still visible when we have no mouseoverID, it'll call	--
-- this function to hide the texture.																			--
------------------------------------------------------------------------------------------------------------------
	local region = self.plateRegions[frame].highlightTexture
	if region and region.Hide then
		region:Hide()
	end
end

--------------------------------------------------------------------------------------------------------------------------------------------

do
	local raidIconTexCoord = {
		[0] = {
			[0] = 1, -- star
			[0.25] = 5 -- moon
		},
		[0.25] = {
			[0] = 2, -- circle
			[0.25] = 6 -- square
		},
		[0.5] = {
			[0] = 3, -- star
			[0.25] = 7 -- cross
		},
		[0.75] = {
			[0] = 4, -- star
			[0.25] = 8 -- skull
		}
	}

	function lib:GetRaidIcon(frame)
		frame = self.realPlate[frame] or frame
		local region = self.plateRegions[frame].raidIcon
		if region and region.IsShown and region:IsShown() and region.GetTexCoord then
			local ULx, ULy = region:GetTexCoord()
			if ULx and ULy then
				return raidIconTexCoord[ULx] and raidIconTexCoord[ULx][ULy] or 0
			end
		end
	end

	function lib:IsMarked(frame)
		frame = self.realPlate[frame] or frame
		local region = self.plateRegions[frame].raidIcon
		if region and region.IsShown then
			return region:IsShown() and true or false
		end
	end
end

function lib:IsCasting(frame)
	frame = self.realPlate[frame] or frame
	local bar = self.plateChildren[frame].castBar
	if bar and bar.IsShown then
		return bar:IsShown() and true or false
	end
end

function lib:GetType(frame)
	frame = self.realPlate[frame] or frame
	local r, g, b = GetHealthBarColor(frame)
	if r then
		return select(2, reactionByColor(r, g, b))
	end
end

function lib:GetReaction(frame)
	frame = self.realPlate[frame] or frame
	local r, g, b = GetHealthBarColor(frame)
	if r then
		return reactionByColor(r, g, b)
	end
end

do
	local colorToClass = {}
	local function pctToInt(number)
		return math_floor((100 * number) + 0.5)
	end
	for classname, color in pairs(RAID_CLASS_COLORS) do
		colorToClass["C" .. pctToInt(color.r) + pctToInt(color.g) + pctToInt(color.b)] = classname
	end

	function lib:GetClass(frame)
		frame = self.realPlate[frame] or frame
		local r, g, b = GetHealthBarColor(frame)
		if r then
			return colorToClass["C" .. pctToInt(r) + pctToInt(g) + pctToInt(b)] or nil
		end
	end
end

function lib:GetHealthMax(frame)
	frame = self.realPlate[frame] or frame
	local bar = self.plateChildren[frame].healthBar
	if bar and bar.GetMinMaxValues then
		local _, max = bar:GetMinMaxValues()
		return tonumber(max or 0)
	end
end

function lib:GetHealth(frame)
	frame = self.realPlate[frame] or frame
	local bar = self.plateChildren[frame].healthBar
	if bar and bar.GetValue then
		return bar:GetValue()
	end
end

function lib:GetGUID(frame)
	frame = self.realPlate[frame] or frame
	if self.nameplates[frame] and self.nameplates[frame] ~= true then
		return self.nameplates[frame]
	end
end

function lib:GetTargetNameplate()
	if UnitExists("target") then
		for frame in pairs(self.nameplates) do
			if frame:IsShown() and frame:GetAlpha() == 1 then
				return self.fakePlate[frame] or frame
			end
		end
	end
end

function lib:GetNameplateByGUID(GUID)
	if not GUID then return end
	for frame, guid in pairs(self.nameplates) do
		if guid == GUID then
			return self.fakePlate[frame] or frame
		end
	end
end

function lib:GetNameplateByName(name, maxHp)
	for frame in pairs(self.nameplates) do
		if frame:IsShown() then
			if name == lib:GetName(frame) then
				if not maxHp then
					return self.fakePlate[frame] or frame
				end
				local bar = self.plateChildren[frame].healthBar
				if bar and bar.GetMinMaxValues then
					local _, barMax = bar:GetMinMaxValues()
					if barMax == maxHp then
						return self.fakePlate[frame] or frame
					end
				end
			end
		end
	end
end

function lib:GetNameplateByUnit(unitID)
	if UnitIsUnit(unitID, "target") then
		return self:GetTargetNameplate()
	end
	local frame = self:GetNameplateByGUID(UnitGUID(unitID))
	if not frame then
		frame = self:GetNameplateByName(UnitName(unitID), UnitHealthMax(unitID))
	end
	return frame
end

do
	local unpack = unpack
	local frames = {}

	function lib:GetAllNameplates()
		wipe(frames)
		for frame in pairs(self.nameplates) do
			table_insert(frames, frame)
		end
		return unpack(frames)
	end

	function lib:IteratePlates()
		wipe(frames)
		for frame in pairs(self.nameplates) do
			table_insert(frames, frame)
		end
		return pairs(frames)
	end
end

do
	local possibleFrames = {}
	function lib:GetNameplateByHealth(current, max)
		wipe(possibleFrames)

		for frame in pairs(self.nameplates) do
			if frame:IsShown() then
				local bar = self.plateChildren[frame].healthBar

				if bar and bar.GetMinMaxValues then
					local _, barMax = bar:GetMinMaxValues()
					if barMax == max then
						if bar:GetValue() == current then
							table_insert(possibleFrames, #possibleFrames + 1, frame)
						end
					end
				end
			end
		end
		if #possibleFrames == 1 then
			return self.fakePlate[possibleFrames[1]] or possibleFrames[1]
		end
	end
end