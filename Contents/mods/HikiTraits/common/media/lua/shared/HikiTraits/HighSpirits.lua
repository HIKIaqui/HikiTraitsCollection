-- Hiki Traits: High Spirits
local Library = require "HikiTraits/Library"

HikiTraits.HighSpirits = HikiTraits.HighSpirits or {
    TRAIT_ID = "hikitraits:high_spirits",
    MAX_UNHAPPINESS = 1.0,
    EXTRA_ENDURANCE_PER_MINUTE = 0.005,
}
local Trait = HikiTraits.HighSpirits

Library.Runtime.registerMinute({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    when = Library.Conditions.statBelow(CharacterStat.UNHAPPINESS, Trait.MAX_UNHAPPINESS),
    effects = {
        Library.Effects.addStat(CharacterStat.ENDURANCE, Trait.EXTRA_ENDURANCE_PER_MINUTE),
    },
})
