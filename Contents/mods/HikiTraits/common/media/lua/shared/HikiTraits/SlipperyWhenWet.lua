-- Hiki Traits: Slippery When Wet
local Library = require "HikiTraits/Library"

HikiTraits.SlipperyWhenWet = HikiTraits.SlipperyWhenWet or {
    TRAIT_ID = "hikitraits:slippery_when_wet",
    SCRATCH_PROTECTION_LEVEL = 1,
    CUT_PROTECTION_LEVEL = 2,
    BITE_PROTECTION_LEVEL = 4,
}

local Trait = HikiTraits.SlipperyWhenWet
local InjuryManager = Library.InjuryManager

local function getProtectedInjuries(context)
    local wetnessLevel = context.character:getMoodles():getMoodleLevel(
        MoodleType.WET
    )
    local protected = {}

    if wetnessLevel >= Trait.SCRATCH_PROTECTION_LEVEL
        and InjuryManager.hasNewInjury(context, "scratch") then
        protected[#protected + 1] = "scratch"
    end

    if wetnessLevel >= Trait.CUT_PROTECTION_LEVEL
        and InjuryManager.hasNewInjury(context, "cut") then
        protected[#protected + 1] = "cut"
    end

    if wetnessLevel >= Trait.BITE_PROTECTION_LEVEL
        and InjuryManager.hasNewInjury(context, "bite") then
        protected[#protected + 1] = "bite"
    end

    return protected
end

InjuryManager.registerHandler({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    priority = InjuryManager.PRIORITY.PREVENTION,
    evaluate = function(context)
        local protected = getProtectedInjuries(context)
        if #protected == 0 then
            return nil
        end

        return InjuryManager.decisionRemove(protected, {
            -- A prevented bite never happened, so its Knox Infection roll is
            -- rewound together with the injury whenever this handler applies.
            infectionPolicy = InjuryManager.INFECTION_POLICY.PREVIOUS,
        })
    end,
})
