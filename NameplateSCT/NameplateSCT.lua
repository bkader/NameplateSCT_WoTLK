---------------
-- LIBRARIES --
---------------

local NameplateSCT = LibStub("AceAddon-3.0"):NewAddon("NameplateSCT", "AceConsole-3.0", "AceEvent-3.0")
NameplateSCT.frame = CreateFrame("Frame", nil, UIParent)

local L = LibStub("AceLocale-3.0"):GetLocale("NameplateSCT")
local LibEasing = LibStub("LibEasing-1.0")
local SharedMedia = LibStub("LibSharedMedia-3.0")
local LibNameplates = LibStub("LibNameplates-1.0")

-------------
-- GLOBALS --
-------------
local CreateFrame = CreateFrame
local math_floor, math_pow, math_random = math.floor, math.pow, math.random
local tostring, tonumber, band = tostring, tonumber, bit.band
local format, find = string.format, string.find
local next, pairs, ipairs = next, pairs, ipairs
local tinsert, tremove = table.insert, table.remove

------------
-- LOCALS --
------------
local _
local animating = {}

local playerGUID

local function rgbToHex(r, g, b)
	return format("%02x%02x%02x", math_floor(255 * r), math_floor(255 * g), math_floor(255 * b))
end

local function hexToRGB(hex)
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1
end

local animationValues = {
	["verticalUp"] = L["Vertical Up"],
	["verticalDown"] = L["Vertical Down"],
	["fountain"] = L["Fountain"],
	["rainfall"] = L["Rainfall"],
	["disabled"] = L["Disabled"]
}

local fontFlags = {
	[""] = L["None"],
	["OUTLINE"] = L["Outline"],
	["THICKOUTLINE"] = L["Thick Outline"],
	["nil, MONOCHROME"] = L["Monochrome"],
	["OUTLINE , MONOCHROME"] = L["Monochrome Outline"],
	["THICKOUTLINE , MONOCHROME"] = L["Monochrome Thick Outline"]
}

local stratas = {
	["BACKGROUND"] = L["Background"],
	["LOW"] = L["Low"],
	["MEDIUM"] = L["Medium"],
	["HIGH"] = L["High"],
	["DIALOG"] = L["Dialog"],
	["TOOLTIP"] = L["Tooltip"]
}

local positionValues = {
	["TOP"] = L["Top"],
	["RIGHT"] = L["Right"],
	["BOTTOM"] = L["Bottom"],
	["LEFT"] = L["Left"],
	["TOPRIGHT"] = L["Top Right"],
	["TOPLEFT"] = L["Top Left"],
	["BOTTOMRIGHT"] = L["Bottom Right"],
	["BOTTOMLEFT"] = L["Bottom Left"],
	["CENTER"] = L["Center"]
}

local inversePositions = {
	["BOTTOM"] = "TOP",
	["LEFT"] = "RIGHT",
	["TOP"] = "BOTTOM",
	["RIGHT"] = "LEFT",
	["TOPLEFT"] = "BOTTOMRIGHT",
	["TOPRIGHT"] = "BOTTOMLEFT",
	["BOTTOMLEFT"] = "TOPRIGHT",
	["BOTTOMRIGHT"] = "TOPLEFT",
	["CENTER"] = "CENTER"
}

--------
-- DB --
--------

local defaultFont = SharedMedia:IsValid("font", "Bazooka") and "Bazooka" or "Friz Quadrata TT"

local defaults = {
	global = {
		enabled = true,
		xOffset = 0,
		yOffset = 0,
		heals = false,
		personalOnly = false,
		xOffsetPersonal = 0,
		yOffsetPersonal = -100,
		modOffTargetStrata = false,
		strata = {
			target = "HIGH",
			offTarget = "MEDIUM"
		},
		font = defaultFont,
		fontFlag = "OUTLINE",
		fontShadow = false,
		damageColor = true,
		defaultColor = "ffff00",
		showIcon = true,
		iconScale = 1,
		iconPosition = "RIGHT",
		xOffsetIcon = 0,
		yOffsetIcon = 0,
		damageColorPersonal = false,
		defaultColorPersonal = "ff0000",
		truncate = true,
		truncateLetter = true,
		commaSeperate = true,
		sizing = {
			crits = true,
			critsScale = 1.5,
			miss = false,
			missScale = 1.5,
			smallHits = true,
			smallHitsScale = 0.66,
			smallHitsHide = false,
			autoattackcritsizing = true
		},
		animations = {
			ability = "fountain",
			crit = "verticalUp",
			miss = "verticalUp",
			autoattack = "fountain",
			autoattackcrit = "verticalUp",
			animationspeed = 1
		},
		animationsPersonal = {
			normal = "rainfall",
			crit = "verticalUp",
			miss = "verticalUp"
		},
		formatting = {
			size = 20,
			alpha = 1
		},
		useOffTarget = true,
		offTargetFormatting = {
			size = 15,
			alpha = 0.5
		}
	}
}

---------------------
-- LOCAL CONSTANTS --
---------------------

local SMALL_HIT_EXPIRY_WINDOW = 30
local SMALL_HIT_MULTIPIER = 0.5

local ANIMATION_VERTICAL_DISTANCE = 75

local ANIMATION_ARC_X_MIN = 50
local ANIMATION_ARC_X_MAX = 150
local ANIMATION_ARC_Y_TOP_MIN = 10
local ANIMATION_ARC_Y_TOP_MAX = 50
local ANIMATION_ARC_Y_BOTTOM_MIN = 10
local ANIMATION_ARC_Y_BOTTOM_MAX = 50

