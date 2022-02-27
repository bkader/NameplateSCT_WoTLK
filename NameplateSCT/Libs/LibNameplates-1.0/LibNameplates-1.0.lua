--[[
	Name: LibNameplates-1.0
	Author(s): Cyprias (cyprias@gmail.com)
	Documentation: http://www.wowace.com/addons/libnameplate-1-0/pages/main/
	SVN:  svn://svn.wowace.com/wow/libnameplate-1-0/mainline/trunk
	Description: Alerts addons when a nameplate is shown or hidden. Has API to get info such as name, level, class, ect from the nameplate. LibNameplates tries to function with the default nameplates, Aloft, caelNamePlates and TidyPlates (buggy).
	Dependencies: LibStub, CallbackHandler-1.0
]]
local MAJOR, MINOR = "LibNameplates-1.0", 30
if not LibStub then
	error(MAJOR .. " requires LibStub.")
	return
end

-- Create lib
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

-- Make sure CallbackHandler exists.
lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)
if not lib.callbacks then
	error(MAJOR .. " CallbackHandler-1.0.")
	return
end

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

lib.nameplates = lib.nameplates or {}
lib.realPlate = lib.realPlate or {}
lib.fakePlate = lib.fakePlate or {}
lib.plateGUIDs = lib.plateGUIDs or {}
lib.isOnScreen = lib.isOnScreen or {}
lib.healthOnValueChangedHooks = lib.healthOnValueChangedHooks or {}
lib.combatStatus = lib.combatStatus or {}
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

local IsNamePlateFrame
do
	local wantedName = "NamePlate"
	local wantedID = 0
	local wantedObjectType = "Frame"
	local wantedNumChildren = 2
	local wantedNumRegions = 8
	local frameName

	function IsNamePlateFrame(frame)
		if frame.extended or frame.aloftData or frame.kui then
			--Tidyplates = extended, Aloft = aloftData, KuiNameplates = kui
			--They sometimes remove & replace the children so this needs to be checked first.
			return true
		end

		if frame.done then --caelNP
			return true
		end

		frameName = frame:GetName()

		if frameName and frameName:sub(1, 9) ~= wantedName then
			debugPrint("GetName", frame:GetName())
			return false
		end

		if frame:GetID() ~= wantedID then
			debugPrint("GetID", frame:GetID())
			return false
		end

		if frame:GetObjectType() ~= wantedObjectType then
			debugPrint("GetObjectType", frame:GetObjectType())
			return false
		end
		if frame:GetNumChildren() ~= wantedNumChildren then
			return false
		end
		if frame:GetNumRegions() ~= wantedNumRegions then
			debugPrint("GetNumRegions", frame:GetNumRegions())
			return false
		end
		return true
	end
end

local Round
do
	local math_floor = math.floor
	local zeros
	------------------------------------------------------------------
	function Round(num, zeros) --
	-- zeroes is the number of decimal places. eg 1=*.*, 3=*.***	--
	------------------------------------------------------------------
		zeros = zeros or 0
		return math_floor(num * 10 ^ zeros + 0.5) / 10 ^ zeros
	end
end

local ScanWorldFrameChildren
do
	function ScanWorldFrameChildren(frame, ...)
		if not frame then return end

		if frame:IsShown() and not lib.nameplates[frame] and IsNamePlateFrame(frame) then
			lib:NameplateFirstLoad(frame)
		end

		return ScanWorldFrameChildren(...)
	end
end

do
	local WorldFrame = WorldFrame
	local curChildren
	local prevChildren = 0
	local function onUpdate(this, elapsed)
		local curChildren = WorldFrame:GetNumChildren()
		if curChildren ~= prevChildren then
			prevChildren = curChildren
			ScanWorldFrameChildren(WorldFrame:GetChildren())
		end
	end

	lib.scanForPlate = lib.scanForPlate or CreateFrame("frame")
	lib.scanForPlate:SetScript("OnUpdate", onUpdate)
end

local function FoundPlateGUID(frame, GUID, unitID)
	lib.plateGUIDs[frame] = GUID
	lib.callbacks:Fire(callbackFoundGUID, lib.fakePlate[frame] or frame, GUID, unitID)
end

