-- Hiki Traits: Unhinged - I Can Quit
local Library = require "HikiTraits/Library"

HikiTraitsUnhinged = HikiTraitsUnhinged or {}
HikiTraitsUnhinged.ICanQuit = HikiTraitsUnhinged.ICanQuit or {
    TRAIT_ID = "hikitraitsunhinged:i_can_quit",
    GRACE_HOURS = 6,
    STAGE_HOURS = 3,
    MAX_STAGE = 4,
    BASE_STRESS_PER_MINUTE = 0.0015,
    BASE_SICKNESS_PER_MINUTE = 0.0005,
    LETHAL_STAGE = 4,
    MAX_SICKNESS_THRESHOLD = 0.999,
    HEALTH_DAMAGE_PER_MINUTE = 1.0,
    MINIMUM_ALCOHOL_DRINK_LITERS = 0.05,
    QUALIFYING_PILLS = { ["Base.PillsBeta"] = true },
}
local Trait = HikiTraitsUnhinged.ICanQuit
local TIMER_KEY = "lastUseHour"

function Trait.registerQualifyingPill(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        return false
    end

    Trait.QUALIFYING_PILLS[fullType] = true
    return true
end

Library.ConsumptionManager.registerRule({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    when = function(context)
        local item = context.itemSnapshot or {}

        if context.kind == Library.ConsumptionManager.Kind.FLUID then
            return context.liters >= Trait.MINIMUM_ALCOHOL_DRINK_LITERS
                and Library.ConsumptionManager.isAlcoholic(
                    context.fluidSnapshot
                )
        end

        if context.kind == Library.ConsumptionManager.Kind.PILL then
            return Trait.QUALIFYING_PILLS[item.fullType] == true
                or item.smokable == true
        end

        return item.smokable == true or item.alcoholic == true
    end,
    onConsume = function(context)
        Library.State.markWorldTime(
            context.character, Trait.TRAIT_ID, TIMER_KEY
        )
    end,
})

Library.Runtime.registerMinute({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    onInactive = function(context)
        Library.State.Persistent.remove(
            context.character, Trait.TRAIT_ID, TIMER_KEY
        )
    end,
    effects = function(context)
        local elapsed = Library.State.elapsedWorldHours(
            context.character, Trait.TRAIT_ID, TIMER_KEY
        )
        if elapsed < Trait.GRACE_HOURS then
            return {}
        end

        local overdue = elapsed - Trait.GRACE_HOURS
        local stage = math.max(1, math.min(
            math.floor(overdue / Trait.STAGE_HOURS) + 1,
            Trait.MAX_STAGE
        ))
        local multiplier = 2 ^ (stage - 1)
        context.withdrawalStage = stage

        return {
            Library.Effects.addStat(
                CharacterStat.STRESS,
                Trait.BASE_STRESS_PER_MINUTE * multiplier
            ),
            Library.Effects.addStat(
                CharacterStat.SICKNESS,
                Trait.BASE_SICKNESS_PER_MINUTE * multiplier
            ),
            Library.Effects.damageHealth(Trait.HEALTH_DAMAGE_PER_MINUTE, {
                when = function(effectContext)
                    return effectContext.withdrawalStage >= Trait.LETHAL_STAGE
                        and Library.Stats.get(
                            effectContext.character,
                            CharacterStat.SICKNESS
                        ) >= Trait.MAX_SICKNESS_THRESHOLD
                end,
            }),
        }
    end,
})
