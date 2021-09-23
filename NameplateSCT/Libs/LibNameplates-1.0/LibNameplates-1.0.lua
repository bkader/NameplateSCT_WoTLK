--[[
Name: LibNameplates-1.0
Original Author(s): Cyprias (cyprias@gmail.com)
Documentation: http://www.wowace.com/addons/libnameplate-1-0/pages/main/
SVN:  svn://svn.wowace.com/wow/libnameplate-1-0/mainline/trunk
Description: Alerts addons when a nameplate is shown or hidden. Has API to get info such as name, level, class, ect from the nameplate. LibNameplates tries to function with the default nameplates, Aloft, caelNamePlates and TidyPlates (buggy).
Dependencies: LibStub, CallbackHandler-1.0
]]
local MAJOR, MINOR = "LibNameplates-1.0", 22
if not LibStub then
	error(MAJOR .. " requires LibStub.")
	return
end

local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)
if not lib.callbacks then
	error(MAJOR .. " CallbackHandler-1.0.")
	return
end

-- Globals
local _G = _G
local tostring = tostring
local WorldFrame = WorldFrame
local select = select
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitName = UnitName
local pairs = pairs
local table_insert = table.insert
local GetMouseFocus = GetMouseFocus
local GetNumRaidMembers = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local UnitIsUnit = UnitIsUnit
local GetRaidTargetIndex = GetRaidTargetIndex
local print = print
local table_getn = table.getn
local IsAddOnLoaded = IsAddOnLoaded
local unpack = unpack
local math_floor = math.floor
local tonumber = tonumber
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitClass = UnitClass
local UnitInRange = UnitInRange
local table_remove = table.remove
local _

--Conts
local scanDelay = 1 -- Scan for new nameplates every 1 seconds. We hook OnShow so this doesn't need to be done rapidly.
local updateDelay = 1 -- Update nameplate info every 1 seconds. This checks if a nameplate has a raid icon then trys to find the GUID to that icon.

local DEBUG = false
--[===[@debug@
DEBUG = true
--@end-debug@]===]

lib.realPlate = lib.realPlate or {}
lib.fakePlate = lib.fakePlate or {}

local function CmdHandler()
	DEBUG = not DEBUG
end
_G.SlashCmdList["LIBNAMEPLATEDEBUG"] = CmdHandler
_G.SLASH_LIBNAMEPLATEDEBUG1 = "/lnbug"
local function debugPrint(...)
	if DEBUG then
		print(...)
	end
end
lib.debugPrint = debugPrint

lib.nameplates = lib.nameplates or {}
lib.GUIDs = lib.GUIDs or {}
lib.onShowHooks = lib.onShowHooks or {}
lib.onHideHooks = lib.onHideHooks or {}
lib.onUpdateHooks = lib.onUpdateHooks or {}
lib.healthOnValueChangedHooks = lib.healthOnValueChangedHooks or {}

lib.plateGUIDs = lib.plateGUIDs or {}
lib.isOnScreen = lib.isOnScreen or {}
lib.isOnUpdating = lib.isOnUpdating or {}
lib.prevHealth = lib.prevHealth or {}

--Region locations
lib.name_region = lib.name_region or setmetatable({}, {__index = function(t, frame)
	t[frame] = lib:GetNameRegion(frame)
	return t[frame]
end})
lib.level_region = lib.level_region or setmetatable({}, {__index = function(t, frame)
	t[frame] = lib:GetLevelRegion(frame)
	return t[frame]
end})
lib.boss_region = lib.boss_region or setmetatable({}, {
__index = function(t, frame)
	t[frame] = lib:GetBossRegion(frame)
	return t[frame]
end})
lib.elite_region = lib.elite_region or setmetatable({}, {__index = function(t, frame)
	t[frame] = lib:GetEliteRegion(frame)
	return t[frame]
end})
lib.threat_region = lib.threat_region or setmetatable({}, {__index = function(t, frame)
	t[frame] = lib:GetThreatRegion(frame)
	return t[frame]
end})
lib.hightlight_region = lib.hightlight_region or setmetatable({}, {__index = function(t, frame)
	t[frame] = lib:GetHightlightRegion(frame)
	return t[frame]
end})
lib.raidicon_region = lib.raidicon_region or setmetatable({}, {__index = function(t, frame)
	t[frame] = lib:GetRaidIconRegion(frame)
	return t[frame]
end})

--bar locations
lib.health_bar = lib.health_bar or setmetatable({}, { __index = function(t, frame)
	t[frame] = lib:GetHealthBar(frame)
	return t[frame]
end})
lib.cast_bar = lib.cast_bar or setmetatable({}, { __index = function(t, frame)
	t[frame] = lib:GetCastBar(frame)
	return t[frame]
end})

lib.combatStatus = lib.combatStatus or {}
lib.threatStatus = lib.threatStatus or {}