do
	local pairs = pairs
	local wipe = wipe
	local UnitExists = UnitExists
	local UnitGUID = UnitGUID

	local checkForGUID = {}
	local f = CreateFrame("Frame")
	f:Hide()
	f:SetScript("OnUpdate", function(this, elapsed)
		for frame in pairs(checkForGUID) do
			if not lib.plateGUIDs[frame] and lib:IsTarget(frame) then
				lib.callbacks:Fire(callbackOnTarget, lib.fakePlate[frame] or frame)
				FoundPlateGUID(frame, UnitGUID("target"), "target")
			end
		end
		wipe(checkForGUID)
		this:Hide()
	end)

	function lib:CheckFrameForTargetGUID(frame)
		checkForGUID[frame] = true
		f:Show()
	end
end

do
	local ipairs = ipairs

	local plateName
	function lib:SetupNameplate(frame)
		self.isOnScreen[frame] = true
		if frame.extended and not self.fakePlate[frame] then
			self.fakePlate[frame] = frame.extended
			self.realPlate[frame.extended] = frame
			self.callbacks:Fire(callbackOnHide, frame)
		elseif frame.kui and not self.fakePlate[frame] then
			self.fakePlate[frame] = frame.kui
			self.realPlate[frame.kui] = frame
			self.callbacks:Fire(callbackOnHide, frame)
		end

		self.callbacks:Fire(callbackOnShow, self.fakePlate[frame] or frame)

		self:CheckFrameForTargetGUID(frame)
	end
end

do
	local ipairs = ipairs
	function lib:NameplateOnShow(frame)
		self:SetupNameplate(frame)
	end
end

do
	local fake
	function lib:RecycleNameplate(frame)
		self.plateGUIDs[frame] = nil
		if self.fakePlate[frame] then
			self.callbacks:Fire(callbackOnHide, self.fakePlate[frame])
		end
		self.callbacks:Fire(callbackOnHide, frame)
	end
end

lib.plateAnimations = lib.plateAnimations or {}
do
	local ipairs = ipairs
	function lib:NameplateOnHide(frame)
		-- silly KuiNameplates
		if frame and frame.MOVING then return end
		self.isOnScreen[frame] = false
		for i, group in ipairs(self.onFinishedGroups[frame]) do
			group:Play()
		end

		self:RecycleNameplate(frame)
	end
end

local FindGUIDByRaidIcon
do
	local UnitExists = UnitExists
	local UnitIsUnit = UnitIsUnit
	local GetRaidTargetIndex = GetRaidTargetIndex
	local tostring = tostring
	local UnitGUID = UnitGUID

	local targetID
	local targetIndex
	local function CheckRaidIconOnUnit(unitID, frame, raidNum, from)
		targetID = unitID .. "target"
		if UnitExists(targetID) and not UnitIsUnit("target", targetID) then
			targetIndex = GetRaidTargetIndex(targetID)
			if targetIndex and targetIndex == raidNum then
				debugPrint("FindGUIDByRaidIcon", from, "Icon:" .. tostring(raidNum), "unitID:" .. tostring(targetID), "GUID:" .. tostring(UnitGUID(targetID)))
				FoundPlateGUID(frame, UnitGUID(targetID), targetID)
				return true
			end
		end
		return false
	end

	local GetNumRaidMembers = GetNumRaidMembers
	local GetNumPartyMembers = GetNumPartyMembers

	local group, num
	function FindGUIDByRaidIcon(frame, raidNum, from)
		if GetNumRaidMembers() > 1 then
			group, num = "raid", GetNumRaidMembers()
		elseif GetNumPartyMembers() > 0 then
			group, num = "party", GetNumPartyMembers()
		else
			return
		end

		local unitID
		for i = 1, num do
			unitID = group .. i
			if CheckRaidIconOnUnit(unitID, frame, raidNum, from) then
				return
			end

			if UnitExists(unitID .. "pet") and CheckRaidIconOnUnit(unitID .. "pet", frame, raidNum, from) then
				return
			end
		end
	end
end

