-- Hiki Traits: Low Tolerance
local Library = require "HikiTraits/Library"

HikiTraits.LowTolerance = HikiTraits.LowTolerance or {
    TRAIT_ID = "hikitraits:low_tolerance",
    EXTRA_ALCOHOL_INTOXICATION_MULTIPLIER = 0.50,
    ALCOHOL_SICKNESS_MULTIPLIER = 0.15,
    SMOKING_INTOXICATION = 0.04,
    SMOKING_SICKNESS = 0.015,
}
local Trait = HikiTraits.LowTolerance

local function consumedAlcohol(context)
    local fluid = context.fluidSnapshot or {}
    local properties = fluid.properties or {}
    local alcoholPerLiter = tonumber(properties.alcohol) or 0
    local liters = math.max(0, tonumber(context.liters) or 0)

    if alcoholPerLiter > 0 and liters > 0 then
        return alcoholPerLiter * liters
    end

    local item = context.itemSnapshot or {}
    if item.alcoholic == true then
        local alcoholPower = math.max(
            0,
            tonumber(item.alcoholPower) or 0
        )
        local portion = Library.ConsumptionManager.normalizePortion(
            context.portion,
            1
        )
        return alcoholPower * portion
    end

    return 0
end

local function isSmoked(context)
    local item = context.itemSnapshot or {}
    return item.smokable == true
end

Library.ConsumptionManager.registerRule({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    when = function(context)
        return consumedAlcohol(context) > 0 or isSmoked(context)
    end,
    effects = function(context)
        local alcoholDose = consumedAlcohol(context)
        local intoxication = alcoholDose
            * Trait.EXTRA_ALCOHOL_INTOXICATION_MULTIPLIER
        local sickness = alcoholDose
            * Trait.ALCOHOL_SICKNESS_MULTIPLIER

        if isSmoked(context) then
            intoxication = intoxication + Trait.SMOKING_INTOXICATION
            sickness = sickness + Trait.SMOKING_SICKNESS
        end

        return {
            Library.Effects.addStat(
                CharacterStat.INTOXICATION,
                intoxication
            ),
            Library.Effects.addStat(
                CharacterStat.SICKNESS,
                sickness
            ),
        }
    end,
})
