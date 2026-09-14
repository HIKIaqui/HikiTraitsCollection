-- Hiki Traits: Just a Scratch
local Library = require "HikiTraits/Library"

HikiTraits.JustAScratch = HikiTraits.JustAScratch or {
    TRAIT_ID = "hikitraits:just_a_scratch",
}

local Trait = HikiTraits.JustAScratch
local InjuryManager = Library.InjuryManager

InjuryManager.registerRule({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    priority = InjuryManager.PRIORITY.PREVENTION,
    injuries = "cut",
    action = "replace",
    replacement = "scratch",
    -- This is a worsening of the original injury, not a defense. Preserve a
    -- Knox Infection already caused by the incoming scratch.
    infectionPolicy = InjuryManager.INFECTION_POLICY.CURRENT,
})
