-- Hiki Traits: Exhaustion Anxiety
local Library = require "HikiTraits/Library"

HikiTraits.ExhaustionAnxiety = HikiTraits.ExhaustionAnxiety or {
    TRAIT_ID = "hikitraits:exhaustion_anxiety",
    STRESS_PER_MINUTE = { [1] = 0.010, [2] = 0.020, [3] = 0.030, [4] = 0.050 },
    PANIC_PER_MINUTE = { [1] = 0.00, [2] = 2.50, [3] = 5.00, [4] = 10.00 },
}
local Trait = HikiTraits.ExhaustionAnxiety

Library.Runtime.registerMinute({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    effects = function(context)
        local level = context.character:getMoodles():getMoodleLevel(MoodleType.ENDURANCE)
        return {
            Library.Effects.addStat(CharacterStat.STRESS, Trait.STRESS_PER_MINUTE[level] or 0),
            Library.Effects.addStat(CharacterStat.PANIC, Trait.PANIC_PER_MINUTE[level] or 0),
        }
    end,
})
