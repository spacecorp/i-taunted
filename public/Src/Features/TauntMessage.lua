-- init
ITaunted.TauntMessage = {}
ITaunted.TauntMessage.massTauntLastCasted = GetTime();
ITaunted.TauntMessage.lastTaunt = { time = 0, target = nil }

-- Game version detection
-- WoW: Forever reports its own project id (WOW_PROJECT_CAMELOT, 18).
ITaunted.TauntMessage.isForever = (WOW_PROJECT_ID == (WOW_PROJECT_CAMELOT or 18))
-- Retail Midnight (12.0+) no longer delivers COMBAT_LOG_EVENT_UNFILTERED to addons,
-- so there we fall back to UNIT_SPELLCAST_SUCCEEDED for the player and pet.
ITaunted.TauntMessage.useUnitEvents = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
    and (select(4, GetBuildInfo()) >= 120000)

-- WoW: Forever paladin
local FOREVER_JUDGEMENT = 20271     -- Judgement
local FOREVER_SEAL_OF_FURY = 20163  -- Seal of Fury: Judgement taunts while this seal is active

local function isSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local function playerHasAura(auraSpellId)
    if (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return C_UnitAuras.GetPlayerAuraBySpellID(auraSpellId) ~= nil
    end

    if (UnitBuff) then
        for i = 1, 40 do
            local name, _, _, _, _, _, _, _, _, buffSpellId = UnitBuff("player", i)
            if (not name) then
                return false
            end
            if (buffSpellId == auraSpellId) then
                return true
            end
        end
    end

    return false
end

-- Returns start, duration, enabled for every client flavor (C_Spell on modern clients, global on old ones)
local function getSpellCooldown(spellId)
    if (C_Spell and C_Spell.GetSpellCooldown) then
        local info = C_Spell.GetSpellCooldown(spellId)
        if (not info) then
            return nil, nil, nil
        end
        return info.startTime, info.duration, info.isEnabled
    end

    if (GetSpellCooldown) then
        return GetSpellCooldown(spellId)
    end

    return nil, nil, nil
end

local function sendChatMessage(message)
    if (C_ChatInfo and C_ChatInfo.SendChatMessage) then
        pcall(C_ChatInfo.SendChatMessage, message)
    else
        pcall(SendChatMessage, message)
    end
end

local function dump(o)
    if type(o) == 'table' then
        local s = '{ ';
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ',';
        end
        return s .. '} ';
    else
        return tostring(o);
    end
end

function ITaunted.TauntMessage.GetIcon(
    destRaidFlags
)
    local icon = {
        [0] = "",
        [1] = "{rt1}",
        [2] = "{rt2}",
        [4] = "{rt3}",
        [8] = "{rt4}",
        [16] = "{rt5}",
        [32] = "{rt6}",
        [64] = "{rt7}",
        [128] = "{skull}"
    }
    local parsedIcon = icon[destRaidFlags]

    if (parsedIcon) then
        return parsedIcon
    end

    return ''
end

function ITaunted.TauntMessage.isMassTaunt(spellId)
    local massTauntSpells = {
        -- Warrior
        386071, --Disrupting Shout
        1161,   --Challenging Shout
        223591, -- Challening Shout #2
        46276,  --Ravager taunt

        -- Druid
        5209,   -- Challenging Roar (Classic / TBC / Wrath / Cata / MoP)

        -- Paladin
        204079, -- Final Stand
        204077, -- Final Stand #2,
        406984, -- Final Stand #3,
        278804, -- Final Stand #4,
        31790,  --Righteous Defense

        -- Monk
        116189, --Provoke, talented
        196727, -- Provoke #?

        -- Priest
        236003, --Visage of Terror

        -- Warlock pets
        43263, -- Ghoul Taunt

        -- Engineering
        82407, -- Painful Shock - caused when backfired engineering trinket goes off

        -- Unknown
        -- BEES!
        442054, -- Bees!
        176646, -- Nether Attraction
    }

    if ITaunted.Helpers.tableContainsValue(massTauntSpells, spellId) then
        return true
    end
    return false
end

-- Checks if the spell is one of the taunt spells in game
function ITaunted.TauntMessage.isTaunt(spellId)
    local tauntSpells = {
        --Warrior
        355,    --Taunt
        145058, --Taunt #2
        138937, -- Taunt #3
        172907, --Taunt #4
        55981,  -- Mammoth Trumpet
        12765,  -- improved taunt
        694,    -- Mocking Blow (Classic / TBC / Wrath / Cata / MoP)
        7400,   -- Mocking Blow rank 2
        7402,   -- Mocking Blow rank 3
        20559,  -- Mocking Blow rank 4
        20560,  -- Mocking Blow rank 5
        25266,  -- Mocking Blow rank 6 (TBC)

        --Death Knight
        51399,  --Death Grip for Blood (49576 is now just the pull effect)
        49576,  --Death Grip (the taunt itself in Wrath / Cata / MoP, and the cast that triggers 51399 on retail)
        56222,  --Dark Command
        222409, --Dark Command NPC

        --Paladin
        62124,  --Hand of Reckoning
        221710, -- Hand of Reckoning #2

        --Druid
        6795, --Growl

        --Hunter
        20736,  --Distracting Shot
        146771, --Distracting Shot #2
        -- Pets
        2649,   --Growl #1
        214413, --Growl #2
        39270,  --Growl #3
        14916,  --Growl rank 2 (Classic)
        14917,  --Growl rank 3
        14918,  --Growl rank 4
        14919,  --Growl rank 5
        14920,  --Growl rank 6
        14921,  --Growl rank 7
        27047,  --Growl rank 8 (TBC)
        61676,  --Growl rank 9 (Wrath)

        --Monk
        115546, --Provoke

        --Demon Hunter
        185245, --Torment

        -- Shaman
        204683, --Dark Whisper
        463161, -- Hand of Provocation
        460468, -- Hand of Provocation #2

        -- Warlock
        -- Pets
        17735,  --Suffering
        171014, -- Infernal, Seethe

        -- Engineering
        40224,  --Clintar agro pulse
        468371, -- Mark of the Hunted
    }

    if ITaunted.Helpers.tableContainsValue(tauntSpells, spellId) then
        return true
    end

    -- WoW: Forever: Paladin Judgement taunts while Seal of Fury is active.
    -- On every other client 20271 is a regular damage Judgement, so never count it there.
    if (ITaunted.TauntMessage.isForever and spellId == FOREVER_JUDGEMENT and playerHasAura(FOREVER_SEAL_OF_FURY)) then
        return true
    end

    return false
end

-- Some taunts fire more than one event for the same cast (e.g. Death Grip on retail),
-- so ignore a second "Taunted" message on the same target within a second.
function ITaunted.TauntMessage.isDuplicateTaunt(target, timeNow)
    local last = ITaunted.TauntMessage.lastTaunt
    local isDuplicate = (last.target == target and (timeNow - last.time) < 1)
    last.target = target
    last.time = timeNow
    return isDuplicate
end

function ITaunted.TauntMessage.GetIconForUnit(unit)
    local index = GetRaidTargetIndex and GetRaidTargetIndex(unit)
    if (index and not isSecret(index) and index >= 1 and index <= 8) then
        return "{rt" .. index .. "}"
    end
    return ""
end

-- Midnight (retail 12.0+): no combat log, so report successful casts from the player or pet.
function ITaunted.TauntMessage.handleUnitSpellcast(unit, spellId)
    if (isSecret(spellId)) then
        return
    end

    local timeNow = GetTime()
    local message = nil

    if (ITaunted.TauntMessage.isMassTaunt(spellId)) then
        if (ITaunted.TauntMessage.massTauntLastCasted + 10 < timeNow) then
            message = "Mass taunt"
            ITaunted.TauntMessage.massTauntLastCasted = timeNow
        end
    elseif (ITaunted.TauntMessage.isTaunt(spellId)) then
        local targetUnit = (unit == "pet") and "pettarget" or "target"
        local targetName = UnitName(targetUnit)

        if (targetName and not isSecret(targetName) and not ITaunted.TauntMessage.isDuplicateTaunt(targetName, timeNow)) then
            message = "Taunted " .. ITaunted.TauntMessage.GetIconForUnit(targetUnit) .. " " .. targetName
        end
    end

    if (message) then
        sendChatMessage(message)
    end
end

function ITaunted.TauntMessage.playerHasValidTarget()
    if (UnitName("target") and not UnitPlayerControlled("target")) then
        return true
    end
    return false
end

function ITaunted.TauntMessage.handleCombatLogEvent(...)
    local _, event, _, _, _, _, _, _, destName, _, destRaidFlags =
        select(1, ...)
    local message = nil
    local spellId, _, _ = select(12, ...)
    local start, duration, enabled = getSpellCooldown(spellId);

    if (start == nil or duration == nil or enabled == nil) then
        return;
    end

    local timeNow = GetTime()
    local canCastAgain = (start + duration - timeNow) < 0;


    if (ITaunted.TauntMessage.massTauntLastCasted + 10 < timeNow and canCastAgain and ITaunted.TauntMessage.isMassTaunt(spellId)) then
        if (event == "SPELL_AURA_APPLIED") then
            message = "Mass taunt"
        elseif (event == "SPELL_CAST_SUCCESS") then
            message = "Mass taunt"
        elseif (event == "SPELL_MISSED") then
            message = "Mass taunt"
        else
            message = nil
        end
        ITaunted.TauntMessage.massTauntLastCasted = timeNow;
    end

    if (canCastAgain and ITaunted.TauntMessage.isTaunt(spellId)) then
        if ((event == "SPELL_AURA_APPLIED" or event == "SPELL_CAST_SUCCESS") and ITaunted.TauntMessage.isDuplicateTaunt(destName, timeNow)) then
            message = nil
        elseif (event == "SPELL_AURA_APPLIED") then
            message = "Taunted " .. ITaunted.TauntMessage.GetIcon(destRaidFlags) .. " " .. destName
        elseif (event == "SPELL_CAST_SUCCESS") then
            message = "Taunted " .. ITaunted.TauntMessage.GetIcon(destRaidFlags) .. " " .. destName
        elseif (event == "SPELL_MISSED") then
            message = "Taunt failed on " .. ITaunted.TauntMessage.GetIcon(destRaidFlags) .. " " .. destName
        else
            message = nil
        end
    end

    if (message) then
        sendChatMessage(message);
        message = nil
    end
end

function ITaunted.TauntMessage.run()
    ITaunted.TauntMessage.Frame = CreateFrame("Frame")
    ITaunted.TauntMessage.Frame:RegisterEvent("ADDON_LOADED")
    if (ITaunted.TauntMessage.useUnitEvents) then
        ITaunted.TauntMessage.Frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
    else
        ITaunted.TauntMessage.Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
    ITaunted.TauntMessage.Frame:SetScript("OnEvent", function(self, event, arg1, ...)
        local playerGUID = UnitGUID("player")
        local _, instanceType = IsInInstance()
        local isOn = (ITauntedVars == nil or ITauntedVars.isOn ~= false)
        local isDebug = (ITauntedVars ~= nil and ITauntedVars.debugMode == true)

        if (event == "UNIT_SPELLCAST_SUCCEEDED") then
            local _, spellId = ...
            if (isOn and (instanceType == "raid" or isDebug)) then
                ITaunted.TauntMessage.handleUnitSpellcast(arg1, spellId)
            end
            return
        end

        if (event == "ADDON_LOADED" and arg1 == "ITaunted") then
            local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
            local date = getMetadata("ITaunted", "X-ResetVarsDate")

            -- reset out of date addons
            if (ITauntedVars and ITauntedVars.lastResetDate ~= date) then
                print('\124cffffcee2[i-Taunted]: Config had to be reset because of new functionality.')
                ITauntedVars = nil
            end

            if (ITauntedVars == nil) then
                ITauntedVars = {};
                ITauntedVars.isOn = true;
                ITauntedVars.debugMode = false;
                ITauntedVars.lastResetDate = date;
            end
        end

        if (event == "COMBAT_LOG_EVENT_UNFILTERED" and isOn and ITaunted.TauntMessage.playerHasValidTarget) then
            local _, _, _, sourceGUID = CombatLogGetCurrentEventInfo()
            local petGUID = UnitGUID("pet")
            local isMine = (sourceGUID == playerGUID or (petGUID ~= nil and sourceGUID == petGUID))

            if (isMine and (instanceType == "raid" or isDebug)) then
                ITaunted.TauntMessage.handleCombatLogEvent(CombatLogGetCurrentEventInfo())
            end
        end
    end
    )
end

local function ITaunted_DebugOn()
    print('\124cffffcee2[i-Taunted]: Debug is now: ON.')
    ITauntedVars.debugMode = true
end

local function ITaunted_DebugOff()
    print('\124cffffcee2[i-Taunted]: Debug is now: OFF.')
    ITauntedVars.debugMode = false;
end

local function ITaunted_On()
    print('\124cffffcee2[i-Taunted]: i-Taunted is now: ON.')
    ITauntedVars.isOn = true;
end

local function ITaunted_Off()
    print('\124cffffcee2[i-Taunted]: i-Taunted is now: OFF.')
    ITauntedVars.isOn = false;
end


local function ITaunted_Init(msg)
    -- pattern matching that skips leading whitespace and whitespace between cmd and args
    -- any whitespace at end of args is retained
    local _, _, cmd, _ = string.find(msg, "%s?(%w+)%s?(.*)")

    if cmd == "reset" then
        ITauntedVars = nil;
        if (ITauntedVars == nil) then
            print('\124cffffcee2[i-Taunted]: Settings have been reset. You should now type /reload.')
        end
    elseif cmd == "on" then
        ITaunted_On();
    elseif cmd == "off" then
        ITaunted_Off();
    elseif cmd == "debug" then
        if (ITauntedVars and ITauntedVars.debugMode == true) then
            ITaunted_DebugOff();
        elseif (ITauntedVars and ITauntedVars.debugMode == false) then
            ITaunted_DebugOn();
        end

        dump(ITauntedVars);
    elseif cmd == "dump" then
        dump(ITauntedVars);
    else
        print('\124cffffcee2[i-Taunted]: Available commands are: on, off, reset, debug, dump')
    end
end

SlashCmdList["ITAUNTED"] = ITaunted_Init;
SLASH_ITAUNTED1 = "/itaunted"
ITaunted.TauntMessage.run();
