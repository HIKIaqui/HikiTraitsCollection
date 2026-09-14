-- Hiki Traits
-- Central injury observation and transformation manager for Project Zomboid
-- B42.20.
--
-- Trait scripts register prioritized handlers here. This module owns the
-- injury snapshots, wound mutation, infection policy, health recalculation,
-- and multiplayer synchronization. A single incoming injury event can be
-- transformed by at most one handler.

require "HikiTraits/Library/Core"

HikiTraits.Library.Systems = HikiTraits.Library.Systems or {}

local Systems = HikiTraits.Library.Systems
Systems.InjuryManager = Systems.InjuryManager
    or HikiTraits.InjuryManager
    or {}

local InjuryManager = Systems.InjuryManager
local Effects = HikiTraits.Library.Effects
local Runtime = HikiTraits.Library.Runtime
local State = HikiTraits.Library.State
local Traits = HikiTraits.Library.Traits
local Util = HikiTraits.Library.Util

-- Preserve the public path used by the released trait scripts. The old file
-- now only forwards here, so saves never gain an extra mod dependency.
HikiTraits.InjuryManager = InjuryManager

InjuryManager.SCAN_INTERVAL_MS = 100
InjuryManager.TIMER_INCREASE_EPSILON = 0.001
InjuryManager.BODY_PART_SYNC_MASK = 0x3ffffffffff

InjuryManager.PRIORITY = InjuryManager.PRIORITY or {
    PREVENTION = 100,
    LOCATION_DEFENSE = 200,
    LIMITED_DEFENSE = 300,
    WORSENING = 400,
    DEFAULT = 500,
}

InjuryManager.INFECTION_POLICY = InjuryManager.INFECTION_POLICY or {
    PREVIOUS = "previous",
    CURRENT = "current",
}

InjuryManager.DEBUG = false
InjuryManager._states = InjuryManager._states or {}
InjuryManager._handlers = InjuryManager._handlers or {}
InjuryManager._observers = InjuryManager._observers or {}
InjuryManager._orderedHandlers = InjuryManager._orderedHandlers or {}
InjuryManager._orderedObservers = InjuryManager._orderedObservers or {}
InjuryManager._handlerOrderDirty = true
InjuryManager._observerOrderDirty = true
InjuryManager._lastScanMs = InjuryManager._lastScanMs or 0
InjuryManager._runtimeInstalled = InjuryManager._runtimeInstalled or false

local ensureRuntime

local INJURY_ORDER = {
    "bite",
    "cut",
    "scratch",
    "deepWound",
    "burn",
    "fracture",
    "glass",
    "bullet",
}

local INJURY_DEFINITIONS = {
    scratch = {
        activeField = "scratched",
        timerField = "scratchTime",
        label = "scratch",
    },
    cut = {
        activeField = "cut",
        timerField = "cutTime",
        label = "cut",
    },
    bite = {
        activeField = "bitten",
        timerField = "biteTime",
        label = "bite",
    },
    deepWound = {
        activeField = "deepWounded",
        timerField = "deepWoundTime",
        label = "deep wound",
    },
    burn = {
        activeField = "burnt",
        timerField = "burnTime",
        label = "burn",
    },
    fracture = {
        activeField = "fractured",
        timerField = "fractureTime",
        label = "fracture",
    },
    glass = {
        activeField = "glass",
        label = "glass",
    },
    bullet = {
        activeField = "bullet",
        label = "bullet",
    },
}

local SAFE_REPLACEMENTS = {
    scratch = true,
    cut = true,
}

local function debugLog(message)
    if InjuryManager.DEBUG then
        print("[HikiTraits][InjuryManager] " .. message)
    end
end

local function warningLog(message)
    print("[HikiTraits][InjuryManager] WARNING: " .. message)
end

local function getCharacterName(character)
    local username = character:getUsername()
    if username ~= nil and username ~= "" then
        return username
    end

    return tostring(character)
