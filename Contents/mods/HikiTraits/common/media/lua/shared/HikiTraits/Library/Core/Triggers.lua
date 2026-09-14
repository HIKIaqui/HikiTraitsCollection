-- Hiki Traits Library
-- Edge-triggered, rearmable rules such as Shrug It Off and Loses Control.

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}
HikiTraits.Library.Core = HikiTraits.Library.Core or {}

require "HikiTraits/Library/Core/Util"
require "HikiTraits/Library/Core/Stats"
require "HikiTraits/Library/Core/State"
require "HikiTraits/Library/Core/Effects"
require "HikiTraits/Library/Core/Runtime"

local Core = HikiTraits.Library.Core
Core.Triggers = Core.Triggers or {}

local Triggers = Core.Triggers
local Effects = Core.Effects
local Runtime = Core.Runtime
local State = Core.State
local Stats = Core.Stats
local Util = Core.Util

Triggers._definitions = Triggers._definitions or {}

local function validate(specification)
    assert(type(specification) == "table", "trigger specification is required")
    assert(Util.isNonEmptyString(specification.id), "trigger id is required")
    assert(type(specification.read) == "function", "trigger read is required")
    assert(
        type(specification.isTriggered) == "function",
        "trigger predicate is required"
    )
    assert(
        type(specification.isRearmed) == "function",
        "trigger rearm predicate is required"
    )
    assert(
        specification.effects ~= nil
            or type(specification.onTrigger) == "function",
        "trigger needs effects or onTrigger"
    )
end

local function getStorage(definition)
    return State.getStorage(definition.stateMode)
end

local function stateOwner(definition)
    return definition.stateOwner or definition.id
end

local function stateKey(definition)
    return definition.stateKey or "armed"
end

local function isArmed(character, definition)
    return getStorage(definition).initialize(
        character,
        stateOwner(definition),
        stateKey(definition),
        definition.initiallyArmed ~= false
    ) == true
end

local function setArmed(character, definition, armed)
    getStorage(definition).set(
        character,
        stateOwner(definition),
        stateKey(definition),
        armed == true
    )
end

local function runTrigger(definition, context)
    local value = definition.read(context)
    context.triggerValue = value

    if isArmed(context.character, definition) then
        if definition.isTriggered(value, context) ~= true then
            return
        end

        -- Consume first so nested stat/network callbacks cannot fire twice.
        setArmed(context.character, definition, false)

        local effects = definition.effects
        if type(effects) == "function" then
            effects = effects(context, value)
        end

        if effects ~= nil then
            context.effectResults = Effects.apply(
                context.character,
                effects,
                context
            )
        end

        if type(definition.onTrigger) == "function" then
            definition.onTrigger(context, value)
        end

        return
    end

    if definition.isRearmed(value, context) == true then
        setArmed(context.character, definition, true)

        if type(definition.onRearm) == "function" then
            definition.onRearm(context, value)
        end
    end
end

function Triggers.register(specification)
    validate(specification)

    local definition = Util.copyShallow(specification)
    definition.runtimeId = definition.runtimeId
        or "trigger:" .. definition.id
    definition.stateMode = definition.stateMode or "persistent"
    Triggers._definitions[definition.id] = definition

    local runtimeSpecification = {
        id = definition.runtimeId,
        traitId = definition.traitId,
        scope = definition.scope or Runtime.Scope.AUTHORITATIVE,
        priority = definition.priority,
        allowDead = definition.allowDead,
        when = definition.when,
        debug = definition.debug,
        run = function(context)
            return runTrigger(definition, context)
        end,
    }

    if definition.schedule == "minute" then
        Runtime.registerMinute(runtimeSpecification)
    else
        Runtime.registerInterval(
            tonumber(definition.intervalMs) or 100,
            runtimeSpecification
        )
    end

    return definition
end

local function numericValue(value)
    return tonumber(value)
end

function Triggers.registerHigh(specification)
    local definition = Util.copyShallow(specification)
    local triggerAt = definition.triggerAt
    local rearmAt = definition.rearmAt
    local triggerInclusive = definition.triggerInclusive ~= false
    local rearmInclusive = definition.rearmInclusive ~= false

    definition.isTriggered = function(value, context)
        local current = numericValue(value)
        local threshold = numericValue(Util.resolveValue(triggerAt, context))

        if current == nil or threshold == nil then
            return false
        end

        if triggerInclusive then
            return current >= threshold
        end

        return current > threshold
    end

    definition.isRearmed = function(value, context)
        local current = numericValue(value)
        local threshold = numericValue(Util.resolveValue(rearmAt, context))

        if current == nil or threshold == nil then
            return false
        end

        if rearmInclusive then
            return current <= threshold
        end

        return current < threshold
    end

    return Triggers.register(definition)
end

function Triggers.registerLow(specification)
    local definition = Util.copyShallow(specification)
    local triggerAt = definition.triggerAt
    local rearmAt = definition.rearmAt
    local triggerInclusive = definition.triggerInclusive ~= false
    local rearmInclusive = definition.rearmInclusive ~= false

    definition.isTriggered = function(value, context)
        local current = numericValue(value)
        local threshold = numericValue(Util.resolveValue(triggerAt, context))

        if current == nil or threshold == nil then
            return false
        end

        if triggerInclusive then
            return current <= threshold
        end

        return current < threshold
    end

    definition.isRearmed = function(value, context)
        local current = numericValue(value)
        local threshold = numericValue(Util.resolveValue(rearmAt, context))

        if current == nil or threshold == nil then
            return false
        end

        if rearmInclusive then
            return current >= threshold
        end

        return current > threshold
    end

    return Triggers.register(definition)
end

function Triggers.registerStatHigh(specification)
    local definition = Util.copyShallow(specification)
    local stat = definition.stat

    assert(stat ~= nil, "stat trigger requires a CharacterStat")

    definition.read = function(context)
        return Stats.get(context.character, stat)
    end

    if definition.triggerAt == nil and definition.atMaximum then
        definition.triggerAt = function()
            local _, maximum = Stats.getBounds(stat)
            return maximum
        end
    end

    return Triggers.registerHigh(definition)
end

function Triggers.registerStatLow(specification)
    local definition = Util.copyShallow(specification)
    local stat = definition.stat

    assert(stat ~= nil, "stat trigger requires a CharacterStat")

    definition.read = function(context)
        return Stats.get(context.character, stat)
    end

    if definition.triggerAt == nil and definition.atMinimum then
        definition.triggerAt = function()
            local minimum = Stats.getBounds(stat)
            return minimum
        end
    end

    return Triggers.registerLow(definition)
end

function Triggers.isArmed(character, id)
    local definition = Triggers._definitions[tostring(id)]
    if definition == nil then
        return nil
    end

    return isArmed(character, definition)
end

function Triggers.forceArm(character, id, armed)
    local definition = Triggers._definitions[tostring(id)]
    if definition == nil then
        return false
    end

    setArmed(character, definition, armed ~= false)
    return true
end

function Triggers.unregister(id)
    local key = tostring(id)
    local definition = Triggers._definitions[key]
    if definition == nil then
        return false
    end

    Runtime.unregister(definition.runtimeId)
    Triggers._definitions[key] = nil
    return true
end

return Triggers
