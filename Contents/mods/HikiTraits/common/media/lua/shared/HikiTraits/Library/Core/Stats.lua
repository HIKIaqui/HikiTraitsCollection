-- Hiki Traits Library
-- Clamped character-stat mutations with automatic multiplayer sync.

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}
HikiTraits.Library.Core = HikiTraits.Library.Core or {}

require "HikiTraits/Library/Core/Util"

local Core = HikiTraits.Library.Core
Core.Stats = Core.Stats or {}

local Stats = Core.Stats
local Util = Core.Util

Stats.EPSILON = Stats.EPSILON or 0.0000001

local function unchangedResult(stat, value)
    return {
        stat = stat,
        before = value,
        after = value,
        delta = 0,
        changed = false,
    }
end

function Stats.get(character, stat)
    if character == nil or stat == nil then
        return nil
    end

    local stats = character:getStats()
    if stats == nil then
        return nil
    end

    return tonumber(stats:get(stat))
end

function Stats.getBounds(stat)
    if stat == nil then
        return nil, nil
    end

    local minimum = Util.safeCall(nil, function()
        return stat:getMinimumValue()
    end)
    local maximum = Util.safeCall(nil, function()
        return stat:getMaximumValue()
    end)

    return tonumber(minimum), tonumber(maximum)
end

