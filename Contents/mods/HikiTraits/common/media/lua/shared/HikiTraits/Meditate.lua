-- Hiki Traits: Meditate
local Library = require "HikiTraits/Library"

HikiTraits.Meditate = HikiTraits.Meditate or {
    TRAIT_ID = "hikitraits:meditate",
    STRESS_RECOVERY_PER_MINUTE = 0.015,
    PANIC_RECOVERY_PER_MINUTE = 1.5,
}
local Trait = HikiTraits.Meditate

Library.Runtime.registerMinute({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    when = Library.Conditions.sitting(),
    effects = {
        Library.Effects.removeStat(CharacterStat.STRESS, Trait.STRESS_RECOVERY_PER_MINUTE),
        Library.Effects.removeStat(CharacterStat.PANIC, Trait.PANIC_RECOVERY_PER_MINUTE),
    },
})
