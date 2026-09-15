-- Hiki Traits: Balanced Diet
local Library = require "HikiTraits/Library"

HikiTraits.BalancedDiet = HikiTraits.BalancedDiet or {
    TRAIT_ID = "hikitraits:balanced_diet",
    MINIMUM_PROTEINS = 100,
    MINIMUM_CARBOHYDRATES = 100,
    CARRY_CAPACITY_BONUS = 0.20,
    ENDURANCE_PER_MINUTE = 0.01,
}
local Trait = HikiTraits.BalancedDiet

-- Protein supplies the physical half of the trait. ModifierManager removes
-- only this source when protein falls below the threshold and preserves every
-- vanilla or third-party capacity modifier.
Library.ModifierManager.registerSource({
    id = Trait.TRAIT_ID .. ":protein-capacity",
    traitId = Trait.TRAIT_ID,
    channel = "maxWeightDelta",
    value = Trait.CARRY_CAPACITY_BONUS,
    when = Library.NutritionManager.atLeast(
        "proteins",
        Trait.MINIMUM_PROTEINS
    ),
})

-- Carbohydrates supply the energy half independently. Having enough of both
-- nutrients activates both bonuses while still keeping a single selectable
-- trait.
Library.NutritionManager.registerRule({
    id = Trait.TRAIT_ID .. ":carbohydrate-endurance",
    traitId = Trait.TRAIT_ID,
    metric = "carbohydrates",
    minimum = Trait.MINIMUM_CARBOHYDRATES,
    effects = {
        Library.Effects.addStat(
            CharacterStat.ENDURANCE,
            Trait.ENDURANCE_PER_MINUTE
        ),
    },
})