local GetMouseoverGUID
do
	local UnitExists = UnitExists
	local UnitGUID = UnitGUID
	local unitID = "mouseover"
	function GetMouseoverGUID(frame)
		if UnitExists(unitID) then
			FoundPlateGUID(frame, UnitGUID(unitID), unitID)
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
		if frame.extended then
			lib.realPlate[frame.extended] = frame
			lib.fakePlate[frame] = frame.extended
			lib.callbacks:Fire(callbackOnHide, frame)
		end
	end

	local UnitExists = UnitExists
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
	local UnitName = UnitName
	local UnitHealth = UnitHealth
	local UnitHealthMax = UnitHealthMax

	local health, maxHealth
	local function CheckUnitIDForMatchingHP(unitID, frameName, current, max)
		local targetID = unitID .. "target"
		if UnitName(targetID) == frameName then
			health = UnitHealth(targetID)
			maxHealth = UnitHealthMax(targetID)

			if health == current and maxHealth == max then
				return true
			end
		end
		return false
	end

	local GetNumRaidMembers = GetNumRaidMembers
	local GetNumPartyMembers = GetNumPartyMembers
	local table_insert = table.insert
	local UnitExists = UnitExists
	local UnitGUID = UnitGUID
	local wipe = wipe

	local bar
	local _, max
	local possibleUnits = {}
	local frameName
	local unitID, targetID, targetIndex
	local group, num
	function lib:NewNameplateCheckHP(frame, current)
		bar = self.plateChildren[frame].healthBar
		if bar and bar.GetValue then
			_, max = bar:GetMinMaxValues()
			if current > 0 and current ~= max then
				if GetNumRaidMembers() > 1 then
					group, num = "raid", GetNumRaidMembers()
				elseif GetNumPartyMembers() > 0 then
					group, num = "party", GetNumPartyMembers()
				else
					return
				end

				wipe(possibleUnits)

				frameName = self:GetName(frame)
				for i = 1, num do
					unitID = group .. i
					if CheckUnitIDForMatchingHP(unitID, frameName, current, max) then
						table_insert(possibleUnits, #possibleUnits + 1, unitID .. "target")
					end

					if UnitExists(unitID .. "pet") then
						if CheckUnitIDForMatchingHP(unitID .. "pet", frameName, current, max) then
							table_insert(possibleUnits, #possibleUnits + 1, unitID .. "pettarget")
						end
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

	local plate
	local currentHP
	local plateName
	--------------------------------------------------------------------------------------
	function lib:healthOnValueChanged(bar, ...) --
	-- This fires before OnShow fires and the regions haven't been updated yet. 		--
	-- So I make sure lib.isOnScreen[plate] is true before working on the HP change.	--
	--------------------------------------------------------------------------------------
		plate = bar:GetParent()
		currentHP = ...

		--strange, when a nameplate's not on screen, we still get HP changes. It's not relyable but might be of use somehow...
		if plate and self.isOnScreen[plate] and (not self.prevHealth[plate] or self.prevHealth[plate] ~= currentHP) then
			self.callbacks:Fire(callbackHealthChanged, plate, ...)
			if not self.plateGUIDs[plate] then
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

	local hooksecurefunc = hooksecurefunc
	local table_insert = table.insert

	local healthBar
	local group, animation

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
			group = aFrame:CreateAnimationGroup()
			group:SetLooping("REPEAT")
			animation = group:CreateAnimation("Animation")
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

		healthBar = self.plateChildren[frame].healthBar
		if healthBar and not self.healthOnValueChangedHooks[frame] then
			self.healthOnValueChangedHooks[frame] = true
			healthBar:HookScript("OnValueChanged", ourHealthOnValueChanged)
		end
	end
end

do
	local tested = false
	function lib:NameplateFirstLoad(frame)
		if not self.nameplates[frame] then
			self.nameplates[frame] = true
			self:HookNameplate(frame)
			self:SetupNameplate(frame)
		end
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

local noColorText, noColorNum
do
	local input, find, inputString
	noColorText = setmetatable({}, {__index = function(t, inputString)
		if inputString then
			if inputString:find("|c") then
				input = inputString
				find = inputString:find("|c")
				inputString = inputString:sub(find + 10)
				inputString = inputString:gsub("|r", "")
				t[input] = inputString
				return inputString
			end
			t[inputString] = inputString
		end
		return inputString or "UNKNOWN"
	end})

	local tonumber = tonumber
	noColorNum = setmetatable({}, {__index = function(t, inputString)
		if inputString then
			if inputString:find("|c") then
				input = inputString
				find = inputString:find("|c")
				inputString = inputString:sub(find + 10)
				inputString = inputString:gsub("|r", "")
				inputString = tonumber(inputString or 0)
				t[input] = inputString
				return inputString
			end
			t[inputString] = tonumber(inputString or 0)
		end
		return inputString or 0
	end})
end

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
local GetHealthBarColor
do
	local r, g, b
	local bar
	function GetHealthBarColor(frame)
		if frame.aloftData then
			return frame.aloftData.originalHealthBarR, frame.aloftData.originalHealthBarG, frame.aloftData.originalHealthBarB
		end

		if frame.originalR and frame.originalG and frame.originalB then
			--dNamePlates changes the color of the healthbar. r7 now saves the original colors. TY Dawn.
			return frame.originalR, frame.originalG, frame.originalB
		end

		bar = lib.plateChildren[frame].healthBar
		if bar and bar.GetStatusBarColor then
			return bar:GetStatusBarColor()
		end
		return nil
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
	local UnitExists = UnitExists
	local pairs = pairs
	local UnitGUID = UnitGUID
	local GetMouseFocus = GetMouseFocus
	local GetNumRaidMembers = GetNumRaidMembers
	local GetNumPartyMembers = GetNumPartyMembers

	local f = CreateFrame("Frame")
	f:Hide()
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	f:RegisterEvent("RAID_TARGET_UPDATE")

	local i
	local mouseoverPlate
	local raidNum
	f:SetScript("OnEvent", function(this, event, ...)
		if event == "PLAYER_TARGET_CHANGED" then
			if UnitExists("target") then
				this:Show()
			end
		elseif event == "UPDATE_MOUSEOVER_UNIT" then
			if GetMouseFocus():GetName() == "WorldFrame" then
				i = 0
				for frame in pairs(lib.nameplates) do
					if frame:IsShown() and lib:IsMouseover(frame) then
						i = i + 1
						mouseoverPlate = frame
					end
				end

				if i == 1 then
					if not lib.plateGUIDs[mouseoverPlate] then
						FoundPlateGUID(mouseoverPlate, UnitGUID("mouseover"), "mouseover")
					end
				elseif i > 1 then
					debugPrint(i .. " mouseover frames")
				end
			end
		elseif event == "RAID_TARGET_UPDATE" then
			for frame in pairs(lib.nameplates) do
				if frame:IsShown() and not lib.plateGUIDs[frame] and lib:IsMarked(frame) then
					raidNum = lib:GetRaidIcon(frame)
					if raidNum and raidNum > 0 then
						FindGUIDByRaidIcon(frame, raidNum, event)
					end
				end
			end
		end
	end)
	local unitID = "target"
	f:SetScript("OnUpdate", function(this, elapsed)
		for frame in pairs(lib.nameplates) do
			if frame:IsShown() and lib:IsTarget(frame) then
				lib.callbacks:Fire(callbackOnTarget, lib.fakePlate[frame] or frame)
				if not lib.plateGUIDs[frame] then
					FoundPlateGUID(frame, UnitGUID(unitID), unitID)
				end
				break
			end
		end
		this:Hide()
	end)
end

do
	local throttle = 1 --Fire our fix hooks every second.

	local pairs = pairs
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

do
	local select = select
	local region

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
		region = select(regionIndex.nameText, frame:GetRegions())
		return region
	end

	function lib:GetLevelRegion(frame)
		if frame.extended and frame.extended.regions and frame.extended.regions.level then --TidyPlates
			return frame.extended.regions.level
		elseif frame.aloftData and frame.aloftData.levelTextRegion then --Aloft
			return frame.aloftData.levelTextRegion
		elseif frame.level then --dNameplates & KuiNameplates
			return frame.level
		end
		region = select(regionIndex.levelText, frame:GetRegions())
		return region
	end

	function lib:GetBossRegion(frame)
		if frame.extended and frame.extended.regions and frame.extended.regions.dangerskull then --tidyPlates
			return frame.extended.regions.dangerskull
		elseif frame.aloftData and frame.aloftData.bossIconRegion then --aloft
			return frame.aloftData.bossIconRegion
		elseif frame.boss then --dNameplates & KuiNameplates
			return frame.boss
		end
		region = select(regionIndex.skullIcon, frame:GetRegions())
		return region
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
		region = select(regionIndex.threatTexture, frame:GetRegions())
		return region
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
		region = select(regionIndex.highlightTexture, frame:GetRegions())
		return region
	end

	function lib:GetRaidIconRegion(frame)
		if frame.extended and frame.extended.regions and frame.extended.regions.raidicon then
			return frame.extended.regions.raidicon
		elseif frame.aloftData and frame.aloftData.raidIconRegion then
			return frame.aloftData.raidIconRegion
		end
		region = select(regionIndex.raidIcon, frame:GetRegions())
		return region
	end
end

do
	local UnitExists = UnitExists
	function lib:IsTarget(frame)
		frame = self.realPlate[frame] or frame
		return frame:IsShown() and frame:GetAlpha() == 1 and UnitExists("target") or false
	end
end

do
	local select = select

	local healthBar
	function lib:GetHealthBar(frame)
		if frame.extended and frame.extended.bars and frame.extended.bars.health then
			-- Aloft changes the bar color. Our functions will have to use aloftData.originalHealthBarR
			return frame.extended.bars.health
		elseif frame.oldHealth then --KuiNameplates
			return frame.oldHealth
		elseif frame.healthOriginal then -- dNameplates
			return frame.healthOriginal
		end
		healthBar = select(childIndex.healthBar, frame:GetChildren())
		return healthBar
	end

	local castBar
	function lib:GetCastBar(frame)
		if frame.extended and frame.extended.bars and frame.extended.bars.castbar then
			return frame.extended.bars.castbar
		elseif frame.aloftData and frame.aloftData.castBar then
			return frame.aloftData.castBar
		end
		castBar = select(childIndex.castBar, frame:GetChildren())
		return castBar
	end
end

do
	local frame, region
	function lib:GetName(frame)
		frame = self.realPlate[frame] or frame
		region = self.plateRegions[frame].nameText
		if region and region.GetText then
			return noColorText[region:GetText()]
		end
		return nil
	end

	function lib:IsInCombat(frame)
		frame = self.realPlate[frame] or frame

		region = self.plateRegions[frame].nameText
		if region and region.GetTextColor then
			return combatByColor(region:GetTextColor()) and true or false
		end

		return nil
	end
end

do
	local frame, region
	function lib:GetLevel(frame)
		frame = self.realPlate[frame] or frame
		region = self.plateRegions[frame].levelText
		if region and region.GetText then
			return noColorNum[region:GetText()]
		end
		return 0
	end

	local greenRange = 5 --GetQuestGreenRange()
	local UnitLevel = UnitLevel
	local pLevel, levelDiff
	function lib:GetLevelDifficulty(frame)
		pLevel = self:GetLevel(frame)
		levelDiff = pLevel - UnitLevel("player")
		if (levelDiff >= 5) then
			return "impossible"
		elseif (levelDiff >= 3) then
			return "verydifficult"
		elseif (levelDiff >= -2) then
			return "difficult"
		elseif (-levelDiff <= greenRange) then
			return "standard"
		else
			return "trivial"
		end
	end
end

do
	local region

	function lib:IsBoss(frame)
		frame = self.realPlate[frame] or frame
		region = self.plateRegions[frame].bossIcon
		if region and region.IsShown then
			return region:IsShown() and true or false
		end
		return false
	end
end

do
	local region

	function lib:IsElite(frame)
		frame = self.realPlate[frame] or frame
		region = self.plateRegions[frame].eliteIcon
		if region and region.IsShown then
			return region:IsShown() and true or false
		end
		return false
	end
end

do
	local region

	function lib:GetThreatSituation(frame)
		frame = self.realPlate[frame] or frame

		region = self.plateRegions[frame].threatTexture
		if region and region.GetVertexColor then
			return threatByColor(region)
		end
		return nil
	end
end

do
	local region

	function lib:IsMouseover(frame)
		frame = self.realPlate[frame] or frame
		region = self.plateRegions[frame].highlightTexture
		if region and region.IsShown then
			return region:IsShown() and true or false
		end
		return nil
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
		region = self.plateRegions[frame].highlightTexture
		if region and region.Hide then
			region:Hide()
		end
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

	local region, ULx, ULy
	function lib:GetRaidIcon(frame)
		frame = self.realPlate[frame] or frame

		region = self.plateRegions[frame].raidIcon
		if region and region.IsShown and region:IsShown() and region.GetTexCoord then
			ULx, ULy = region:GetTexCoord()

			if ULx and ULy then
				return raidIconTexCoord[ULx] and raidIconTexCoord[ULx][ULy] or 0
			end
		end

		return nil
	end

	function lib:IsMarked(frame)
		frame = self.realPlate[frame] or frame

		region = self.plateRegions[frame].raidIcon
		if region and region.IsShown then
			return region:IsShown() and true or false
		end

		return nil
	end
end

do
	local bar
	function lib:IsCasting(frame)
		frame = self.realPlate[frame] or frame
		bar = self.plateChildren[frame].castBar
		if bar and bar.IsShown then
			return bar:IsShown() and true or false
		end
		return nil
	end
end

do
	local select = select
	local r, g, b
	function lib:GetType(frame)
		frame = self.realPlate[frame] or frame
		r, g, b = GetHealthBarColor(frame)
		if r then
			return select(2, reactionByColor(r, g, b))
		end
		return nil
	end

	function lib:GetReaction(frame)
		frame = self.realPlate[frame] or frame
		r, g, b = GetHealthBarColor(frame)
		if r then
			return reactionByColor(r, g, b)
		end
		return nil
	end

	local math_floor = math.floor
	local colorToClass = {}
	local function pctToInt(number)
		return math_floor((100 * number) + 0.5)
	end
	for classname, color in pairs(RAID_CLASS_COLORS) do
		colorToClass["C" .. pctToInt(color.r) + pctToInt(color.g) + pctToInt(color.b)] = classname
	end

	function lib:GetClass(frame)
		frame = self.realPlate[frame] or frame
		r, g, b = GetHealthBarColor(frame)
		if r then
			return colorToClass["C" .. pctToInt(r) + pctToInt(g) + pctToInt(b)] or nil
		end
		return nil
	end
end

do
	local tonumber = tonumber

	local bar
	function lib:GetHealthMax(frame)
		frame = self.realPlate[frame] or frame

		bar = self.plateChildren[frame].healthBar
		if bar and bar.GetMinMaxValues then
			local _, max = bar:GetMinMaxValues()
			return tonumber(max or 0)
		end
		return nil
	end

	function lib:GetHealth(frame)
		frame = self.realPlate[frame] or frame

		bar = self.plateChildren[frame].healthBar
		if bar and bar.GetValue then
			return bar:GetValue()
		end
		return nil
	end
end

function lib:GetGUID(frame)
	frame = self.realPlate[frame] or frame
	return self.plateGUIDs[frame]
end

do
	local UnitExists = UnitExists
	local pairs = pairs
	function lib:GetTargetNameplate()
		if UnitExists("target") then
			for frame in pairs(self.nameplates) do
				if frame:IsShown() and frame:GetAlpha() == 1 then
					return self.fakePlate[frame] or frame
				end
			end
		end
		return nil
	end
end

do
	local pairs = pairs
	function lib:GetNameplateByGUID(GUID)
		for frame, fGUID in pairs(self.plateGUIDs) do
			if fGUID == GUID then
				return self.fakePlate[frame] or frame
			end
		end
		return nil
	end
end

do
	local pairs = pairs
	local _
	local bar, barMax
	function lib:GetNameplateByName(name, maxHp)
		for frame in pairs(self.nameplates) do
			if frame:IsShown() then
				if name == lib:GetName(frame) then
					if not maxHp then
						return self.fakePlate[frame] or frame
					end
					bar = self.plateChildren[frame].healthBar
					if bar and bar.GetMinMaxValues then
						_, barMax = bar:GetMinMaxValues()
						if barMax == maxHp then
							return self.fakePlate[frame] or frame
						end
					end
				end
			end
		end
	end
end

do
	local UnitIsUnit = UnitIsUnit
	local UnitGUID = UnitGUID
	local UnitHealth = UnitHealth
	local UnitHealthMax = UnitHealthMax
	local UnitName = UnitName

	local GUID
	local health
	local maxHealth
	local frame
	function lib:GetNameplateByUnit(unitID)
		if UnitIsUnit(unitID, "target") then
			return self:GetTargetNameplate()
		end
		frame = self:GetNameplateByGUID(UnitGUID(unitID))
		if frame then
			return frame
		end
		return self:GetNameplateByName(UnitName(unitID), UnitHealthMax(unitID))
	end
end

do
	local wipe = wipe
	local pairs = pairs
	local table_insert = table.insert
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
	local wipe = wipe
	local pairs = pairs
	local table_insert = table.insert

	local possibleFrames = {}
	local bar, barMax, barCurrent, _
	function lib:GetNameplateByHealth(current, max)
		wipe(possibleFrames)

		for frame in pairs(self.nameplates) do
			if frame:IsShown() then
				bar = self.plateChildren[frame].healthBar

				if bar and bar.GetMinMaxValues then
					_, barMax = bar:GetMinMaxValues()
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
		return nil
	end
end