local ANIMATION_RAINFALL_X_MAX = 75
local ANIMATION_RAINFALL_Y_MIN = 50
local ANIMATION_RAINFALL_Y_MAX = 100
local ANIMATION_RAINFALL_Y_START_MIN = 5
local ANIMATION_RAINFALL_Y_START_MAX = 15

local AutoAttack = GetSpellInfo(6603)
local AutoShot = GetSpellInfo(75)
local DAMAGE_TYPE_COLORS = {
	[SCHOOL_MASK_PHYSICAL] = "FFFF00",
	[SCHOOL_MASK_HOLY] = "FFE680",
	[SCHOOL_MASK_FIRE] = "FF8000",
	[SCHOOL_MASK_NATURE] = "4DFF4D",
	[SCHOOL_MASK_FROST] = "80FFFF",
	[SCHOOL_MASK_FROST + SCHOOL_MASK_FIRE] = "FF80FF",
	[SCHOOL_MASK_SHADOW] = "8080FF",
	[SCHOOL_MASK_ARCANE] = "FF80FF",
	[AutoAttack] = "FFFFFF",
	[AutoShot] = "FFFFFF",
	["pet"] = "CC8400"
}

local MISS_EVENT_STRINGS = {
	["ABSORB"] = ACTION_SPELL_MISSED_ABSORB,
	["BLOCK"] = ACTION_SPELL_MISSED_BLOCK,
	["DEFLECT"] = ACTION_SPELL_MISSED_DEFLECT,
	["DODGE"] = ACTION_SPELL_MISSED_DODGE,
	["EVADE"] = ACTION_SPELL_MISSED_EVADE,
	["IMMUNE"] = ACTION_SPELL_MISSED_IMMUNE,
	["MISS"] = ACTION_SPELL_MISSED_MISS,
	["PARRY"] = ACTION_SPELL_MISSED_PARRY,
	["REFLECT"] = L["Reflected"],
	["RESIST"] = L["Resisted"]
}

local STRATAS = {
	"BACKGROUND",
	"LOW",
	"MEDIUM",
	"HIGH",
	"DIALOG",
	"TOOLTIP"
}

----------------
-- FONTSTRING --
----------------
local function getFontPath(fontName)
	local fontPath = SharedMedia:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
	return fontPath
end

local fontStringCache = {}
local frameCounter = 0
local function getFontString()
	local fontString, fontStringFrame

	if next(fontStringCache) then
		fontString = tremove(fontStringCache)
	else
		frameCounter = frameCounter + 1
		fontStringFrame = CreateFrame("Frame", nil, UIParent)
		fontStringFrame:SetFrameStrata(NameplateSCT.db.global.strata.target)
		fontStringFrame:SetFrameLevel(frameCounter)
		fontString = fontStringFrame:CreateFontString()
		fontString:SetParent(fontStringFrame)
	end

	fontString:SetFont(getFontPath(NameplateSCT.db.global.font), 15, NameplateSCT.db.global.fontFlag)
	if NameplateSCT.db.global.textShadow then
		fontString:SetShadowOffset(1, -1)
	else
		fontString:SetShadowOffset(0, 0)
	end
	fontString:SetAlpha(1)
	fontString:SetDrawLayer("BACKGROUND")
	fontString:SetText("")
	fontString:Show()

	if NameplateSCT.db.global.showIcon then
		if not fontString.icon then
			fontString.icon = NameplateSCT.frame:CreateTexture(nil, "BACKGROUND")
			fontString.icon:SetTexCoord(0.062, 0.938, 0.062, 0.938)
		end
		fontString.icon:SetAlpha(1)
		fontString.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		fontString.icon:Hide()

		if fontString.icon.button then
			fontString.icon.button:Show()
		end
	end
	return fontString
end

local function recycleFontString(fontString)
	fontString:SetAlpha(0)
	fontString:Hide()

	animating[fontString] = nil

	fontString.distance = nil
	fontString.arcTop = nil
	fontString.arcBottom = nil
	fontString.arcXDist = nil
	fontString.deflection = nil
	fontString.numShakes = nil
	fontString.animation = nil
	fontString.animatingDuration = nil
	fontString.animatingStartTime = nil
	fontString.anchorFrame = nil

	fontString.guid = nil

	fontString.pow = nil
	fontString.startHeight = nil
	fontString.NSCTFontSize = nil

	if fontString.icon then
		fontString.icon:ClearAllPoints()
		fontString.icon:SetAlpha(0)
		fontString.icon:Hide()
		if fontString.icon.button then
			fontString.icon.button:Hide()
			fontString.icon.button:ClearAllPoints()
		end

		fontString.icon.anchorFrame = nil
		fontString.icon.guid = nil
	end

	fontString:SetFont(getFontPath(NameplateSCT.db.global.font), 15, NameplateSCT.db.global.fontFlag)
	if NameplateSCT.db.global.textShadow then
		fontString:SetShadowOffset(1, -1)
	else
		fontString:SetShadowOffset(0, 0)
	end
	fontString:ClearAllPoints()

	tinsert(fontStringCache, fontString)
end

----------------
-- NAMEPLATES --
----------------

local function adjustStrata()
	if NameplateSCT.db.global.modOffTargetStrata then
		return
	end

	if NameplateSCT.db.global.strata.target == "BACKGROUND" then
		NameplateSCT.db.global.strata.offTarget = "BACKGROUND"
		return
	end

	local offStrata
	for k, v in ipairs(STRATAS) do
		if (v == NameplateSCT.db.global.strata.target) then
			offStrata = STRATAS[k - 1]
		end
	end
	NameplateSCT.db.global.strata.offTarget = offStrata
end

