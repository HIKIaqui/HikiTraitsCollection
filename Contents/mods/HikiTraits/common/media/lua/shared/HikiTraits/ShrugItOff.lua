-- Hiki Traits: Shrug It Off
local Library = require "HikiTraits/Library"

HikiTraits.ShrugItOff = HikiTraits.ShrugItOff or {
    TRAIT_ID = "hikitraits:shrug_it_off",
    SCAN_INTERVAL_MS = 100,
    TARGET_PAIN_FRACTION = 0.50,
    REARM_PAIN_THRESHOLD = 1.0,
}
local Trait = HikiTraits.ShrugItOff

Library.Triggers.registerStatHigh({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    stat = CharacterStat.PAIN,
    atMaximum = true,
    rearmAt = Trait.REARM_PAIN_THRESHOLD,
    rearmInclusive = false,
    intervalMs = Trait.SCAN_INTERVAL_MS,
    stateMode = "persistent",
    effects = {
        Library.Effects.setStat(CharacterStat.PAIN, function()
            local _, maximum = Library.Stats.getBounds(CharacterStat.PAIN)
            return maximum * Trait.TARGET_PAIN_FRACTION
        end),
    },
})