end

local function getCharacterKey(character)
    local username = character:getUsername()
    if username ~= nil and username ~= "" then
        return username
    end

    if isServer() then
        return tostring(character:getOnlineID())
    end

    return tostring(character)
end

local function copyArray(source)
    local result = {}

    if source == nil then
        return result
    end

    for index = 1, #source do
        result[index] = source[index]
    end

    return result
end

local function captureGlobalInfection(bodyDamage)
    return {
        bodyInfected = bodyDamage:isInfected(),
        bodyInfectionTime = bodyDamage:getInfectionTime(),
        bodyInfectionMortalityDuration =
            bodyDamage:getInfectionMortalityDuration(),
        bodyFakeInfected = bodyDamage:isIsFakeInfected(),
    }
end

local function capturePart(bodyPart)
    local fractureTime = bodyPart:getFractureTime()

    return {
        index = bodyPart:getIndex(),
        type = bodyPart:getType(),

        health = bodyPart:getHealth(),
        additionalPain = bodyPart:getAdditionalPain(),
        bleeding = bodyPart:bleeding(),
        bleedingTime = bodyPart:getBleedingTime(),

        scratched = bodyPart:scratched(),
        scratchTime = bodyPart:getScratchTime(),
        cut = bodyPart:isCut(),
        cutTime = bodyPart:getCutTime(),
        bitten = bodyPart:bitten(),
        biteTime = bodyPart:getBiteTime(),
        deepWounded = bodyPart:isDeepWounded(),
        deepWoundTime = bodyPart:getDeepWoundTime(),
        burnt = bodyPart:isBurnt(),
        burnTime = bodyPart:getBurnTime(),
        fractured = fractureTime > 0,
        fractureTime = fractureTime,
        glass = bodyPart:haveGlass(),
        bullet = bodyPart:haveBullet(),

        infected = bodyPart:IsInfected(),
        fakeInfected = bodyPart:IsFakeInfected(),
        infectedWound = bodyPart:isInfectedWound(),
        woundInfectionLevel = bodyPart:getWoundInfectionLevel(),
    }
end

local function captureState(character)
    local bodyDamage = character:getBodyDamage()
    local bodyParts = bodyDamage:getBodyParts()
    local parts = {}

    for index = 0, bodyParts:size() - 1 do
        parts[index + 1] = capturePart(bodyParts:get(index))
    end

    return {
        parts = parts,
        globalInfection = captureGlobalInfection(bodyDamage),
    }
end

local function isNewInjury(previous, current, injuryType)
    local definition = INJURY_DEFINITIONS[injuryType]
    local activeNow = current[definition.activeField]

    if not activeNow then
        return false
    end

    local activeBefore = previous[definition.activeField]
    if not activeBefore then
        return true
    end

    if definition.timerField == nil then
        return false
    end

    local timeBefore = previous[definition.timerField] or 0
    local timeNow = current[definition.timerField] or 0

    return timeNow > timeBefore + InjuryManager.TIMER_INCREASE_EPSILON
end