----------
-- CORE --
----------
function NameplateSCT:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("NameplateSCTDB", defaults, true)
	self:RegisterChatCommand("nsct", "OpenMenu")
	self:RegisterMenu()
	if self.db.global.enabled == false then
		self:Disable()
	end
end

function NameplateSCT:OnEnable()
	playerGUID = UnitGUID("player")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self.db.global.enabled = true
	AutoAttack = AutoAttack or GetSpellInfo(6603)
	AutoShot = AutoShot or GetSpellInfo(75)
end

function NameplateSCT:OnDisable()
	self:UnregisterAllEvents()
	for fontString, _ in pairs(animating) do
		recycleFontString(fontString)
	end
	self.db.global.enabled = false
end

---------------
-- ANIMATION --
---------------
local function verticalPath(elapsed, duration, distance)
	return 0, LibEasing.InQuad(elapsed, 0, distance, duration)
end

local function arcPath(elapsed, duration, xDist, yStart, yTop, yBottom)
	local x, y
	local progress = elapsed / duration

	x = progress * xDist

	local a = -2 * yStart + 4 * yTop - 2 * yBottom
	local b = -3 * yStart + 4 * yTop - yBottom

	y = -a * math_pow(progress, 2) + b * progress + yStart

	return x, y
end

local function powSizing(elapsed, duration, start, middle, finish)
	local size = finish
	if elapsed < duration then
		if elapsed / duration < 0.5 then
			size = LibEasing.OutQuint(elapsed, start, middle - start, duration / 2)
		else
			size = LibEasing.InQuint(elapsed - elapsed / 2, middle, finish - middle, duration / 2)
		end
	end
	return size
end

local function AnimationOnUpdate()
	if next(animating) then
		for fontString, _ in pairs(animating) do
			local elapsed = GetTime() - fontString.animatingStartTime
			if elapsed > fontString.animatingDuration then
				recycleFontString(fontString)
			else
				local isTarget = false
				if fontString.guid then
					isTarget = (UnitGUID("target") == fontString.guid)
				else
					fontString.guid = playerGUID
				end

				local frame = fontString:GetParent()
				local currentStrata = frame:GetFrameStrata()
				local strataRequired = isTarget and NameplateSCT.db.global.strata.target or NameplateSCT.db.global.strata.offTarget
				if currentStrata ~= strataRequired then
					frame:SetFrameStrata(strataRequired)
				end

				local startAlpha = NameplateSCT.db.global.formatting.alpha
				if NameplateSCT.db.global.useOffTarget and not isTarget and fontString.guid ~= playerGUID then
					startAlpha = NameplateSCT.db.global.offTargetFormatting.alpha
				end

				local alpha = LibEasing.InExpo(elapsed, startAlpha, -startAlpha, fontString.animatingDuration)
				fontString:SetAlpha(alpha)

				if fontString.pow then
					local iconScale = NameplateSCT.db.global.iconScale
					local height = fontString.startHeight
					if elapsed < fontString.animatingDuration / 6 then
						fontString:SetText(fontString.NSCTText)

						local size = powSizing(elapsed, fontString.animatingDuration / 6, height / 2, height * 2, height)
						fontString:SetTextHeight(size)
					else
						fontString.pow = nil
						fontString:SetTextHeight(height)
						fontString:SetFont(getFontPath(NameplateSCT.db.global.font), fontString.NSCTFontSize, NameplateSCT.db.global.fontFlag)
						if NameplateSCT.db.global.textShadow then
							fontString:SetShadowOffset(1, -1)
						else
							fontString:SetShadowOffset(0, 0)
						end
						fontString:SetText(fontString.NSCTText)
					end
				end

				local xOffset, yOffset = 0, 0
				if fontString.animation == "verticalUp" then
					xOffset, yOffset = verticalPath(elapsed, fontString.animatingDuration, fontString.distance)
				elseif fontString.animation == "verticalDown" then
					xOffset, yOffset = verticalPath(elapsed, fontString.animatingDuration, -fontString.distance)
				elseif fontString.animation == "fountain" then
					xOffset, yOffset = arcPath(elapsed, fontString.animatingDuration, fontString.arcXDist, 0, fontString.arcTop, fontString.arcBottom)
				elseif fontString.animation == "rainfall" then
					_, yOffset = verticalPath(elapsed, fontString.animatingDuration, -fontString.distance)
					xOffset = fontString.rainfallX
					yOffset = yOffset + fontString.rainfallStartY
				end

				if fontString.anchorFrame and fontString.anchorFrame:IsShown() then
					if fontString.guid == playerGUID then -- player frame
						fontString:SetPoint("CENTER", fontString.anchorFrame, "CENTER", NameplateSCT.db.global.xOffsetPersonal + xOffset, NameplateSCT.db.global.yOffsetPersonal + yOffset)
					else
						fontString:SetPoint("CENTER", fontString.anchorFrame, "CENTER", NameplateSCT.db.global.xOffset + xOffset, NameplateSCT.db.global.yOffset + yOffset)
					end
				else
					recycleFontString(fontString)
				end
			end
		end
	else
		NameplateSCT.frame:SetScript("OnUpdate", nil)
	end
end

