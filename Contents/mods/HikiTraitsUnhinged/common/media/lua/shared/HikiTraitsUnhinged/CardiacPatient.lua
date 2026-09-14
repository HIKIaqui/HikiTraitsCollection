-- Hiki Traits: Unhinged - Cardiac Patient
local Library = require "HikiTraits/Library"

HikiTraitsUnhinged = HikiTraitsUnhinged or {}
HikiTraitsUnhinged.CardiacPatient = HikiTraitsUnhinged.CardiacPatient or {
    TRAIT_ID = "hikitraitsunhinged:cardiac_patient",
    MAX_STRESS_THRESHOLD = 0.75,
    MAX_PANIC_THRESHOLD = 75.0,
    HEALTH_DAMAGE_PER_MINUTE = 1.0,
    EXTREME_PAIN = 100.0,
}
local Trait = HikiTraitsUnhinged.CardiacPatient

Library.Runtime.registerMinute({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    when = Library.Conditions.any(
        Library.Conditions.statAtLeast(CharacterStat.STRESS, Trait.MAX_STRESS_THRESHOLD),
        Library.Conditions.statAtLeast(CharacterStat.PANIC, Trait.MAX_PANIC_THRESHOLD)
    ),
    effects = {
        Library.Effects.damageHealth(Trait.HEALTH_DAMAGE_PER_MINUTE),
        Library.Effects.setStatAtLeast(CharacterStat.PAIN, Trait.EXTREME_PAIN),
    },
})
