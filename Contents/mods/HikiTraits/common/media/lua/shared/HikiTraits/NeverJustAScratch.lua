-- Hiki Traits: Never Just a Scratch
local Library = require "HikiTraits/Library"

HikiTraits.NeverJustAScratch = HikiTraits.NeverJustAScratch or {
    TRAIT_ID = "hikitraits:never_just_a_scratch",
}

local Trait = HikiTraits.NeverJustAScratch
local InjuryManager = Library.InjuryManager

InjuryManager.registerRule({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    priority = InjuryManager.PRIORITY.WORSENING,
    injuries = "scratch",
    action = "replace",
    replacement = "cut",
    -- This is a worsening of the original injury, not a defense. Preserve a
    -- Knox Infection already caused by the incoming scratch.
    infectionPolicy = InjuryManager.INFECTION_POLICY.CURRENT,
})