local arcDirection = 1
function NameplateSCT:Animate(fontString, anchorFrame, duration, animation)
	animation = animation or "verticalUp"

	fontString.animation = animation
	fontString.animatingDuration = duration
	fontString.animatingStartTime = GetTime()
	fontString.anchorFrame = anchorFrame == "player" and UIParent or anchorFrame

	if animation == "verticalUp" then
		fontString.distance = ANIMATION_VERTICAL_DISTANCE
	elseif animation == "verticalDown" then
		fontString.distance = ANIMATION_VERTICAL_DISTANCE
	elseif animation == "fountain" then
		fontString.arcTop = math_random(ANIMATION_ARC_Y_TOP_MIN, ANIMATION_ARC_Y_TOP_MAX)
		fontString.arcBottom = -math_random(ANIMATION_ARC_Y_BOTTOM_MIN, ANIMATION_ARC_Y_BOTTOM_MAX)
		fontString.arcXDist = arcDirection * math_random(ANIMATION_ARC_X_MIN, ANIMATION_ARC_X_MAX)

		arcDirection = arcDirection * -1
	elseif animation == "rainfall" then
		fontString.distance = math_random(ANIMATION_RAINFALL_Y_MIN, ANIMATION_RAINFALL_Y_MAX)
		fontString.rainfallX = math_random(-ANIMATION_RAINFALL_X_MAX, ANIMATION_RAINFALL_X_MAX)
		fontString.rainfallStartY = -math_random(ANIMATION_RAINFALL_Y_START_MIN, ANIMATION_RAINFALL_Y_START_MAX)
	end

	animating[fontString] = true

	-- start onupdate if it's not already running
	if NameplateSCT.frame:GetScript("OnUpdate") == nil then
		NameplateSCT.frame:SetScript("OnUpdate", AnimationOnUpdate)
	end
end

------------
-- EVENTS --
------------

local damageSpellEvents = {
	DAMAGE_SHIELD = true,
	SPELL_DAMAGE = true,
	SPELL_PERIODIC_DAMAGE = true,
	SPELL_BUILDING_DAMAGE = true,
	RANGE_DAMAGE = true
}

local missedSpellEvents = {
	SPELL_MISSED = true,
	SPELL_PERIODIC_MISSED = true,
	RANGE_MISSED = true,
	SPELL_BUILDING_MISSED = true
}

local healSpellEvents = {
	SPELL_HEAL = true,
	SPELL_PERIODIC_HEAL = true
}

local COMBATLOG_OBJECT_TYPE_PET = COMBATLOG_OBJECT_TYPE_PET or 0x00001000
local COMBATLOG_OBJECT_TYPE_GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x00002000
local BITMASK_PETS = COMBATLOG_OBJECT_TYPE_PET + COMBATLOG_OBJECT_TYPE_GUARDIAN
local BITMASK_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001

function NameplateSCT:COMBAT_LOG_EVENT_UNFILTERED(_, _, clueevent, srcGUID, srcName, srcFlags, dstGUID, dstName, _, ...)
	if self.db.global.personalOnly and self.db.global.personal and playerGUID ~= dstGUID then
		return
	end -- Cancel out any non player targetted abilities if you have personalSCT only enabled

	if playerGUID == srcGUID or (self.db.global.personal and playerGUID == dstGUID) then -- Player events
		if damageSpellEvents[clueevent] or (healSpellEvents[clueevent] and self.db.global.heals) then
			local spellId, spellName, school, amount, _, _, _, _, _, critical, _, _ = ...
			self:DamageEvent(dstGUID, spellName, amount, school, critical, spellId, healSpellEvents[clueevent] and self.db.global.heals)
		elseif clueevent == "SWING_DAMAGE" then
			local amount, _, _, _, _, _, critical, _, _ = ...
			self:DamageEvent(dstGUID, AutoAttack, amount, 1, critical, 6603)
		elseif missedSpellEvents[clueevent] then
			local spellId, spellName, school, missType = ...
			self:MissEvent(dstGUID, spellName, missType, spellId)
		elseif clueevent == "SWING_MISSED" then
			self:MissEvent(dstGUID, AutoAttack, dstGUID == playerGUID and AutoAttack or ..., 6603)
		end
	elseif band(srcFlags, BITMASK_PETS) ~= 0 and band(srcFlags, BITMASK_MINE) ~= 0 then -- Pet/Guardian events
		if damageSpellEvents[clueevent] or (healSpellEvents[clueevent] and self.db.global.heals) then
			local spellId, spellName, _, amount, _, _, _, _, _, critical, _, _ = ...
			self:DamageEvent(dstGUID, spellName, amount, "pet", critical, spellId, healSpellEvents[clueevent] and self.db.global.heals)
		elseif clueevent == "SWING_DAMAGE" then
			local amount, _, _, _, _, _, critical, _, _ = ...
			self:DamageEvent(dstGUID, AutoAttack, amount, "pet", critical, 6603)
		end
	end
end

-------------
-- DISPLAY --
-------------
local function commaSeperate(number)
	local _, _, minus, int, fraction = tostring(number):find("([-]?)(%d+)([.]?%d*)")
	int = int:reverse():gsub("(%d%d%d)", "%1,")
	return minus .. int:reverse():gsub("^,", "") .. fraction
end

