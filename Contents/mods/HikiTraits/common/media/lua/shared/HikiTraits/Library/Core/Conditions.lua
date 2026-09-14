-- Hiki Traits Library
-- Reusable predicates for declarative trait definitions.

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}
HikiTraits.Library.Core = HikiTraits.Library.Core or {}

require "HikiTraits/Library/Core/Util"
require "HikiTraits/Library/Core/Traits"
require "HikiTraits/Library/Core/Stats"

local Core = HikiTraits.Library.Core
Core.Conditions = Core.Conditions or {}

local Conditions = Core.Conditions
local Stats = Core.Stats
local Traits = Core.Traits
local Util = Core.Util

local function collectArguments(...)
    local values = {}

    for index = 1, select("#", ...) do
        values[index] = select(index, ...)
    end

    return values
end

function Conditions.always()
    return function()
        return true
    end
end

function Conditions.custom(predicate)
    assert(type(predicate) == "function", "condition must be a function")
    return predicate
end

function Conditions.all(...)
    local predicates = collectArguments(...)

    return function(context)
        for index = 1, #predicates do
            if not predicates[index](context) then
                return false
            end
        end

        return true
    end
end

function Conditions.any(...)
    local predicates = collectArguments(...)

    return function(context)
        for index = 1, #predicates do
            if predicates[index](context) then
                return true
            end
        end

        return false
    end
end

function Conditions.none(predicate)
    return function(context)
        return not predicate(context)
    end
end

function Conditions.hasTrait(traitId)
    return function(context)
        return Traits.has(context.character, traitId)
    end
end

local function statComparison(stat, expected, comparer)
    return function(context)
        local current = Stats.get(context.character, stat)
        local target = Util.resolveValue(expected, context)

        if current == nil or tonumber(target) == nil then
            return false
        end

        return comparer(current, tonumber(target))
    end
end

function Conditions.statAtLeast(stat, expected)
    return statComparison(stat, expected, function(current, target)
        return current >= target
    end)
end

function Conditions.statAbove(stat, expected)
    return statComparison(stat, expected, function(current, target)
        return current > target
    end)
end

function Conditions.statAtMost(stat, expected)
    return statComparison(stat, expected, function(current, target)
        return current <= target
    end)
end

function Conditions.statBelow(stat, expected)
    return statComparison(stat, expected, function(current, target)
        return current < target
    end)
end

function Conditions.statBetween(stat, minimum, maximum)
    return Conditions.all(
        Conditions.statAtLeast(stat, minimum),
        Conditions.statAtMost(stat, maximum)
    )
end

function Conditions.statAtMaximum(stat, epsilon)
    return function(context)
        return Stats.isAtMaximum(context.character, stat, epsilon)
    end
end

function Conditions.statAtMinimum(stat, epsilon)
    return function(context)
        return Stats.isAtMinimum(context.character, stat, epsilon)
    end
end

function Conditions.moodleLevel(moodleType)
    return function(context)
        local character = context.character
        if character == nil then
            return nil
        end

        local moodles = character:getMoodles()
        if moodles == nil then
            return nil
        end

        return tonumber(moodles:getMoodleLevel(moodleType))
    end
end

local function moodleComparison(moodleType, expected, comparer)
    local readLevel = Conditions.moodleLevel(moodleType)

    return function(context)
        local level = readLevel(context)
        local target = tonumber(Util.resolveValue(expected, context))

        return level ~= nil and target ~= nil and comparer(level, target)
    end
end

function Conditions.moodleAtLeast(moodleType, expected)
    return moodleComparison(moodleType, expected, function(level, target)
        return level >= target
    end)
end

function Conditions.moodleAtMost(moodleType, expected)
    return moodleComparison(moodleType, expected, function(level, target)
        return level <= target
    end)
end

function Conditions.moodleEquals(moodleType, expected)
    return moodleComparison(moodleType, expected, function(level, target)
        return level == target
    end)
end

function Conditions.sitting()
    return function(context)
        local character = context.character
        if character == nil then
            return false
        end

        local sittingOnGround = Util.safeCall(false, function()
            return character:isSitOnGround()
        end)

        if sittingOnGround == true then
            return true
        end

        local sittingOnFurniture = Util.safeCall(false, function()
            return character:isSittingOnFurniture()
        end)

        return sittingOnFurniture == true
    end
end

function Conditions.driving()
    return function(context)
        local character = context.character
        if character == nil then
            return false
        end

        local vehicle = Util.safeCall(nil, function()
            return character:getVehicle()
        end)

        if vehicle == nil then
            return false
        end

        local driver = Util.safeCall(nil, function()
            return vehicle:getDriver()
        end)

        return driver == character
    end
end

function Conditions.outside()
    return function(context)
        local character = context.character
        if character == nil then
            return false
        end

        local square = character:getSquare()
        return square ~= nil and square:isOutside()
    end
end

function Conditions.weightTrouble()
    return function(context)
        local character = context.character
        if character == nil then
            return false
        end

        local nutrition = character:getNutrition()
        return nutrition ~= nil
            and nutrition:characterHaveWeightTrouble() == true
    end
end

return Conditions
