-- Hiki Traits: Thrill Seeker
local Library = require "HikiTraits/Library"

HikiTraits.ThrillSeeker = HikiTraits.ThrillSeeker or {
    TRAIT_ID = "hikitraits:thrill_seeker",
    PANIC_THRESHOLD = 50,
    STRESS_THRESHOLD = 0.50,
    GRACE_HOURS = 1,
    UNHAPPINESS_PER_MINUTE = 0.1,
}
local Trait = HikiTraits.ThrillSeeker
local TIMER_KEY = "lastExcitementHour"

Library.Runtime.registerMinute({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    run = function(context)
        local panic = Library.Stats.get(context.character, CharacterStat.PANIC)
        local stress = Library.Stats.get(context.character, CharacterStat.STRESS)

        if panic >= Trait.PANIC_THRESHOLD
            or stress >= Trait.STRESS_THRESHOLD then
            Library.State.markWorldTime(
                context.character,
                Trait.TRAIT_ID,
                TIMER_KEY
            )
            return
        end

        if Library.State.elapsedWorldHours(
            context.character,
            Trait.TRAIT_ID,
            TIMER_KEY
        ) >= Trait.GRACE_HOURS then
            Library.Effects.apply(context.character, {
                Library.Effects.addStat(
                    CharacterStat.UNHAPPINESS,
                    Trait.UNHAPPINESS_PER_MINUTE
                ),
            }, context)
        end
    end,
})
