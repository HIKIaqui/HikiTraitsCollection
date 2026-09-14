-- Hiki Traits: Neck Reflex
local Library = require "HikiTraits/Library"

HikiTraits.NeckReflex = HikiTraits.NeckReflex or {
    TRAIT_ID = "hikitraits:neck_reflex",
    MINIMUM_ENDURANCE = 0.75,
    ENDURANCE_COST = 0.50,
}
local Trait = HikiTraits.NeckReflex

Library.InjuryManager.registerRule({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    priority = Library.InjuryManager.PRIORITY.LOCATION_DEFENSE,
    bodyPart = BodyPartType.Neck,
    injuries = { "scratch", "cut", "bite", "deepWound" },
    triggerInjuries = { "cut", "bite", "deepWound" },
    action = "replace",
    replacement = "scratch",
    infectionPolicy = Library.InjuryManager.INFECTION_POLICY.PREVIOUS,
    when = function(context)
        return Library.Stats.get(context.character, CharacterStat.ENDURANCE)
            > Trait.MINIMUM_ENDURANCE
    end,
    effects = {
        Library.Effects.removeStat(CharacterStat.ENDURANCE, Trait.ENDURANCE_COST),
    },
})
