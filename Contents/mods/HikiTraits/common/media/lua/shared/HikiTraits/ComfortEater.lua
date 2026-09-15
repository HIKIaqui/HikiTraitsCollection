-- Hiki Traits: Comfort Eater
local Library = require "HikiTraits/Library"

HikiTraits.ComfortEater = HikiTraits.ComfortEater or {
    TRAIT_ID = "hikitraits:comfort_eater",
    STRESS_RELIEF_PER_FULL_ITEM = 0.075,
}
local Trait = HikiTraits.ComfortEater

Library.ConsumptionManager.registerRule({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    kinds = Library.ConsumptionManager.Kind.FOOD,
    when = function(context)
        local item = context.itemSnapshot or {}
        return item.smokable ~= true
    end,
    effects = {
        Library.Effects.removeStat(CharacterStat.STRESS, function(context)
            return Trait.STRESS_RELIEF_PER_FULL_ITEM * context.portion
        end),
    },
})
