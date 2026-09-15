-- Hiki Traits: Weight Anxiety
local Library = require "HikiTraits/Library"

HikiTraits.WeightAnxiety = HikiTraits.WeightAnxiety or {
    TRAIT_ID = "hikitraits:weight_anxiety",
    STRESS_PER_MINUTE = 0.004,
}
local Trait = HikiTraits.WeightAnxiety

Library.NutritionManager.registerRule({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    scope = Library.Runtime.Scope.LOCAL,
    weightTrouble = true,
    effects = {
        Library.Effects.addStat(CharacterStat.STRESS, Trait.STRESS_PER_MINUTE),
    },
})