--[[
TidyPlate region names
	old: "threatGlow", "healthBorder", "castBorder", "castNostop", "spellIcon", "highlightTexture", "nameText", "levelText", "dangerSkull", "raidIcon", "eliteIcon"
	new: "threatGlow", "healthborder", "castborder", "castnostop", "spellicon", "highlight", "name", "level", "dangerskull", "raidicon", "eliteicon"
TidyPlate child names
	old: "healthBar", "castBar"
	new: "castbar", "healthbar"

TidyPlate 'frame.regions' names.
	castborder, castnostop, dangerskull, eliteicon, healthborder, highlight, level, name, raidicon, specialArt, specialText, specialText2, threatGlow, threatborder
TidyPlate 'frame.bars' names.
	cast (real), castbar, health (real), healthbar,
]]
local regionNames = {
	"threatGlow",
	"healthBorder",
	"castBorder",
	"castNostop",
	"spellIcon",
	"highlightTexture",
	"nameText",
	"levelText",
	"dangerSkull",
	"raidIcon",
	"eliteIcon"
}
local regionIndex = {}
for i, name in pairs(regionNames) do
	regionIndex[name] = i
end

local barNames = {"healthBar", "castBar"}
local barIndex = {}
for i, name in pairs(barNames) do
	barIndex[name] = i
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
		return false
	end

	if frame:GetID() ~= 0 then
		return false
	end

	if frame:GetObjectType() ~= "Frame" then
		return false
	end

	if frame:GetNumChildren() == 0 then
		return false
	end

	if frame:GetNumRegions() == 0 then
		return false
	end

	return true
end

local function ScanWorldFrameChildren(frame, ...)
	if not frame then return end
	if frame:IsShown() and not lib.nameplates[frame] and IsNamePlateFrame(frame) then
		lib:NameplateFirstLoad(frame)
	end
	return ScanWorldFrameChildren(...)
end

local prevChildren = 0
local function FindNameplates()
	local curChildren = WorldFrame:GetNumChildren()
	if curChildren ~= prevChildren then
		prevChildren = curChildren
		ScanWorldFrameChildren(WorldFrame:GetChildren())
	end
end

---------------------------
-- Get region locations
----------------------------
function lib:GetNameRegion(frame)
	if frame.extended and frame.extended.regions and frame.extended.regions.name then --TidyPlates
		return frame.extended.regions.name
	elseif frame.aloftData and frame.aloftData.nameTextRegion then --Aloft
		return frame.aloftData.nameTextRegion
	elseif frame.kui then --KuiNameplates
		return frame.kui.oldName
	elseif frame.oldname then --dNameplates
		return frame.oldname
	end

	local region = select(regionIndex.nameText, frame:GetRegions())
	return region
end

function lib:GetLevelRegion(frame)
	if frame.extended and frame.extended.regions and frame.extended.regions.level then --TidyPlates
		return frame.extended.regions.level
	elseif frame.aloftData and frame.aloftData.levelTextRegion then --Aloft
		return frame.aloftData.levelTextRegion
	elseif frame.kui then --KuiNameplates
		return frame.kui.level
	elseif frame.level then --dNameplates
		return frame.level
	end

	return select(regionIndex.levelText, frame:GetRegions())
end

function lib:GetBossRegion(frame)
	if frame.extended and frame.extended.regions and frame.extended.regions.dangerskull then --tidyPlates
		return frame.extended.regions.dangerskull
	elseif frame.aloftData and frame.aloftData.bossIconRegion then --aloft
		return frame.aloftData.bossIconRegion
	elseif frame.kui then --KuiNameplates
		return frame.kui.boss
	elseif frame.boss then --dNameplates
		return frame.boss
	end
	return select(regionIndex.dangerSkull, frame:GetRegions())
end

function lib:GetEliteRegion(frame)
	if frame.extended and frame.extended.regions and frame.extended.regions.eliteicon then --tidyPlates
		return frame.extended.regions.eliteicon
	elseif frame.aloftData and frame.aloftData.stateIconRegion then --aloft
		return frame.aloftData.stateIconRegion
	elseif frame.kui then --KuiNameplates
		return frame.kui.state
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
	elseif frame.kui then --KuiNameplates
		return frame.kui.glow
	elseif frame.oldglow then --dNameplates
		return frame.oldglow
	end

	return select(regionIndex.threatGlow, frame:GetRegions())
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
	elseif frame.kui then --KuiNameplates
		return frame.kui.highlight
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
	elseif frame.kui then
		return frame.kui.icon
	end
	return select(regionIndex.raidIcon, frame:GetRegions())
end

----------------------
-- Get bar frames
----------------------
function lib:GetHealthBar(frame)
	if frame.extended and frame.extended.bars and frame.extended.bars.health then
		--Aloft changes the bar color. Our functions will have to use aloftData.originalHealthBarR
		return frame.extended.bars.health
	elseif frame.kui then --KuiNameplates
		return frame.kui.oldHealth
	elseif frame.healthOriginal then --dNameplates
		return frame.healthOriginal
	end
	return select(barIndex.healthBar, frame:GetChildren())
end

