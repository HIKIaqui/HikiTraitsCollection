-- Hiki Traits Library
-- Declarative gameplay effects used by Runtime rules and triggers.

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}
HikiTraits.Library.Core = HikiTraits.Library.Core or {}

require "HikiTraits/Library/Core/Util"
require "HikiTraits/Library/Core/Logger"
require "HikiTraits/Library/Core/Stats"

local Core = HikiTraits.Library.Core
Core.Effects = Core.Effects or {}

local Effects = Core.Effects
local Logger = Core.Logger
local Stats = Core.Stats
local Util = Core.Util

local log = Logger.scoped("Effects")

local function statEffect(operation, stat, value, options)
    options = options or {}

    return {
        type = "stat",
        operation = operation,
        stat = stat,
        value = value,
        when = options.when,
        clamp = options.clamp,
    }
end

function Effects.addStat(stat, amount, options)
    return statEffect("add", stat, amount, options)
end

function Effects.removeStat(stat, amount, options)
    return statEffect("remove", stat, amount, options)
end

function Effects.setStat(stat, value, options)
    return statEffect("set", stat, value, options)
end

function Effects.setStatAtLeast(stat, value, options)
    return statEffect("atLeast", stat, value, options)
end

function Effects.setStatAtMost(stat, value, options)
    return statEffect("atMost", stat, value, options)
end

function Effects.damageHealth(amount, options)
    options = options or {}

    return {
        type = "healthDamage",
        value = amount,
        when = options.when,
    }
end

function Effects.healHealth(amount, options)
    options = options or {}

    return {
        type = "healthHealing",
        value = amount,
        when = options.when,
    }
end

function Effects.custom(callback, options)
    options = options or {}
    assert(type(callback) == "function", "custom effect callback is required")

    return {
        type = "custom",
        callback = callback,
        when = options.when,
    }
end

local function shouldApply(effect, context)
    if type(effect.when) ~= "function" then
        return true
    end

    return effect.when(context) == true
end

local function rememberStat(changedStats, stat)
    for index = 1, #changedStats do
        if changedStats[index] == stat then
            return
        end
    end

    changedStats[#changedStats + 1] = stat
end

local function applyStatEffect(character, effect, context)
    local value = Util.resolveValue(effect.value, context)
    local operation = {
        operation = effect.operation,
        stat = effect.stat,
        value = value,
        clamp = effect.clamp,
    }

    return Stats.apply(character, { operation }, { sync = false })[1]
end

function Effects.apply(character, effects, context)
    local results = {}
    local changedStats = {}
    local damageChanged = false

    if character == nil or type(effects) ~= "table" then
        return results
    end

    for index = 1, #effects do
        local effect = effects[index]

        if type(effect) == "table" then
            local succeeded, result = pcall(function()
                if not shouldApply(effect, context) then
                    return nil
                end

                if effect.type == "stat" then
                    return applyStatEffect(character, effect, context)
                elseif effect.type == "healthDamage" then
                    local amount = tonumber(
                        Util.resolveValue(effect.value, context)
                    ) or 0

                    return Stats.damageHealth(
                        character,
                        amount,
                        { sync = false }
                    )
                elseif effect.type == "healthHealing" then
                    local amount = tonumber(
                        Util.resolveValue(effect.value, context)
                    ) or 0

                    return Stats.healHealth(
                        character,
                        amount,
                        { sync = false }
                    )
                elseif effect.type == "custom" then
                    return effect.callback(context)
                end

                return nil
            end)

            if not succeeded then
                log:error("effect %d failed: %s", index, tostring(result))
            elseif result ~= nil then
                results[#results + 1] = result

                if effect.type == "stat" and result.changed then
                    rememberStat(changedStats, effect.stat)
                elseif (effect.type == "healthDamage"
                    or effect.type == "healthHealing")
                    and result.changed then
                    damageChanged = true
                end
            end
        end
    end

    for index = 1, #changedStats do
        Stats.sync(character, changedStats[index])
    end

    if damageChanged then
        Stats.syncDamage(character)
    end

    return results
end

return Effects