local numDamageEvents = 0
local lastDamageEventTime
local runningAverageDamageEvents = 0
function NameplateSCT:DamageEvent(guid, spellName, amount, school, crit, spellId, heals)
	local text, animation, pow, size, alpha
	local autoattack = spellName == AutoAttack or spellName == AutoShot or spellName == "pet"

	-- select an animation
	if (autoattack and crit) then
		animation = guid ~= playerGUID and self.db.global.animations.autoattackcrit or self.db.global.animationsPersonal.crit
		pow = true
	elseif (autoattack) then
		animation = guid ~= playerGUID and self.db.global.animations.autoattack or self.db.global.animationsPersonal.normal
		pow = false
	elseif (crit) then
		animation = guid ~= playerGUID and self.db.global.animations.crit or self.db.global.animationsPersonal.crit
		pow = true
	elseif (not autoattack and not crit) then
		animation = guid ~= playerGUID and self.db.global.animations.ability or self.db.global.animationsPersonal.normal
		pow = false
	end

	-- skip if this damage event is disabled
	if (animation == "disabled") then return end

	local isTarget = (UnitGUID("target") == guid)

	if (self.db.global.useOffTarget and not isTarget and playerGUID ~= guid) then
		size = self.db.global.offTargetFormatting.size
		alpha = self.db.global.offTargetFormatting.alpha
	else
		size = self.db.global.formatting.size
		alpha = self.db.global.formatting.alpha
	end

	-- truncate
	if (self.db.global.truncate and amount >= 1000000 and self.db.global.truncateLetter) then
		text = format("%.1fM", amount / 1000000)
	elseif (self.db.global.truncate and amount >= 10000) then
		text = format("%.0f", amount / 1000)

		if (self.db.global.truncateLetter) then
			text = text .. "k"
		end
	elseif (self.db.global.truncate and amount >= 1000) then
		text = format("%.1f", amount / 1000)

		if (self.db.global.truncateLetter) then
			text = text .. "k"
		end
	else
		if (self.db.global.commaSeperate) then
			text = commaSeperate(amount)
		else
			text = tostring(amount)
		end
	end

	-- color text
	if guid ~= playerGUID then
		if self.db.global.damageColor and (spellName == AutoAttack or spellName == AutoShot) and DAMAGE_TYPE_COLORS[spellName] then
			text = "\124cff" .. DAMAGE_TYPE_COLORS[spellName] .. text .. "\124r"
		elseif self.db.global.damageColor and school and DAMAGE_TYPE_COLORS[school] then
			text = "\124cff" .. DAMAGE_TYPE_COLORS[school] .. text .. "\124r"
		else
			text = "\124cff" .. self.db.global.defaultColor .. text .. "\124r"
		end
	else
		if self.db.global.damageColorPersonal and school and DAMAGE_TYPE_COLORS[school] then
			text = "\124cff" .. DAMAGE_TYPE_COLORS[school] .. text .. "\124r"
		elseif self.db.global.damageColorPersonal and spellName == AutoAttack and DAMAGE_TYPE_COLORS[spellName] then
			text = "\124cff" .. DAMAGE_TYPE_COLORS[spellName] .. text .. "\124r"
		elseif heals and not self.db.global.damageColorPersonal then
			text = "\124cff4dff4d" .. text .. "\124r"
		else
			text = "\124cff" .. self.db.global.defaultColorPersonal .. text .. "\124r"
		end
	end

	-- shrink small hits
	if (self.db.global.sizing.smallHits or self.db.global.sizing.smallHitsHide) and playerGUID ~= guid then
		if (not lastDamageEventTime or (lastDamageEventTime + SMALL_HIT_EXPIRY_WINDOW < GetTime())) then
			numDamageEvents = 0
			runningAverageDamageEvents = 0
		end

		runningAverageDamageEvents = ((runningAverageDamageEvents * numDamageEvents) + amount) / (numDamageEvents + 1)
		numDamageEvents = numDamageEvents + 1
		lastDamageEventTime = GetTime()

		if ((not crit and amount < SMALL_HIT_MULTIPIER * runningAverageDamageEvents) or (crit and amount / 2 < SMALL_HIT_MULTIPIER * runningAverageDamageEvents)) then
			if (self.db.global.sizing.smallHitsHide) then
				-- skip this damage event, it's too small
				return
			else
				size = size * self.db.global.sizing.smallHitsScale
			end
		end
	end

	-- embiggen crit's size
	if (self.db.global.sizing.crits and crit) and playerGUID ~= guid then
		if (autoattack and not self.db.global.sizing.autoattackcritsizing) then
			-- don't embiggen autoattacks
			pow = false
		else
			size = size * self.db.global.sizing.critsScale
		end
	end

	-- make sure that size is larger than 5
	if (size < 5) then
		size = 5
	end
	self:DisplayText(guid, text, size, alpha, animation, spellId, pow, spellName)
end

function NameplateSCT:MissEvent(guid, spellName, missType, spellId)
	local text, animation, pow, size, alpha, color
	local isTarget = (UnitGUID("target") == guid)

	if playerGUID ~= guid then
		animation = self.db.global.animations.miss
		color = self.db.global.defaultColor
	else
		animation = self.db.global.animationsPersonal.miss
		color = self.db.global.defaultColorPersonal
	end

	-- No animation set, cancel out
	if (animation == "disabled") then
		return
	end

	if (self.db.global.useOffTarget and not isTarget and playerGUID ~= guid) then
		size = self.db.global.offTargetFormatting.size
		alpha = self.db.global.offTargetFormatting.alpha
	else
		size = self.db.global.formatting.size
		alpha = self.db.global.formatting.alpha
	end

	-- embiggen miss size
	if self.db.global.sizing.miss and playerGUID ~= guid then
		size = size * self.db.global.sizing.missScale
	end

	pow = true

	text = MISS_EVENT_STRINGS[missType] or ACTION_SPELL_MISSED_MISS
	text = "\124cff" .. color .. text .. "\124r"

	self:DisplayText(guid, text, size, alpha, animation, spellId, pow, spellName)
end

function NameplateSCT:GetNameplate(guid)
	local plate = (guid == playerGUID) and "player" or nil
	if not plate and UnitExists("target") and not UnitIsUnit("target", "player") and UnitGUID("target") == guid then
		plate = LibNameplates:GetTargetNameplate()
	end
	return plate or LibNameplates:GetNameplateByGUID(guid)
end

