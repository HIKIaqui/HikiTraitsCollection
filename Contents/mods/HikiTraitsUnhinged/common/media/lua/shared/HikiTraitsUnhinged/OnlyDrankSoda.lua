-- Hiki Traits: Unhinged - Only Drank Soda
local Library = require "HikiTraits/Library"

HikiTraitsUnhinged = HikiTraitsUnhinged or {}
HikiTraitsUnhinged.OnlyDrankSoda = HikiTraitsUnhinged.OnlyDrankSoda or {
    TRAIT_ID = "hikitraitsunhinged:only_drank_soda",
    REFERENCE_DRINK_LITERS = 0.12,
    STRESS_PER_REFERENCE_DRINK = 0.2,
    UNHAPPINESS_PER_REFERENCE_DRINK = 20.00,
}
local Trait = HikiTraitsUnhinged.OnlyDrankSoda

Library.ConsumptionManager.registerRule({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    kinds = Library.ConsumptionManager.Kind.FLUID,
    when = function(context)
        return Library.ConsumptionManager.isPlainWater(context.fluidSnapshot)
    end,
    effects = function(context)
        local units = context.liters / Trait.REFERENCE_DRINK_LITERS
        return {
            Library.Effects.addStat(CharacterStat.STRESS, Trait.STRESS_PER_REFERENCE_DRINK * units),
            Library.Effects.addStat(CharacterStat.UNHAPPINESS, Trait.UNHAPPINESS_PER_REFERENCE_DRINK * units),
        }
    end,
})
