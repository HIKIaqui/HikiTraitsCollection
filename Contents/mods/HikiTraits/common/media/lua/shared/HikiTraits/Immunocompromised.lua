-- Hiki Traits: Immunocompromised
local Library = require "HikiTraits/Library"

HikiTraits.Immunocompromised = HikiTraits.Immunocompromised or {
    TRAIT_ID = "hikitraits:immunocompromised",
    GRACE_HOURS = 48,
    STAGE_HOURS = 24,
    MAX_STAGE = 4,
    BASE_SICKNESS_PER_MINUTE = 0.0001,
    QUALIFYING_ANTIBIOTICS = {
        ["Base.Antibiotics"] = true,
    },
}
local Trait = HikiTraits.Immunocompromised
local TIMER_KEY = "lastAntibioticHour"

function Trait.registerQualifyingAntibiotic(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        return false
    end

    Trait.QUALIFYING_ANTIBIOTICS[fullType] = true
    return true
end

Library.ConsumptionManager.registerRule({
    id = Trait.TRAIT_ID .. ":antibiotic",
    traitId = Trait.TRAIT_ID,
    kinds = {
        Library.ConsumptionManager.Kind.FOOD,
        Library.ConsumptionManager.Kind.PILL,
    },
    when = function(context)
        local item = context.itemSnapshot or {}
        local fullType = item.fullType or context.fullType
        return Trait.QUALIFYING_ANTIBIOTICS[fullType] == true
    end,
    onConsume = function(context)
        Library.State.markWorldTime(
            context.character,
            Trait.TRAIT_ID,
            TIMER_KEY
        )
    end,
})

Library.Runtime.registerMinute({
    id = Trait.TRAIT_ID .. ":sickness",
    traitId = Trait.TRAIT_ID,
    onInactive = function(context)
        Library.State.Persistent.remove(
            context.character,
            Trait.TRAIT_ID,
            TIMER_KEY
        )
    end,
    effects = function(context)
        local elapsed = Library.State.elapsedWorldHours(
            context.character,
            Trait.TRAIT_ID,
            TIMER_KEY
        )

        if elapsed < Trait.GRACE_HOURS then
            return {}
        end

        local overdue = elapsed - Trait.GRACE_HOURS
        local stage = math.max(1, math.min(
            math.floor(overdue / Trait.STAGE_HOURS) + 1,
            Trait.MAX_STAGE
        ))
        context.immunocompromisedStage = stage

        return {
            Library.Effects.addStat(
                CharacterStat.SICKNESS,
                Trait.BASE_SICKNESS_PER_MINUTE * stage
            ),
        }
    end,
})