function lib:GetCastBar(frame)
	if frame.extended and frame.extended.bars and frame.extended.bars.castbar then
		return frame.extended.bars.castbar
	elseif frame.kui and frame.kui.castBar then
		return frame.kui.castBar
	elseif frame.aloftData and frame.aloftData.castBar then
		return frame.aloftData.castBar
	end
	return select(barIndex.healthBar, frame:GetChildren())
end

------------------------------------------------------------------------------------------------------------------
local function HideMouseoverRegion(frame) --
-- If we move the camera angle while the mouse is over a plate, that plate won't hide the mouseover texture.	--
-- So if we're mousing over someone's feet and a plate has the mouseover texture visible, 						--
-- it fools our code into thinking we're mousing over that plate.												--
-- This can be recreated by placing the mouse over a nameplate then holding rightclick and moving the camera.	--
-- If our UpdateNameplateInfo sees the mouseover texture still visible when we have no mouseoverID, it'll call	--
-- this function to hide the texture.																			--
------------------------------------------------------------------------------------------------------------------
	local region = lib.hightlight_region[frame]
	if region and region.Hide then
		region:Hide()
	end
end

local function RecycleNameplate(frame)
	lib.callbacks:Fire("LibNameplates_RecycleNameplate", lib.fakePlate[frame] or frame)
	if lib.plateGUIDs[frame] then
		lib.GUIDs[lib.plateGUIDs[frame]] = false
	end

	local plateName = lib:GetName(frame)
	lib.plateGUIDs[frame] = false
	local fake = lib.fakePlate[frame]
	if fake then
		lib.realPlate[fake] = false
	end
	lib.fakePlate[frame] = false
end

local function FoundPlateGUID(frame, GUID, unitID)
	lib.plateGUIDs[frame] = GUID
	lib.GUIDs[GUID] = frame
	lib.callbacks:Fire("LibNameplates_FoundGUID", lib.fakePlate[frame] or frame, GUID, unitID)
end

local function GetMouseoverGUID(frame)
	local unitID = "mouseover"
	if UnitExists(unitID) then
		FoundPlateGUID(frame, UnitGUID(unitID), unitID)
	end
end

local function FindPlateWithRaidIcon(iconNum)
	for frame in pairs(lib.nameplates) do
		if lib:IsMarked(frame) and lib:GetRaidIcon(frame) == iconNum then
			return frame
		end
	end
	return nil
end

local function CheckRaidIconOnUnit(unitID, frame, raidNum, from)
	local targetID = unitID .. "target"
	local targetIndex

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

local function FindGUIDByRaidIcon(frame, raidNum, from)
	local group, num = "", 0
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

		if UnitExists(unitID .. "pet") then
			if CheckRaidIconOnUnit(unitID .. "pet", frame, raidNum, from) then
				return
			end
		end
	end
end

local function UpdateNameplateInfo(frame)
	if lib:IsMouseover(frame) and not UnitExists("mouseover") then
		HideMouseoverRegion(frame)
	end

	if not lib.plateGUIDs[frame] then
		if lib:IsMouseover(frame) then
			GetMouseoverGUID(frame)
		elseif lib:IsMarked(frame) then
			local raidNum = lib:GetRaidIcon(frame)
			if raidNum and raidNum > 0 then
				FindGUIDByRaidIcon(frame, raidNum, "UpdateNameplateInfo")
			end
		end
	end
	frame.lnpLastUpdate = 0
end

local function CheckUnitIDForMatchingHP(unitID, frameName, current, max)
	local targetID = unitID .. "target"

	if UnitName(targetID) == frameName then
		local health = UnitHealth(targetID)
		local maxHealth = UnitHealthMax(targetID)

		if health == current and maxHealth == max then
			return true
		end
	end
	return false
end

function lib:NewNameplateCheckHP(frame)
	local bar = self.health_bar[frame]
	if bar and bar.GetValue then
		local _, max = bar:GetMinMaxValues()
		local current = bar:GetValue()
		lib.prevHealth[frame] = current

		if current > 0 and current ~= max then
			local group, num = "", 0
			if GetNumRaidMembers() > 1 then
				group, num = "raid", GetNumRaidMembers()
			elseif GetNumPartyMembers() > 0 then
				group, num = "party", GetNumPartyMembers()
			else
				return
			end

			local possibleUnits = {}

			local frameName = self:GetName(frame)
			local unitID, targetID, targetIndex
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

function lib.OnNameplateShow(frame, ...)
	lib:SetupNameplate(frame)
	lib:NewNameplateCheckHP(frame)
end
local function ourOnShow(...)
	return lib.OnNameplateShow(...)
end

function lib.OnNameplateHide(frame, ...)
	lib.isOnScreen[frame] = false
	lib.isOnUpdating[frame] = false
	lib.combatStatus[frame] = false
	RecycleNameplate(frame)
end
local function ourOnHide(...)
	return lib.OnNameplateHide(...)
end

lib.callbacksRegistered = lib.callbacksRegistered or {}

