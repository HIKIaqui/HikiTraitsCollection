-- Hiki Traits: Bitten? No.
local Library = require "HikiTraits/Library"

HikiTraits.BittenNo = HikiTraits.BittenNo or { TRAIT_ID = "hikitraits:bitten_no" }
local Trait = HikiTraits.BittenNo

Library.InjuryManager.registerRule({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    priority = Library.InjuryManager.PRIORITY.LIMITED_DEFENSE,
    once = true,
    injuries = "bite",
    action = "replace",
    replacement = "cut",
    infectionPolicy = Library.InjuryManager.INFECTION_POLICY.PREVIOUS,
})