function Stats.clamp(stat, value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end

    local clamped, succeeded = Util.safeCall(number, function()
        return stat:clamp(number)
    end)

    if succeeded then
        return tonumber(clamped) or number
    end

    local minimum, maximum = Stats.getBounds(stat)
    return Util.clamp(number, minimum, maximum)
end

function Stats.sync(character, stat)
    if character == nil or stat == nil then
        return false
    end

    if type(sendPlayerStat) ~= "function" then
        return false
    end

    if not Util.isClientContext() and not Util.isServerContext() then
        return false
    end

    local succeeded = pcall(sendPlayerStat, character, stat)
    return succeeded
end

function Stats.syncDamage(character)
    if character == nil then
        return false
    end

    if Util.isServerContext() and type(sendDamage) == "function" then
        sendDamage(character)
        return true
    end

    return false
end

function Stats.set(character, stat, wantedValue, options)
    options = options or {}

    local before = Stats.get(character, stat)
    if before == nil then
        return unchangedResult(stat, nil)
    end

    local target = tonumber(wantedValue)
    if target == nil then
        return unchangedResult(stat, before)
    end

    if options.clamp ~= false then
        target = Stats.clamp(stat, target)
    end

    if target == nil
        or math.abs(target - before)
            <= (options.epsilon or Stats.EPSILON) then
        return unchangedResult(stat, before)
    end

    character:getStats():set(stat, target)
    local after = Stats.get(character, stat) or target
    local result = {
        stat = stat,
        before = before,
        after = after,
        delta = after - before,
        changed = math.abs(after - before) > Stats.EPSILON,
    }

    if result.changed and options.sync ~= false then
        Stats.sync(character, stat)
    end

    return result
end

function Stats.change(character, stat, delta, options)
    options = options or {}

    local before = Stats.get(character, stat)
    if before == nil then
        return unchangedResult(stat, nil)
    end

    local wantedDelta = tonumber(delta) or 0
    if math.abs(wantedDelta) <= (options.epsilon or Stats.EPSILON) then
        return unchangedResult(stat, before)
    end

    local target = before + wantedDelta
    if options.clamp ~= false then
        target = Stats.clamp(stat, target)
    end

    if target == nil
        or math.abs(target - before)
            <= (options.epsilon or Stats.EPSILON) then
        return unchangedResult(stat, before)
    end

    if target > before then
        character:getStats():add(stat, target - before)
    else
        character:getStats():remove(stat, before - target)
    end

    local after = Stats.get(character, stat) or target
    local result = {
        stat = stat,
        before = before,
        after = after,
        delta = after - before,
        changed = math.abs(after - before) > Stats.EPSILON,
    }

    if result.changed and options.sync ~= false then
        Stats.sync(character, stat)
    end

    return result
end

function Stats.add(character, stat, amount, options)
    return Stats.change(character, stat, math.abs(tonumber(amount) or 0), options)
end

function Stats.remove(character, stat, amount, options)
    return Stats.change(character, stat, -math.abs(tonumber(amount) or 0), options)
end

function Stats.setAtLeast(character, stat, minimum, options)
    local current = Stats.get(character, stat)
    if current == nil or current >= minimum then
        return unchangedResult(stat, current)
    end

    return Stats.set(character, stat, minimum, options)
end

function Stats.setAtMost(character, stat, maximum, options)
    local current = Stats.get(character, stat)
    if current == nil or current <= maximum then
        return unchangedResult(stat, current)
    end

    return Stats.set(character, stat, maximum, options)
end

function Stats.isAtMaximum(character, stat, epsilon)
    local current = Stats.get(character, stat)
    local _, maximum = Stats.getBounds(stat)

    if current == nil or maximum == nil then
        return false
    end

    return current >= maximum - (epsilon or Stats.EPSILON)
end

function Stats.isAtMinimum(character, stat, epsilon)
    local current = Stats.get(character, stat)
    local minimum = Stats.getBounds(stat)

    if current == nil or minimum == nil then
        return false
    end

    return current <= minimum + (epsilon or Stats.EPSILON)
end

function Stats.getFraction(character, stat)
    local current = Stats.get(character, stat)
    local minimum, maximum = Stats.getBounds(stat)

    if current == nil or minimum == nil or maximum == nil
        or maximum <= minimum then
        return nil
    end

    return Util.clamp(
        (current - minimum) / (maximum - minimum),
        0,
        1
    )
end

local function performOperation(character, operation)
    local kind = operation.operation or operation.kind
    local value = operation.value
    local options = { sync = false, clamp = operation.clamp }

    if kind == "add" then
        return Stats.add(character, operation.stat, value, options)
    elseif kind == "remove" then
        return Stats.remove(character, operation.stat, value, options)
    elseif kind == "set" then
        return Stats.set(character, operation.stat, value, options)
    elseif kind == "atLeast" then
        return Stats.setAtLeast(character, operation.stat, value, options)
    elseif kind == "atMost" then
        return Stats.setAtMost(character, operation.stat, value, options)
    end

    return unchangedResult(operation.stat, Stats.get(character, operation.stat))
end

function Stats.apply(character, operations, options)
    options = options or {}

    local results = {}
    local changedStats = {}

    if character == nil or type(operations) ~= "table" then
        return results
    end

    for index = 1, #operations do
        local operation = operations[index]

        if type(operation) == "table" and operation.stat ~= nil then
            local result = performOperation(character, operation)
            results[#results + 1] = result

            if result.changed then
                local alreadyRemembered = false

                for statIndex = 1, #changedStats do
                    if changedStats[statIndex] == result.stat then
                        alreadyRemembered = true
                        break
                    end
                end

                if not alreadyRemembered then
                    changedStats[#changedStats + 1] = result.stat
                end
            end
        end
    end

    if options.sync ~= false then
        for index = 1, #changedStats do
            Stats.sync(character, changedStats[index])
        end
    end

    return results
end

function Stats.damageHealth(character, amount, options)
    options = options or {}

    local result = {
        before = nil,
        after = nil,
        delta = 0,
        changed = false,
    }

    if character == nil or (tonumber(amount) or 0) <= 0 then
        return result
    end

    local bodyDamage = character:getBodyDamage()
    if bodyDamage == nil then
        return result
    end

    result.before = tonumber(bodyDamage:getOverallBodyHealth())
    bodyDamage:ReduceGeneralHealth(tonumber(amount))
    result.after = tonumber(bodyDamage:getOverallBodyHealth())

    if result.before ~= nil and result.after ~= nil then
        result.delta = result.after - result.before
        result.changed = math.abs(result.delta) > Stats.EPSILON
    end

    if result.changed and options.sync ~= false then
        Stats.syncDamage(character)
    end

    return result
end

function Stats.healHealth(character, amount, options)
    options = options or {}

    local result = {
        before = nil,
        after = nil,
        delta = 0,
        changed = false,
    }

    if character == nil or (tonumber(amount) or 0) <= 0 then
        return result
    end

    local bodyDamage = character:getBodyDamage()
    if bodyDamage == nil then
        return result
    end

    result.before = tonumber(bodyDamage:getOverallBodyHealth())
    bodyDamage:AddGeneralHealth(tonumber(amount))
    result.after = tonumber(bodyDamage:getOverallBodyHealth())

    if result.before ~= nil and result.after ~= nil then
        result.delta = result.after - result.before
        result.changed = math.abs(result.delta) > Stats.EPSILON
    end

    if result.changed and options.sync ~= false then
        Stats.syncDamage(character)
    end

    return result
end

return Stats