function NameplateSCT:DisplayText(guid, text, size, alpha, animation, spellId, pow, spellName)
	local fontString, icon

	local nameplate = self:GetNameplate(guid)
	if not nameplate then return end

	fontString = getFontString()

	fontString.NSCTText = text
	fontString:SetText(fontString.NSCTText)

	fontString.NSCTFontSize = size
	fontString:SetFont(getFontPath(self.db.global.font), fontString.NSCTFontSize, self.db.global.fontFlag)
	if self.db.global.textShadow then
		fontString:SetShadowOffset(1, -1)
	else
		fontString:SetShadowOffset(0, 0)
	end
	fontString.startHeight = fontString:GetStringHeight()
	fontString.pow = pow

	if (fontString.startHeight <= 0) then
		fontString.startHeight = 5
	end

	fontString.guid = guid

	local _, _, texture = GetSpellInfo(spellId or spellName)
	if not texture and spellName then
		_, _, texture = GetSpellInfo(spellName)
	end

	if self.db.global.showIcon and texture then
		icon = fontString.icon
		icon:Show()
		icon:SetTexture(texture)
		icon:SetSize(size * self.db.global.iconScale, size * self.db.global.iconScale)
		icon:SetPoint(inversePositions[self.db.global.iconPosition], fontString, self.db.global.iconPosition, self.db.global.xOffsetIcon, self.db.global.yOffsetIcon)
		icon:SetAlpha(alpha)
		fontString.icon = icon
	elseif fontString.icon then
		fontString.icon:Hide()
	end
	self:Animate(fontString, nameplate, self.db.global.animations.animationspeed, animation)
end

-------------
-- OPTIONS --
-------------

local addonDisabled = function()
	return not NameplateSCT.db.global.enabled
end