function lib.callbacks:OnUsed(target, eventname)
	lib.callbacksRegistered[eventname] = lib.callbacksRegistered[eventname] or {}
	table_insert(lib.callbacksRegistered[eventname], #lib.callbacksRegistered[eventname] + 1, target)
	lib.ModifyOnUpdate()
end

function lib.callbacks:OnUnused(target, eventname)
	if lib.callbacksRegistered[eventname] then
		for i = 1, #lib.callbacksRegistered[eventname] do
			if lib.callbacksRegistered[eventname][i] == target then
				table_remove(lib.callbacksRegistered[eventname], i)
				break
			end
		end
	end

	lib.ModifyOnUpdate()
end

local function CheckForFakePlate(frame)
	if not lib.fakePlate[frame] and frame.extended then
		lib.realPlate[frame.extended] = frame
		lib.fakePlate[frame] = frame.extended

		lib.callbacks:Fire("LibNameplates_RecycleNameplate", frame)
		 --Hide real plate so addon unhook their stuff.
		lib.callbacks:Fire("LibNameplates_NewNameplate", lib.fakePlate[frame])
	end
end

local function CheckCombatStatus(frame)
	local inCombat = lib:IsInCombat(frame)
	if lib.combatStatus[frame] ~= inCombat then
		lib.combatStatus[frame] = inCombat
		lib.callbacks:Fire("LibNameplates_CombatChange", lib.fakePlate[frame] or frame, inCombat)
	end
end

local function CheckThreatStatus(frame)
	local threatSit = lib:GetThreatSituation(frame)
	if lib.threatStatus[frame] ~= threatSit then
		lib.threatStatus[frame] = threatSit
		lib.callbacks:Fire("LibNameplates_ThreatChange", lib.fakePlate[frame] or frame, threatSit)
	end
end

function lib.OnNameplateUpdate(frame, elapsed, ...)
	lib.isOnUpdating[frame] = true --to make sure our hooks don't break.
	if frame.lnpCheckForTarget then --Check on the first OnUpdate after the frame's shown.
		frame.lnpCheckForTarget = false
		if not lib.plateGUIDs[frame] and frame:IsShown() and ((frame:GetAlpha() == 1) and UnitExists("target")) then
			FoundPlateGUID(frame, UnitGUID("target"), "target")
		end
	end

	frame.lnpLastUpdate = (frame.lnpLastUpdate or 0) + elapsed
	if frame.lnpLastUpdate > updateDelay then
		UpdateNameplateInfo(frame)

		CheckForFakePlate(frame)
		CheckCombatStatus(frame)
		CheckThreatStatus(frame)
	elseif frame.updateCountdown > 0 then
		--Threat doesn't get updated until the first OnUpdate. So OnShow sometimes sees the threat of the previous nameplate owner.
		--So I wait unit the 2nd OnUpdate to check threat status.
		frame.updateCountdown = frame.updateCountdown - 1
		if frame.updateCountdown == 0 then
			CheckThreatStatus(frame)
		end
	end
end
local function ourOnUpdate(...)
	return lib.OnNameplateUpdate(...)
end

--------------------------------------------------------------------------------------
function lib.healthOnValueChanged(frame, ...) --
-- This fires before OnShow fires and the regions haven't been updated yet. 		--
-- So I make sure lib.isOnScreen[plate] is true before working on the HP change.	--
--------------------------------------------------------------------------------------
	local plate = frame.kuiParent or frame:GetParent()
	local currentHP = ...

	--strange, when a nameplate's not on screen, we still get HP changes. It's not relyable but might be of use somehow...
	if plate and lib.isOnScreen[plate] and (not lib.prevHealth[plate] or lib.prevHealth[plate] ~= currentHP) then
		lib.callbacks:Fire("LibNameplates_HealthChange", frame, ...)
		local plateName = lib:GetName(plate)
		if not lib.plateGUIDs[plate] then
			lib:NewNameplateCheckHP(plate)
		end
	end
end
local function ourHealthOnValueChanged(...)
	return lib.healthOnValueChanged(...)
end

local testing = false

function lib:HookNameplate(frame)
	if frame:HasScript("OnHide") and not self.onHideHooks[frame] then
		self.onHideHooks[frame] = true
		frame:HookScript("OnHide", ourOnHide)
	end

	if frame:HasScript("OnShow") and not self.onShowHooks[frame] then
		self.onShowHooks[frame] = true
		frame:HookScript("OnShow", ourOnShow)
	end

	if frame:HasScript("OnUpdate") and not self.onUpdateHooks[frame] then
		self.onUpdateHooks[frame] = true
		frame:HookScript("OnUpdate", ourOnUpdate)
	end

	local healthBar = self.health_bar[frame]
	if healthBar and not self.healthOnValueChangedHooks[frame] and healthBar:HasScript("OnValueChanged") then
		self.healthOnValueChangedHooks[frame] = true
		healthBar:HookScript("OnValueChanged", ourHealthOnValueChanged)
	end
end

function lib:NameplateFirstLoad(frame)
	if not lib.nameplates[frame] then
		--Hook handlers.
		self:HookNameplate(frame)

		--Save frame's combat status as false.
		if self.combatStatus[frame] == nil then
			self.combatStatus[frame] = false --not in combat
		end

		if self.threatStatus[frame] == nil then
			self.threatStatus[frame] = "LOW"
		end

		lib:SetupNameplate(frame)
	end
end

function lib:SetupNameplate(frame)
	self.isOnScreen[frame] = true --to make sure our hooks don't break.

	local plateName = self:GetName(frame)
	self.nameplates[frame] = plateName
	lib.threatStatus[frame] = self:GetThreatSituation(frame) --Save it during OnShow. Sometimes this returns the threat of the previous owner of the nameplate. Our OnUpdate will check for changes and fire ThreatChanged callback.

	--TidyPlates replace the orginal frame with their own.
	--Lets save this and give that frame to addons. It's better for anchors.
	if frame.extended and not self.fakePlate[frame] then
		self.fakePlate[frame] = frame.extended
		self.realPlate[frame.extended] = frame

		--Without this was causing problems with PlateBuffs where it was never told the real plate was gone.
		self.callbacks:Fire("LibNameplates_RecycleNameplate", frame)
	-- same goes for KuiNameplates
	elseif frame.kui and not self.fakePlate[frame] then
		self.fakePlate[frame] = frame.kui
		self.realPlate[frame.kui] = frame
		self.callbacks:Fire("LibNameplates_RecycleNameplate", frame)
	end

	self.callbacks:Fire("LibNameplates_NewNameplate", self.fakePlate[frame] or frame)

	frame.lnpCheckForTarget = true

	UpdateNameplateInfo(frame)
	frame.updateCountdown = 2
end

local function CheckForTargetGUID()
	local unitID = "target"
	local GUID
	for frame in pairs(lib.nameplates) do
		if lib:IsTarget(frame) then
			lib.targeted = frame
			if not lib.plateGUIDs[frame] then
				FoundPlateGUID(frame, UnitGUID(unitID), unitID)
			end
			lib.callbacks:Fire("LibNameplates_TargetNameplate", lib.fakePlate[frame] or frame)
			return
		end
	end
end

local function MainOnEvent(frame, event, ...)
	if event == "UPDATE_MOUSEOVER_UNIT" then
		if GetMouseFocus():GetName() == "WorldFrame" then
			local i = 0
			local mouseoverPlate
			for frame in pairs(lib.nameplates) do
				if frame:IsShown() and lib:IsMouseover(frame) then
					i = i + 1
					mouseoverPlate = frame
				end
			end
			if i == 1 then
				if not lib.plateGUIDs[mouseoverPlate] then
					GetMouseoverGUID(mouseoverPlate)
				end
				lib.callbacks:Fire("LibNameplates_MouseoverNameplate", lib.fakePlate[mouseoverPlate] or mouseoverPlate)
			elseif i > 1 then
				debugPrint(i .. " mouseover frames")
			end
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		lib.targeted = nil

		if UnitExists("target") then
			lib.checkTarget:Show() --Target's nameplate alpha isn't update until the next OnUpdate fires.
		end
	elseif event == "UNIT_TARGET" then
		local unitID = ...
		local targetID = unitID .. "target"
		if UnitExists(targetID) and not UnitIsUnit("player", unitID) and UnitInRange(unitID) then
			local targetGUID = UnitGUID(targetID)
			local iconNum = GetRaidTargetIndex(targetID)
			if iconNum and iconNum > 0 then
				local foundPlate = FindPlateWithRaidIcon(iconNum)
				if foundPlate and not lib.plateGUIDs[foundPlate] then
					--~ 					debugPrint(event, "Found raid icon on ", UnitName(unitID), "'s target", UnitName(targetID), "icon:"..tostring(iconNum))
					FoundPlateGUID(foundPlate, targetGUID, targetID)
				end
			end

			if lib.GUIDs[targetGUID] and lib.GUIDs[targetGUID]:IsShown() then
				return
			end

			local health = UnitHealth(targetID)
			local maxHealth = UnitHealthMax(targetID)
			if health > 0 and health ~= maxHealth then
				local foundPlate = lib:GetNameplateByHealth(health, maxHealth)
				if foundPlate and not lib.plateGUIDs[foundPlate] then
					local name = UnitName(targetID)
					if name == lib:GetName(foundPlate) then
						FoundPlateGUID(foundPlate, targetGUID, targetID)
					end
				end
			end
		end
	elseif event == "RAID_TARGET_UPDATE" then
		for frame in pairs(lib.nameplates) do
			if frame:IsShown() and not lib.plateGUIDs[frame] and lib:IsMarked(frame) then
				local raidNum = lib:GetRaidIcon(frame)
				if raidNum and raidNum > 0 then
					FindGUIDByRaidIcon(frame, raidNum, event)
				end
			end
		end
	end
end

lib.frame = lib.frame or CreateFrame("Frame")
lib.frame.lastUpdate = 0
lib.frame.lastHPCheck = 0
lib.frame:SetScript("OnEvent", MainOnEvent)
lib.frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
lib.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
lib.frame:RegisterEvent("UNIT_TARGET")
lib.frame:RegisterEvent("RAID_TARGET_UPDATE")
lib.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
lib.frame:SetScript("OnUpdate", function(this, elapsed) FindNameplates() end)

--To find our target's nameplate, we need to wait for 1 OnUpdate to fire after PLAYER_TARGET_CHANGED.
lib.checkTarget = lib.checkTarget or CreateFrame("Frame")
lib.checkTarget:Hide()
lib.checkTarget:SetScript("OnUpdate", function(this, elapsed)
	CheckForTargetGUID()
	this:Hide()
end)

lib.fixHooks = lib.fixHooks or CreateFrame("Frame")
lib.fixHooks.updateThrottle = 1 --fire once a second.
lib.fixHooks.lastUpdate = 0
lib.fixHooks:SetScript("OnUpdate", function(this, elapsed)
	--code searches for broken OnShow/OnHide hooks.
	--some nameplate addons will use SetScript instead of HookScript and breaks our hooks.
	this.lastUpdate = this.lastUpdate - elapsed
	if this.lastUpdate <= 0 then
		this.lastUpdate = this.updateThrottle
		for frame, value in pairs(lib.isOnScreen) do
			if (value == true and not frame:IsShown()) then --OnHide fail
				debugPrint("OnHide fail", frame, value, frame:IsShown())
				lib.onHideHooks[frame] = false
				lib.isOnScreen[frame] = false
				lib:HookNameplate(frame)
				lib.OnNameplateHide(frame)
			elseif (value == false and frame:IsShown()) then --OnShow fail
				debugPrint("OnShow fail", frame, value, frame:IsShown())
				lib.onShowHooks[frame] = false
				lib.isOnScreen[frame] = false
				lib:HookNameplate(frame)
				lib:SetupNameplate(frame, true)
			end
		end
		for frame, value in pairs(lib.isOnUpdating) do
			if value == false and frame:IsShown() then
				debugPrint("OnUpdate fail?")
				lib.onUpdateHooks[frame] = false
				lib:HookNameplate(frame)
			end
		end
	end
end)

--------------------- API ------------------
local raidIconTexCoord = {
	--from GetTexCoord. input is ULx and ULy (first 2 values).
	[0] = {
		[0] = 1, --star
		[0.25] = 5 --moon
	},
	[0.25] = {
		[0] = 2, --circle
		[0.25] = 6 --square
	},
	[0.5] = {
		[0] = 3, --star
		[0.25] = 7 --cross
	},
	[0.75] = {
		[0] = 4, --star
		[0.25] = 8 --skull
	}
}

--Support functions for API.
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

local RAID_CLASS_COLORS = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
local colorToClass = {}
local function pctToInt(number)
	return math_floor((100 * number) + 0.5)
end
for classname, color in pairs(RAID_CLASS_COLORS) do
	colorToClass["C" .. pctToInt(color.r) + pctToInt(color.g) + pctToInt(color.b)] = classname
end

local function threatByColor(region)
	if not region:IsShown() then
		return "LOW"
	end

	local redCan, greenCan, blueCan, alphaCan = region:GetVertexColor()
	if greenCan > 0.7 then
		return "MEDIUM"
	end
	if redCan > 0.7 then
		return "HIGH"
	end
end

local function combatByColor(r, g, b, a)
	return (r > 0.5 and g < 0.5)
end

local function GetHealthBarColor(frame)
	if frame.aloftData then
		local r, g, b = frame.aloftData.originalHealthBarR, frame.aloftData.originalHealthBarG, frame.aloftData.originalHealthBarB
		return r, g, b
	end

	if frame.originalR and frame.originalG and frame.originalB then
		--dNamePlates changes the color of the healthbar. r7 now saves the original colors. TY Dawn.
		return frame.originalR, frame.originalG, frame.originalB
	end

	local bar = lib.health_bar[frame]
	if bar and bar.GetStatusBarColor then
		return bar:GetStatusBarColor()
	end
	return nil
end

lib.noColorName = lib.noColorName or setmetatable({}, {__index = function(t, inputString)
	if inputString then
		if inputString:find("|c") then
			local input = inputString
			local find = inputString:find("|c")
			local inputString = inputString:sub(find + 10)
			inputString = inputString:gsub("|r", "")
			t[input] = inputString
			return inputString
		end
		t[inputString] = inputString
	end
	return inputString or "UNKNOWN"
end})

lib.noColorNum = lib.noColorNum or setmetatable({}, {__index = function(t, inputString)
	if inputString then
		if inputString:find("|c") then
			local input = inputString
			local find = inputString:find("|c")
			local inputString = inputString:sub(find + 10)
			inputString = inputString:gsub("|r", "")
			inputString = tonumber(inputString or 0)
			t[input] = inputString
			return inputString
		end
		t[inputString] = tonumber(inputString or 0)
	end
	return inputString or 0
end})

--~ --------------------------------------------------------------
--~ local function RemoveHexColor(inputString)					--
--~ -- Remove hex color code from string. 						--
--~ -- Aloft uses hex codes to color name and level regions.	--
--~ --------------------------------------------------------------
--~ 	if inputString and inputString:find("|c") then
--~ 		local find = inputString:find("|c")
--~ 		inputString = inputString:sub(find+10)
--~ 		inputString = inputString:gsub("|r", "")
--~ 	end
--~ 	return inputString
--~ end

--API

function lib:GetName(frame)
	local frame = self.realPlate[frame] or frame
	local nameRegion = self.name_region[frame]
	if nameRegion and nameRegion.GetText then
		return self.noColorName[nameRegion:GetText()]
	end
	return nil
end

function lib:GetLevel(frame)
	local frame = self.realPlate[frame] or frame
	local region = self.level_region[frame]
	if region and region.GetText then
		return self.noColorNum[region:GetText()]
	end
	return 0
end

function lib:GetScale(frame)
	local frame = self.realPlate[frame] or frame
	if frame.extended then
		frame = frame.extended
	elseif frame.kui then
		frame = frame.kui
	end
	return frame:GetScale()
end

function lib:GetVisibleFrame(frame)
	local frame = self.realPlate[frame] or frame
	if frame.extended then
		frame = frame.extended
	elseif frame.kui then
		frame = frame.kui
	end
	return frame
end

function lib:GetReaction(frame)
	local frame = self.realPlate[frame] or frame

	local r, g, b = GetHealthBarColor(frame)
	if r then
		return reactionByColor(r, g, b)
	end

	return nil
end

function lib:GetType(frame)
	local frame = self.realPlate[frame] or frame

	local r, g, b = GetHealthBarColor(frame)
	if r then
		return select(2, reactionByColor(r, g, b))
	end

	return nil
end

function lib:IsBoss(frame)
	local frame = self.realPlate[frame] or frame

	local region = self.boss_region[frame]
	if region and region.IsShown then
		return region:IsShown() and true or false
	end

	return nil
end

--This will return nil if we're not in a PvP zone (like in cities)
function lib:GetClass(frame)
	local frame = self.realPlate[frame] or frame

	local r, g, b = GetHealthBarColor(frame)
	if r then
		return colorToClass["C" .. pctToInt(r) + pctToInt(g) + pctToInt(b)] or nil
	end

	return nil
end

function lib:IsElite(frame)
	local frame = self.realPlate[frame] or frame

	local region = self.elite_region[frame]
	if region and region.IsShown then
		return region:IsShown() and true or false
	end
	return nil
end

-- Note: GetThreatSituation sometimes returns wrong info on OnShow (NewNameplate) event.
-- It sometimes returns the previous owner of the nameplate's threat.
function lib:GetThreatSituation(frame)
	local frame = self.realPlate[frame] or frame

	local region = self.threat_region[frame]
	if region and region.GetVertexColor then
		return threatByColor(region)
	end

	return nil
end

function lib:IsTarget(frame)
	local frame = self.realPlate[frame] or frame
	return frame:IsShown() and frame:GetAlpha() == 1 and UnitExists("target") or false
end

function lib:GetHealthMax(frame)
	local frame = self.realPlate[frame] or frame

	local bar = self.health_bar[frame]
	if bar and bar.GetMinMaxValues then
		local _, max = bar:GetMinMaxValues()
		return tonumber(max or 0)
	end
	return nil
end

function lib:GetHealth(frame)
	local frame = self.realPlate[frame] or frame

	local bar = self.health_bar[frame]
	if bar and bar.GetValue then
		return bar:GetValue()
	end
	return nil
end

function lib:GetRaidIcon(frame)
	local frame = self.realPlate[frame] or frame

	local region = self.raidicon_region[frame]
	if region and region.IsShown and region:IsShown() and region.GetTexCoord then
		local ULx, ULy = region:GetTexCoord()

		if ULx and ULy then
			return raidIconTexCoord[ULx] and raidIconTexCoord[ULx][ULy] or 0
		end
	end

	return nil
end

function lib:IsMouseover(frame)
	local frame = self.realPlate[frame] or frame

	local region = self.hightlight_region[frame]
	if region and region.IsShown then
		return region:IsShown() and true or false
	end

	return nil
end

function lib:IsCasting(frame)
	local frame = self.realPlate[frame] or frame

	local bar = self.cast_bar[frame]
	if bar and bar.IsShown then
		return bar:IsShown() and true or false
	end
	return nil
end

function lib:IsInCombat(frame)
	local frame = self.realPlate[frame] or frame

	local region = self.name_region[frame]
	if region and region.GetTextColor then
		return combatByColor(region:GetTextColor()) and true or false
	end

	return nil
end

function lib:IsMarked(frame)
	local frame = self.realPlate[frame] or frame

	local region = self.raidicon_region[frame]
	if region and region.IsShown then
		return region:IsShown() and true or false
	end

	return nil
end

function lib:GetGUID(frame)
	local frame = self.realPlate[frame] or frame
	return self.plateGUIDs[frame]
end

function lib:GetTargetNameplate()
	if self.targeted and self.targeted:IsShown() then
		return self.fakePlate[self.targeted] or self.targeted
	end
end

function lib:GetNameplateByGUID(GUID)
	if self.GUIDs[GUID] and self.GUIDs[GUID]:IsShown() then
		return self.fakePlate[self.GUIDs[GUID]] or self.GUIDs[GUID]
	end
end

function lib:GetNameplateByName(name, maxHp)
	local bar, barMax
	for frame in pairs(self.nameplates) do
		if frame:IsShown() then
			if name == lib:GetName(frame) then
				if not maxHp then
					return self.fakePlate[frame] or frame
				end
				bar = self.health_bar[frame]
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

function lib:GetNameplateByUnit(unitID)
	if UnitIsUnit(unitID, "target") then
		return self:GetTargetNameplate()
	end
	local GUID = UnitGUID(unitID)
	if self.GUIDs[GUID] and self.GUIDs[GUID]:IsShown() then
		return self.fakePlate[self.GUIDs[GUID]] or self.GUIDs[GUID]
	end

	local health = UnitHealth(unitID)
	local maxHealth = UnitHealthMax(unitID)
	local frame = self:GetNameplateByHealth(health, maxHealth)
	local name = UnitName(unitID)
	if frame then
		if name == lib:GetName(frame) then
			return self.fakePlate[frame] or frame
		end
	end

	return self:GetNameplateByName(name, maxHealth)
end

--Returns all known nameplates. Not just the one's visible.
function lib:GetAllNameplates()
	local frames = {}
	for frame in pairs(self.nameplates) do
		table_insert(frames, #frames + 1, self.fakePlate[frame] or frame)
	end
	return #frames, unpack(frames)
end

function lib:GetNameplateByHealth(current, max)
	local possibleFrames = {}
	local bar, barMax, barCurrent
	for frame in pairs(self.nameplates) do
		if frame:IsShown() then
			bar = self.health_bar[frame]

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
		return possibleFrames[1]
	end
	return nil
end

-- Testing changes to our OnUpdate hook function.
-- I'm trying to change the OnUpdate function based on which callbacks are registered. Right now it only checks Combat and Threat changed callbacks.
-- Hopfully this is coded right because any errors won't say which line is acting up.
local loadstring = loadstring
local setmetatable = setmetatable
local setfenv = setfenv

function lib.ModifyOnUpdate()
	local code = [[
		local frame, elapsed = ...
		]]

	code = code .. [[
		lib.isOnUpdating[frame] = true --to make sure our hooks don't break.
		if frame.lnpCheckForTarget then --Check on the first OnUpdate after the frame's shown.
			frame.lnpCheckForTarget = false
			if not lib.plateGUIDs[frame] and frame:IsShown() and ((frame:GetAlpha() == 1) and UnitExists("target")) then
				FoundPlateGUID(frame, UnitGUID("target"), "target")
			end
		end

		frame.lnpLastUpdate = (frame.lnpLastUpdate or 0) + elapsed
		if frame.lnpLastUpdate > updateDelay then
			UpdateNameplateInfo(frame)
			CheckForFakePlate(frame)
	]]

	--Only check for combatchange if callback is registered.
	if lib.callbacksRegistered["LibNameplates_CombatChange"] and #lib.callbacksRegistered["LibNameplates_CombatChange"] > 0 then
		code = code .. [[
			CheckCombatStatus(frame)
		]]
	end

	--Only check if threat changed if callback is registred.
	if lib.callbacksRegistered["LibNameplates_ThreatChange"] and #lib.callbacksRegistered["LibNameplates_ThreatChange"] > 0 then
		code = code .. [[
			CheckThreatStatus(frame)
			elseif frame.updateCountdown > 0 then
			--Threat doesn't get updated until the first OnUpdate. So OnShow sometimes sees the threat of the previous nameplate owner.
			--So I wait unit the 2nd OnUpdate to check threat status.
			frame.updateCountdown = frame.updateCountdown - 1
			if frame.updateCountdown == 0 then
				CheckThreatStatus(frame)
			end
		]]
	end
	code = code .. [[
		end
	]]
	--Close our if statement.

	local update = loadstring(code, "OnUpdateString")

	local smallenv = {
		--Create our environment so the script can access these functions/values.
		lib = lib,
		FoundPlateGUID = FoundPlateGUID,
		UpdateNameplateInfo = UpdateNameplateInfo,
		CheckForFakePlate = CheckForFakePlate,
		CheckCombatStatus = CheckCombatStatus,
		CheckThreatStatus = CheckThreatStatus,
		updateDelay = updateDelay
	}

	-- Our script is trying to access something not in our environment.
	setmetatable(smallenv, {
		__index = function(t, i)
			-- Create a upvalue in our environment.
			-- I hope this will give faster lookup times then making '__Index = _G' would.
			t[i] = _G[i]
			return t[i]
		end
	})

	setfenv(update, smallenv) --Set our update function to use our environment.

	lib.OnNameplateUpdate = update
end