local function findNewInjuries(previous, current)
    local injuries = {}
    local injurySet = {}

    for index = 1, #INJURY_ORDER do
        local injuryType = INJURY_ORDER[index]

        if isNewInjury(previous, current, injuryType) then
            injuries[#injuries + 1] = injuryType
            injurySet[injuryType] = true
        end
    end

    return injuries, injurySet
end

local function injuryLabels(injuries)
    local labels = {}

    for index = 1, #injuries do
        local definition = INJURY_DEFINITIONS[injuries[index]]
        labels[index] = definition and definition.label or injuries[index]
    end

    return table.concat(labels, ", ")
end

local function restoreGlobalInfection(bodyDamage, state)
    bodyDamage:setInfected(state.bodyInfected)
    bodyDamage:setInfectionTime(state.bodyInfectionTime)
    bodyDamage:setInfectionMortalityDuration(
        state.bodyInfectionMortalityDuration
    )
    bodyDamage:setIsFakeInfected(state.bodyFakeInfected)
end

local function restorePartInfection(bodyPart, state)
    bodyPart:SetInfected(state.infected)
    bodyPart:SetFakeInfected(state.fakeInfected)
    bodyPart:setInfectedWound(state.infectedWound)
    bodyPart:setWoundInfectionLevel(state.woundInfectionLevel)
end

local function restoreCommonDamage(bodyPart, state)
    bodyPart:SetHealth(state.health)
    bodyPart:setAdditionalPain(state.additionalPain)
    bodyPart:setBleeding(state.bleeding)
    bodyPart:setBleedingTime(state.bleedingTime)
end

local function restoreInjury(bodyPart, state, injuryType)
    if injuryType == "scratch" then
        bodyPart:setScratched(state.scratched, true)
        bodyPart:setScratchTime(state.scratchTime)
    elseif injuryType == "cut" then
        bodyPart:setCut(state.cut, true)
        bodyPart:setCutTime(state.cutTime)
    elseif injuryType == "bite" then
        bodyPart:SetBitten(state.bitten, false)
        bodyPart:setBiteTime(state.biteTime)
    elseif injuryType == "deepWound" then
        bodyPart:setDeepWounded(state.deepWounded)
        bodyPart:setDeepWoundTime(state.deepWoundTime)
    elseif injuryType == "burn" then
        if state.burnt and not bodyPart:isBurnt() then
            bodyPart:setBurned()
        end
        bodyPart:setBurnTime(state.burnTime)
    elseif injuryType == "fracture" then
        bodyPart:setFractureTime(state.fractureTime)
    elseif injuryType == "glass" then
        bodyPart:setHaveGlass(state.glass)
    elseif injuryType == "bullet" then
        bodyPart:setHaveBullet(state.bullet, 0)
    else
        error("unsupported injury type: " .. tostring(injuryType))
    end
end

local function restoreExactState(bodyDamage, bodyPart, partState, globalState)
    for index = 1, #INJURY_ORDER do
        restoreInjury(bodyPart, partState, INJURY_ORDER[index])
    end

    restoreCommonDamage(bodyPart, partState)
    restorePartInfection(bodyPart, partState)
    restoreGlobalInfection(bodyDamage, globalState)
    bodyDamage:calculateOverallHealth()
end

local function applyReplacement(bodyPart, replacement)
    if replacement == "scratch" then
        bodyPart:setScratched(true, true)
    elseif replacement == "cut" then
        bodyPart:setCut(true, true)
    else
        error("unsafe replacement injury type: " .. tostring(replacement))
    end
end

local function normalizeInjuryList(injuries)
    if type(injuries) == "string" then
        return { injuries }
    end

    if type(injuries) ~= "table" then
        return nil
    end

    return copyArray(injuries)
end

local function applyOptions(decision, options)
    options = options or {}

    decision.infectionPolicy = options.infectionPolicy
        or InjuryManager.INFECTION_POLICY.CURRENT
    decision.rewindDamage = options.rewindDamage ~= false
    decision.metadata = options.metadata

    return decision
end

-- Returns a declarative decision. It does not mutate the body part. Trait
-- handlers return this value from their evaluate(context) callback.
function InjuryManager.decisionRemove(injuries, options)
    return applyOptions({
        action = "remove",
        injuries = normalizeInjuryList(injuries),
    }, options)
end

-- Safe replacements initially cover the transformations already proven in
-- Hiki Traits: any supported incoming injury can become a scratch or a cut.
function InjuryManager.decisionReplace(injuries, replacement, options)
    return applyOptions({
        action = "replace",
        injuries = normalizeInjuryList(injuries),
        replacement = replacement,
    }, options)
end

function InjuryManager.hasNewInjury(context, injuryType)
    return context ~= nil
        and context.newInjurySet ~= nil
        and context.newInjurySet[injuryType] == true
end

function InjuryManager.selectNewInjuries(context, allowedInjuries)
    local selected = {}

    if context == nil or type(allowedInjuries) ~= "table" then
        return selected
    end

    for index = 1, #context.newInjuries do
        local injuryType = context.newInjuries[index]

        if allowedInjuries[injuryType] == true then
            selected[#selected + 1] = injuryType
        end
    end

    return selected
end

local function normalizeInjurySet(injuries)
    local normalized = {}

    if type(injuries) == "string" then
        normalized[injuries] = true
        return normalized
    end

    if type(injuries) ~= "table" then
        return normalized
    end

    for key, value in pairs(injuries) do
        if type(key) == "number" then
            normalized[tostring(value)] = true
        elseif value == true then
            normalized[tostring(key)] = true
        end
    end

    return normalized
end

local function hasEnabledEntry(values)
    for _, enabled in pairs(values) do
        if enabled == true then
            return true
        end
    end

    return false
end

local function hasAnySelected(context, selected)
    for injuryType, enabled in pairs(selected) do
        if enabled and InjuryManager.hasNewInjury(context, injuryType) then
            return true
        end
    end

    return false
end

local function matchesBodyPart(context, bodyPart)
    if bodyPart == nil then
        return true
    end

    if type(bodyPart) == "function" then
        return bodyPart(context) == true
    end

    if type(bodyPart) == "table" then
        for key, value in pairs(bodyPart) do
            local wanted = type(key) == "number" and value or key
            local enabled = type(key) == "number" or value == true

            if enabled and (context.bodyPartType == wanted
                or tostring(context.bodyPartType) == tostring(wanted)) then
                return true
            end
        end

        return false
    end

    return context.bodyPartType == bodyPart
        or tostring(context.bodyPartType) == tostring(bodyPart)
end

local function validateRegistration(entry, callbackName)
    if type(entry) ~= "table" then
        return false, "registration must be a table"
    end

    if type(entry.id) ~= "string" or entry.id == "" then
        return false, "registration requires a non-empty id"
    end

    if type(entry[callbackName]) ~= "function" then
        return false, "registration requires " .. callbackName .. "(context)"
    end

    if entry.priority ~= nil and type(entry.priority) ~= "number" then
        return false, "priority must be a number"
    end

    return true, nil
end

function InjuryManager.registerHandler(handler)
    local valid, reason = validateRegistration(handler, "evaluate")
    if not valid then
        warningLog("handler rejected: " .. reason)
        return false
    end

    handler.priority = handler.priority or InjuryManager.PRIORITY.DEFAULT
    InjuryManager._handlers[handler.id] = handler
    InjuryManager._handlerOrderDirty = true

    debugLog(string.format(
        "registered handler %s at priority %d",
        handler.id,
        handler.priority
    ))

    ensureRuntime()

    return true
end

-- High-level registration for the common case: a trait selects incoming
-- injuries and removes or replaces them. Bespoke mechanics can still use the
-- lower-level registerHandler API without creating another scanner.
function InjuryManager.registerRule(specification)
    assert(type(specification) == "table", "injury rule is required")
    assert(Util.isNonEmptyString(specification.id), "rule id is required")

    local rule = Util.copyShallow(specification)
    rule.action = rule.action or "remove"
    rule.injurySet = normalizeInjurySet(rule.injuries)
    rule.triggerSet = normalizeInjurySet(
        rule.triggerInjuries or rule.injuries
    )

    -- Kahlua does not expose Lua's global next() in every game context.
    -- pairs() is available in B42 and works for these string-keyed sets.
    assert(hasEnabledEntry(rule.injurySet), "rule injuries are required")
    assert(
        rule.action == "remove" or rule.action == "replace",
        "rule action must be remove or replace"
    )
    assert(
        rule.action ~= "replace" or SAFE_REPLACEMENTS[rule.replacement],
        "replacement must be scratch or cut"
    )

    local stateOwner = rule.stateOwner or rule.traitId or rule.id
    local stateKey = rule.onceKey or "used"

    local handler = {
        id = rule.id,
        traitId = rule.traitId,
        priority = rule.priority,
        evaluate = function(context)
            if rule.traitId ~= nil
                and not Traits.has(context.character, rule.traitId) then
                return nil
            end

            if rule.once == true and State.Persistent.get(
                context.character,
                stateOwner,
                stateKey,
                false
            ) == true then
                return nil
            end

            if not matchesBodyPart(context, rule.bodyPart)
                or not hasAnySelected(context, rule.triggerSet) then
                return nil
            end

            if type(rule.when) == "function"
                and rule.when(context) ~= true then
                return nil
            end

            local selected = InjuryManager.selectNewInjuries(
                context,
                rule.injurySet
            )

            if #selected == 0 then
                return nil
            end

            if rule.action == "replace"
                and #selected ~= #context.newInjuries then
                return nil
            end

            local metadata = rule.metadata
            if type(metadata) == "function" then
                metadata = metadata(context)
            end

            local options = {
                infectionPolicy = rule.infectionPolicy,
                rewindDamage = rule.rewindDamage,
                metadata = metadata,
            }

            if rule.action == "replace" then
                return InjuryManager.decisionReplace(
                    selected,
                    rule.replacement,
                    options
                )
            end

            return InjuryManager.decisionRemove(selected, options)
        end,
        onApplied = function(context, outcome)
            if rule.once == true then
                State.Persistent.set(
                    context.character,
                    stateOwner,
                    stateKey,
                    true
                )
            end

            if rule.effects ~= nil then
                local effects = rule.effects
                if type(effects) == "function" then
                    effects = effects(context, outcome)
                end

                Effects.apply(context.character, effects, context)
            end

            if type(rule.onApplied) == "function" then
                rule.onApplied(context, outcome)
            end
        end,
    }

    InjuryManager.registerHandler(handler)
    return rule
end

function InjuryManager.unregisterHandler(handlerId)
    if InjuryManager._handlers[handlerId] == nil then
        return false
    end

    InjuryManager._handlers[handlerId] = nil
    InjuryManager._handlerOrderDirty = true
    return true
end

function InjuryManager.registerObserver(observer)
    local valid, reason = validateRegistration(observer, "observe")
    if not valid then
        warningLog("observer rejected: " .. reason)
        return false
    end

    observer.priority = observer.priority or InjuryManager.PRIORITY.DEFAULT
    InjuryManager._observers[observer.id] = observer
    InjuryManager._observerOrderDirty = true

    debugLog(string.format(
        "registered observer %s at priority %d",
        observer.id,
        observer.priority
    ))

    ensureRuntime()

    return true
end

function InjuryManager.unregisterObserver(observerId)
    if InjuryManager._observers[observerId] == nil then
        return false
    end

    InjuryManager._observers[observerId] = nil
    InjuryManager._observerOrderDirty = true
    return true
end

local function registrationSorter(left, right)
    if left.priority == right.priority then
        return left.id < right.id
    end

    return left.priority < right.priority
end

local function orderedRegistrations(source, cacheField, dirtyField)
    if not InjuryManager[dirtyField] then
        return InjuryManager[cacheField]
    end

    local ordered = {}

    for _, registration in pairs(source) do
        ordered[#ordered + 1] = registration
    end

    table.sort(ordered, registrationSorter)
    InjuryManager[cacheField] = ordered
    InjuryManager[dirtyField] = false

    return ordered
end

local function getOrderedHandlers()
    return orderedRegistrations(
        InjuryManager._handlers,
        "_orderedHandlers",
        "_handlerOrderDirty"
    )
end

local function getOrderedObservers()
    return orderedRegistrations(
        InjuryManager._observers,
        "_orderedObservers",
        "_observerOrderDirty"
    )
end

local function validateDecision(context, decision)
    if type(decision) ~= "table" then
        return false, "decision must be a table"
    end

    if decision.action ~= "remove" and decision.action ~= "replace" then
        return false, "action must be remove or replace"
    end

    if type(decision.injuries) ~= "table" or #decision.injuries == 0 then
        return false, "decision requires at least one injury"
    end

    local seen = {}

    for index = 1, #decision.injuries do
        local injuryType = decision.injuries[index]

        if INJURY_DEFINITIONS[injuryType] == nil then
            return false, "unknown injury type " .. tostring(injuryType)
        end

        if context.newInjurySet[injuryType] ~= true then
            return false, injuryType .. " is not new in this context"
        end

        if seen[injuryType] then
            return false, "duplicate injury type " .. injuryType
        end

        seen[injuryType] = true
    end

    if decision.action == "replace"
        and not SAFE_REPLACEMENTS[decision.replacement] then
        return false, "replacement must be scratch or cut"
    end

    -- Replacement setters generate their own health, pain, and bleeding. If
    -- another new injury on the same body part were left untouched, there is
    -- no reliable way to separate both injuries' shared damage contribution.
    -- Rejecting partial replacement avoids either duplicating that damage or
    -- healing the unrelated wound by accident.
    if decision.action == "replace" then
        local selectedCount = 0

        for _ in pairs(seen) do
            selectedCount = selectedCount + 1
        end

        if selectedCount ~= #context.newInjuries then
            return false,
                "replacement must include every new injury on the body part"
        end
    end

    if decision.infectionPolicy ~= InjuryManager.INFECTION_POLICY.PREVIOUS
        and decision.infectionPolicy
            ~= InjuryManager.INFECTION_POLICY.CURRENT then
        return false, "infectionPolicy must be previous or current"
    end

    return true, nil
end

local function handlesEveryNewInjury(context, decision)
    if #context.newInjuries ~= #decision.injuries then
        return false
    end

    local handled = {}
    for index = 1, #decision.injuries do
        handled[decision.injuries[index]] = true
    end

    for index = 1, #context.newInjuries do
        if not handled[context.newInjuries[index]] then
            return false
        end
    end

    return true
end

local function resultingInjuries(context, decision)
    local removed = {}
    local result = {}

    for index = 1, #decision.injuries do
        removed[decision.injuries[index]] = true
    end

    for index = 1, #context.newInjuries do
        local injuryType = context.newInjuries[index]
        if not removed[injuryType] then
            result[#result + 1] = injuryType
        end
    end

    if decision.action == "replace" then
        result[#result + 1] = decision.replacement
    end

    return result
end

local function syncMutation(context)
    if type(syncBodyPart) == "function" then
        syncBodyPart(
            context.bodyPart,
            InjuryManager.BODY_PART_SYNC_MASK
        )
    else
        warningLog("syncBodyPart is unavailable; injury changed locally only")
    end
end

local function applyDecision(context, handler, decision)
    local bodyDamage = context.bodyDamage
    local bodyPart = context.bodyPart
    local rollbackPart = capturePart(bodyPart)
    local rollbackGlobal = captureGlobalInfection(bodyDamage)
    local allNewHandled = handlesEveryNewInjury(context, decision)
    local rewindDamage = decision.rewindDamage and allNewHandled

    local infectionPart
    local infectionGlobal

    if decision.infectionPolicy == InjuryManager.INFECTION_POLICY.PREVIOUS then
        infectionPart = context.previousPart
        infectionGlobal = context.previousState.globalInfection
    else
        infectionPart = rollbackPart
        infectionGlobal = rollbackGlobal
    end

    local applied, applyError = pcall(function()
        for index = 1, #decision.injuries do
            restoreInjury(
                bodyPart,
                context.previousPart,
                decision.injuries[index]
            )
        end

        if rewindDamage then
            restoreCommonDamage(bodyPart, context.previousPart)
        end

        restorePartInfection(bodyPart, infectionPart)
        restoreGlobalInfection(bodyDamage, infectionGlobal)

        if decision.action == "replace" then
            applyReplacement(bodyPart, decision.replacement)
        end

        -- Injury setters may roll or rewrite infection state. The selected
        -- policy is therefore applied once more after the replacement.
        restorePartInfection(bodyPart, infectionPart)
        restoreGlobalInfection(bodyDamage, infectionGlobal)
        bodyDamage:calculateOverallHealth()
    end)

    if not applied then
        local rolledBack, rollbackError = pcall(function()
            restoreExactState(
                bodyDamage,
                bodyPart,
                rollbackPart,
                rollbackGlobal
            )
        end)

        if not rolledBack then
            warningLog(string.format(
                "handler %s failed and rollback also failed: %s / %s",
                handler.id,
                tostring(applyError),
                tostring(rollbackError)
            ))
        else
            warningLog(string.format(
                "handler %s failed; original state restored: %s",
                handler.id,
                tostring(applyError)
            ))
        end

        return nil, applyError
    end

    syncMutation(context)

    return {
        applied = true,
        handlerId = handler.id,
        action = decision.action,
        removedInjuries = copyArray(decision.injuries),
        replacement = decision.replacement,
        resultingInjuries = resultingInjuries(context, decision),
        infectionPolicy = decision.infectionPolicy,
        rewoundDamage = rewindDamage,
        metadata = decision.metadata,
    }, nil
end

local function notifyObservers(context, outcome)
    local observers = getOrderedObservers()

    for index = 1, #observers do
        local observer = observers[index]
        local eligible = observer.traitId == nil
            or Traits.has(context.character, observer.traitId)

        if eligible and type(observer.when) == "function" then
            local conditionWorked, applies = pcall(
                observer.when,
                context,
                outcome
            )

            eligible = conditionWorked and applies == true
            if not conditionWorked then
                warningLog(string.format(
                    "observer %s condition failed: %s",
                    observer.id,
                    tostring(applies)
                ))
            end
        end

        local succeeded = true
        local observerError = nil

        if eligible then
            succeeded, observerError = pcall(
                observer.observe,
                context,
                outcome
            )
        end

        if not succeeded then
            warningLog(string.format(
                "observer %s failed: %s",
                observer.id,
                tostring(observerError)
            ))
        end
    end
end

local function processContext(context)
    local handlers = getOrderedHandlers()
    local outcome = {
        applied = false,
        handlerId = nil,
        action = "accept",
        removedInjuries = {},
        replacement = nil,
        resultingInjuries = copyArray(context.newInjuries),
        infectionPolicy = nil,
        rewoundDamage = false,
        metadata = nil,
    }

    for index = 1, #handlers do
        local handler = handlers[index]
        local eligible = handler.traitId == nil
            or Traits.has(context.character, handler.traitId)
        local evaluated = true
        local decisionOrError = nil

        if eligible then
            evaluated, decisionOrError = pcall(
                handler.evaluate,
                context
            )
        end

        if not evaluated then
            warningLog(string.format(
                "handler %s evaluation failed: %s",
                handler.id,
                tostring(decisionOrError)
            ))
        elseif decisionOrError ~= nil then
            local valid, reason = validateDecision(context, decisionOrError)

            if not valid then
                warningLog(string.format(
                    "handler %s returned an invalid decision: %s",
                    handler.id,
                    reason
                ))
            else
                local appliedOutcome = applyDecision(
                    context,
                    handler,
                    decisionOrError
                )

                if appliedOutcome ~= nil then
                    outcome = appliedOutcome

                    if type(handler.onApplied) == "function" then
                        local callbackWorked, callbackError = pcall(
                            handler.onApplied,
                            context,
                            outcome
                        )

                        if not callbackWorked then
                            warningLog(string.format(
                                "handler %s onApplied failed: %s",
                                handler.id,
                                tostring(callbackError)
                            ))
                        end
                    end
                end

                -- A valid decision owns this event even if an unexpected Java
                -- bridge failure prevented the mutation. A lower-priority rule
                -- must not attempt a second, contradictory transformation.
                break
            end
        end
    end

    context.finalPart = capturePart(context.bodyPart)
    context.outcome = outcome
    notifyObservers(context, outcome)

    return outcome.applied
end

local function buildContexts(character, previousState, currentState)
    local contexts = {}
    local bodyDamage = character:getBodyDamage()
    local bodyParts = bodyDamage:getBodyParts()

    for index = 0, bodyParts:size() - 1 do
        local previousPart = previousState.parts[index + 1]
        local currentPart = currentState.parts[index + 1]

        if previousPart ~= nil and currentPart ~= nil then
            local injuries, injurySet = findNewInjuries(
                previousPart,
                currentPart
            )

            if #injuries > 0 then
                contexts[#contexts + 1] = {
                    character = character,
                    characterKey = getCharacterKey(character),
                    bodyDamage = bodyDamage,
                    bodyPart = bodyParts:get(index),
                    bodyPartIndex = index,
                    bodyPartType = currentPart.type,
                    previousPart = previousPart,
                    currentPart = currentPart,
                    previousState = previousState,
                    currentState = currentState,
                    newInjuries = injuries,
                    newInjurySet = injurySet,
                }
            end
        end
    end

    return contexts
end

function InjuryManager.processCharacter(character)
    if character == nil then
        return false
    end

    local key = getCharacterKey(character)

    if character:isDead() then
        InjuryManager._states[key] = nil
        return false
    end

    local currentState = captureState(character)
    local previousState = InjuryManager._states[key]

    if previousState == nil
        or #previousState.parts ~= #currentState.parts then
        InjuryManager._states[key] = currentState
        debugLog(getCharacterName(character) .. " injury snapshot initialized")
        return false
    end

    local contexts = buildContexts(character, previousState, currentState)
    local changed = false

    for index = 1, #contexts do
        local context = contexts[index]

        debugLog(string.format(
            "%s received new injury on body part %d: %s",
            getCharacterName(character),
            context.bodyPartIndex,
            injuryLabels(context.newInjuries)
        ))

        if processContext(context) then
            changed = true

            debugLog(string.format(
                "%s applied %s through %s on body part %d",
                getCharacterName(character),
                context.outcome.action,
                context.outcome.handlerId,
                context.bodyPartIndex
            ))
        end
    end

    if changed and type(sendDamage) == "function" then
        sendDamage(character)
    end

    -- Always snapshot the final state. This permanently accepts injuries that
    -- no handler could transform and prevents generated replacements from
    -- appearing as fresh incoming wounds on the next scan.
    InjuryManager._states[key] = captureState(character)

    return changed
end

function InjuryManager.refreshCharacter(character)
    if character == nil then
        return false
    end

    local key = getCharacterKey(character)

    if character:isDead() then
        InjuryManager._states[key] = nil
        return false
    end

    InjuryManager._states[key] = captureState(character)
    return true
end

function InjuryManager.clearCharacter(character)
    if character == nil then
        return false
    end

    InjuryManager._states[getCharacterKey(character)] = nil
    return true
end

ensureRuntime = function()
    if InjuryManager._runtimeInstalled then
        return true
    end

    Runtime.registerInterval(InjuryManager.SCAN_INTERVAL_MS, {
        id = "hikitraits:library:injury-manager",
        scope = Runtime.Scope.AUTHORITATIVE,
        priority = 100,
        run = function(context)
            InjuryManager.processCharacter(context.character)
        end,
    })

    InjuryManager._runtimeInstalled = true
    debugLog("100 ms centralized injury manager installed through Runtime")
    return true
end

function InjuryManager.ensureInstalled()
    return ensureRuntime()
end

return InjuryManager