local menu = {
	name = "NameplateSCT \124c00ffffffBackported\124r by \124cfff58cbaKader\124r",
	handler = NameplateSCT,
	type = "group",
	get = function(i)
		return NameplateSCT.db.global[i[#i]]
	end,
	set = function(i, val)
		NameplateSCT.db.global[i[#i]] = val
	end,
	args = {
		nameplatesEnabled = {
			type = "description",
			name = "\124cFFFF0000" .. L["YOUR ENEMY NAMEPLATES ARE DISABLED, NAMEPLATESCT WILL NOT WORK!!"] .. "\124r",
			hidden = function()
				return GetCVar("nameplateShowEnemies") == "1"
			end,
			order = 1,
			width = "double"
		},
		enable = {
			type = "toggle",
			name = L["Enable"],
			desc = L["If the addon is enabled."],
			get = "IsEnabled",
			set = function(_, val)
				if val then
					NameplateSCT:Enable()
				else
					NameplateSCT:Disable()
				end
			end,
			order = 2
		},
		heals = {
			type = "toggle",
			name = L["Include Heals"],
			desc = L["Also show numbers when you heal"],
			order = 3
		},
		personal = {
			type = "toggle",
			name = L["Personal SCT"],
			desc = L["Also show numbers when you take damage on your personal nameplate or center screen"],
			disabled = addonDisabled,
			order = 6
		},
		personalOnly = {
			type = "toggle",
			name = L["Personal SCT Only"],
			desc = L["Don't display any numbers on enemies and only use the personal SCT."],
			disabled = function()
				return (not NameplateSCT.db.global.personal or not NameplateSCT.db.global.enabled)
			end,
			order = 7
		},
		animations = {
			type = "group",
			name = L["Animations"],
			order = 30,
			inline = true,
			disabled = addonDisabled,
			get = function(i)
				return NameplateSCT.db.global.animations[i[#i]]
			end,
			set = function(i, val)
				NameplateSCT.db.global.animations[i[#i]] = val
			end,
			args = {
				animationspeed = {
					type = "range",
					name = L["Animation Speed"],
					desc = L["Default speed: 1"],
					min = 0.5,
					max = 2,
					step = .1,
					order = 1,
					width = "double"
				},
				ability = {
					type = "select",
					name = L["Abilities"],
					values = animationValues,
					order = 2
				},
				crit = {
					type = "select",
					name = L["Criticals"],
					values = animationValues,
					order = 3
				},
				miss = {
					type = "select",
					name = L["Miss/Parry/Dodge/etc"],
					values = animationValues,
					order = 4
				},
				autoattack = {
					type = "select",
					name = L["Auto Attacks"],
					values = animationValues,
					order = 5
				},
				autoattackcrit = {
					type = "select",
					name = L["Criticals"],
					desc = L["Auto attacks that are critical hits"],
					values = animationValues,
					order = 6
				},
				autoattackcritsizing = {
					type = "toggle",
					name = L["Embiggen Crits"],
					desc = L["Embiggen critical auto attacks"],
					order = 7
				}
			}
		},
		appearance = {
			type = "group",
			name = L["Appearance/Offsets"],
			order = 50,
			inline = true,
			disabled = addonDisabled,
			args = {
				font = {
					type = "select",
					dialogControl = "LSM30_Font",
					name = L["Font"],
					values = AceGUIWidgetLSMlists.font,
					order = 1
				},
				fontFlag = {
					type = "select",
					name = L["Font Flags"],
					values = fontFlags,
					order = 2
				},
				textShadow = {
					type = "toggle",
					name = L["Text Shadow"],
					order = 3
				},
				damageColor = {
					type = "toggle",
					name = L["Use Damage Type Color"],
					order = 4
				},
				defaultColor = {
					type = "color",
					name = L["Default Color"],
					disabled = function()
						return NameplateSCT.db.global.damageColor
					end,
					hasAlpha = false,
					set = function(_, r, g, b)
						NameplateSCT.db.global.defaultColor = rgbToHex(r, g, b)
					end,
					get = function()
						return hexToRGB(NameplateSCT.db.global.defaultColor)
					end,
					order = 5
				},
				xOffset = {
					type = "range",
					name = L["X Offset"],
					desc = L["Has soft max/min, you can type whatever you'd like into the editbox"],
					softMin = -75,
					softMax = 75,
					step = 1,
					order = 10,
					width = "double"
				},
				yOffset = {
					type = "range",
					name = L["Y Offset"],
					desc = L["Has soft max/min, you can type whatever you'd like into the editbox"],
					softMin = -75,
					softMax = 75,
					step = 1,
					order = 11,
					width = "double"
				},
				modOffTargetStrata = {
					type = "toggle",
					name = L["Use Separate Off-Target Strata"],
					order = 8
				},
				targetStrata = {
					type = "select",
					name = L["Target Strata"],
					get = function()
						return NameplateSCT.db.global.strata.target
					end,
					set = function(_, val)
						NameplateSCT.db.global.strata.target = val
						adjustStrata()
					end,
					values = stratas,
					order = 9
				},
				offTarget = {
					type = "select",
					name = L["Off-Target Strata"],
					disabled = function()
						return not NameplateSCT.db.global.modOffTargetStrata
					end,
					get = function()
						return NameplateSCT.db.global.strata.offTarget
					end,
					set = function(_, val)
						NameplateSCT.db.global.strata.offTarget = val
					end,
					values = stratas,
					order = 10
				},
				iconAppearance = {
					type = "group",
					name = L["Icons"],
					order = 60,
					inline = true,
					args = {
						showIcon = {
							type = "toggle",
							name = L["Display Icon"],
							order = 1,
							width = "double"
						},
						iconScale = {
							type = "range",
							name = L["Icon Scale"],
							desc = L["Scale of the spell icon"],
							softMin = 0.5,
							softMax = 2,
							isPercent = true,
							step = 0.01,
							hidden = function()
								return not NameplateSCT.db.global.showIcon
							end,
							order = 3,
							width = "Half"
						},
						iconPosition = {
							type = "select",
							name = L["Position"],
							hidden = function()
								return not NameplateSCT.db.global.showIcon
							end,
							values = positionValues,
							order = 6
						},
						xOffsetIcon = {
							type = "range",
							name = L["Icon X Offset"],
							hidden = function()
								return not NameplateSCT.db.global.showIcon
							end,
							softMin = -30,
							softMax = 30,
							step = 1,
							order = 7,
							width = "Half"
						},
						yOffsetIcon = {
							type = "range",
							name = L["Icon Y Offset"],
							hidden = function()
								return not NameplateSCT.db.global.showIcon
							end,
							softMin = -30,
							softMax = 30,
							step = 1,
							order = 8,
							width = "Half"
						}
					}
				}
			}
		},
		animationsPersonal = {
			type = "group",
			name = L["Personal SCT Animations"],
			order = 60,
			inline = true,
			hidden = function()
				return not NameplateSCT.db.global.personal
			end,
			disabled = addonDisabled,
			args = {
				normalPersonal = {
					type = "select",
					name = L["Default"],
					get = function()
						return NameplateSCT.db.global.animationsPersonal.normal
					end,
					set = function(_, val)
						NameplateSCT.db.global.animationsPersonal.normal = val
					end,
					values = animationValues,
					order = 5
				},
				critPersonal = {
					type = "select",
					name = L["Criticals"],
					get = function()
						return NameplateSCT.db.global.animationsPersonal.crit
					end,
					set = function(_, val)
						NameplateSCT.db.global.animationsPersonal.crit = val
					end,
					values = animationValues,
					order = 10
				},
				missPersonal = {
					type = "select",
					name = L["Miss/Parry/Dodge/etc"],
					get = function()
						return NameplateSCT.db.global.animationsPersonal.miss
					end,
					set = function(_, val)
						NameplateSCT.db.global.animationsPersonal.miss = val
					end,
					values = animationValues,
					order = 15
				},
				damageColorPersonal = {
					type = "toggle",
					name = L["Use Damage Type Color"],
					order = 40
				},
				defaultColorPersonal = {
					type = "color",
					name = L["Default Color"],
					disabled = function()
						return NameplateSCT.db.global.damageColorPersonal
					end,
					hasAlpha = false,
					set = function(_, r, g, b)
						NameplateSCT.db.global.defaultColorPersonal = rgbToHex(r, g, b)
					end,
					get = function()
						return hexToRGB(NameplateSCT.db.global.defaultColorPersonal)
					end,
					order = 45
				},
				xOffsetPersonal = {
					type = "range",
					name = L["X Offset Personal SCT"],
					desc = L["Only used if Personal Nameplate is Disabled"],
					hidden = function()
						return not NameplateSCT.db.global.personal
					end,
					softMin = -400,
					softMax = 400,
					step = 1,
					order = 50,
					width = "double"
				},
				yOffsetPersonal = {
					type = "range",
					name = L["Y Offset Personal SCT"],
					desc = L["Only used if Personal Nameplate is Disabled"],
					hidden = function()
						return not NameplateSCT.db.global.personal
					end,
					softMin = -400,
					softMax = 400,
					step = 1,
					order = 60,
					width = "double"
				}
			}
		},
		formatting = {
			type = "group",
			name = L["Text Formatting"],
			order = 90,
			inline = true,
			disabled = addonDisabled,
			args = {
				truncate = {
					type = "toggle",
					name = L["Truncate Number"],
					order = 1
				},
				truncateLetter = {
					type = "toggle",
					name = L["Show Truncated Letter"],
					disabled = function()
						return not NameplateSCT.db.global.enabled or not NameplateSCT.db.global.truncate
					end,
					order = 2
				},
				commaSeperate = {
					type = "toggle",
					name = L["Comma Seperate"],
					desc = "100000 -> 100,000",
					disabled = function()
						return not NameplateSCT.db.global.enabled or NameplateSCT.db.global.truncate
					end,
					order = 3
				},
				size = {
					type = "range",
					name = L["Size"],
					min = 5,
					max = 72,
					step = 1,
					get = function()
						return NameplateSCT.db.global.formatting.size
					end,
					set = function(_, val)
						NameplateSCT.db.global.formatting.size = val
					end,
					order = 52
				},
				alpha = {
					type = "range",
					name = L["Alpha"],
					min = 0.1,
					max = 1,
					step = .01,
					get = function()
						return NameplateSCT.db.global.formatting.alpha
					end,
					set = function(_, val)
						NameplateSCT.db.global.formatting.alpha = val
					end,
					order = 53
				},
				useOffTarget = {
					type = "toggle",
					name = L["Use Seperate Off-Target Text Appearance"],
					order = 100,
					width = "double"
				},
				offTarget = {
					type = "group",
					name = L["Off-Target Text Appearance"],
					hidden = function()
						return not NameplateSCT.db.global.useOffTarget
					end,
					order = 101,
					inline = true,
					get = function(i)
						return NameplateSCT.db.global.offTargetFormatting[i[#i]]
					end,
					set = function(i, val)
						NameplateSCT.db.global.offTargetFormatting[i[#i]] = val
					end,
					args = {
						size = {
							type = "range",
							name = L["Size"],
							min = 5,
							max = 72,
							step = 1,
							order = 2
						},
						alpha = {
							type = "range",
							name = L["Alpha"],
							min = 0.1,
							max = 1,
							step = .01,
							order = 3
						}
					}
				}
			}
		},
		sizing = {
			type = "group",
			name = L["Sizing Modifiers"],
			order = 100,
			inline = true,
			disabled = function()
				return not NameplateSCT.db.global.enabled
			end,
			get = function(i)
				return NameplateSCT.db.global.sizing[i[#i]]
			end,
			set = function(i, val)
				NameplateSCT.db.global.sizing[i[#i]] = val
			end,
			args = {
				crits = {
					type = "toggle",
					name = L["Embiggen Crits"],
					order = 1
				},
				critsScale = {
					type = "range",
					name = L["Embiggen Crits Scale"],
					disabled = function()
						return not NameplateSCT.db.global.enabled or not NameplateSCT.db.global.sizing.crits
					end,
					min = 1,
					max = 3,
					step = .01,
					order = 2,
					width = "double"
				},
				miss = {
					type = "toggle",
					name = L["Embiggen Miss/Parry/Dodge/etc"],
					order = 10
				},
				missScale = {
					type = "range",
					name = L["Embiggen Miss/Parry/Dodge/etc Scale"],
					disabled = function()
						return not NameplateSCT.db.global.enabled or not NameplateSCT.db.global.sizing.miss
					end,
					min = 1,
					max = 3,
					step = .01,
					order = 11,
					width = "double"
				},
				smallHits = {
					type = "toggle",
					name = L["Scale Down Small Hits"],
					desc = L["Scale down hits that are below a running average of your recent damage output"],
					disabled = function()
						return not NameplateSCT.db.global.enabled or NameplateSCT.db.global.sizing.smallHitsHide
					end,
					order = 20
				},
				smallHitsScale = {
					type = "range",
					name = L["Small Hits Scale"],
					disabled = function()
						return not NameplateSCT.db.global.enabled or not NameplateSCT.db.global.sizing.smallHits or
							NameplateSCT.db.global.sizing.smallHitsHide
					end,
					min = 0.33,
					max = 1,
					step = .01,
					order = 21,
					width = "double"
				},
				smallHitsHide = {
					type = "toggle",
					name = L["Hide Small Hits"],
					desc = L["Hide hits that are below a running average of your recent damage output"],
					order = 22
				}
			}
		},
		about = {
			type = "group",
			name = "About",
			order = 110,
			inline = true,
			args = {
				date = {
					type = "description",
					name = format("|cffffff33Date|r: %s", GetAddOnMetadata("NameplateSCT", "X-Date")),
					width = "double",
					order = 0
				},
				website = {
					type = "description",
					name = format("|cffffff33Website|r: %s", GetAddOnMetadata("NameplateSCT", "X-Website")),
					width = "double",
					order = 10
				},
				discord = {
					type = "description",
					name = format("|cffffff33Discord|r: %s", GetAddOnMetadata("NameplateSCT", "X-Discord")),
					width = "double",
					order = 20
				},
				email = {
					type = "description",
					name = format("|cffffff33Email|r: %s", GetAddOnMetadata("NameplateSCT", "X-Email")),
					width = "double",
					order = 30
				},
				credits = {
					type = "description",
					name = format("|cffffff33Credits|r: %s", GetAddOnMetadata("NameplateSCT", "X-Credits")),
					width = "double",
					order = 40
				}
			}
		}
	}
}

function NameplateSCT:OpenMenu()
	-- just open to the frame, double call because blizz bug
	InterfaceOptionsFrame_OpenToCategory(self.menu)
	InterfaceOptionsFrame_OpenToCategory(self.menu)
end

function NameplateSCT:RegisterMenu()
	LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("NameplateSCT", menu)
	self.menu = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("NameplateSCT", "NameplateSCT")
end