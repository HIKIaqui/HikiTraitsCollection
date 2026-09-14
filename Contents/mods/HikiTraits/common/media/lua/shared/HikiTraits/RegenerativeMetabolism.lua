-- Hiki Traits: Regenerative Metabolism
local Library = require "HikiTraits/Library"

HikiTraits.RegenerativeMetabolism = HikiTraits.RegenerativeMetabolism or {
    TRAIT_ID = "hikitraits:regenerative_metabolism",
    MINIMUM_CALORIES = 500,
    MINIMUM_WEIGHT = 60,
    HEALTH_PER_MINUTE = 0.25,
    CALORIES_PER_MINUTE = 5,
    WEIGHT_PER_MINUTE = 0.001,
    FULL_HEALTH = 100,
}
local Trait = HikiTraits.RegenerativeMetabolism

local function getOverallHealth(character)
    if character == nil then
        return nil
    end

    local bodyDamage = character:getBodyDamage()
    if bodyDamage == nil then
        return nil
    end

    local succeeded, health = pcall(function()
        return bodyDamage:getOverallBodyHealth()
    end)

    if not succeeded then
        return nil
    end

    return tonumber(health)
end

Library.NutritionManager.registerRule({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    metric = "calories",
    minimum = Trait.MINIMUM_CALORIES,
    when = function(context)
        local nutrition = context.nutrition or {}
        local weight = tonumber(nutrition.weight)
        local health = getOverallHealth(context.character)

        return weight ~= nil
            and weight > Trait.MINIMUM_WEIGHT
            and health ~= nil
            and health < Trait.FULL_HEALTH
    end,
    run = function(context)
        local healed = Library.Stats.healHealth(
            context.character,
            Trait.HEALTH_PER_MINUTE,
            { sync = false }
        )

        -- Resources are spent only when health actually changed. Being at
        -- full health therefore cannot silently devour the survivor's lunch.
        if not healed.changed then
            return healed
        end

        local calories = Library.NutritionManager.change(
            context.character,
            "calories",
            -Trait.CALORIES_PER_MINUTE,
            { sync = false }
        )
        local weight = Library.NutritionManager.changeWeight(
            context.character,
            -Trait.WEIGHT_PER_MINUTE,
            { sync = false }
        )

        Library.Stats.syncDamage(context.character)
        if calories.changed or weight.changed then
            Library.NutritionManager.sync(context.character)
        end

        return {
            healing = healed,
            calories = calories,
            weight = weight,
        }
    end,
})
