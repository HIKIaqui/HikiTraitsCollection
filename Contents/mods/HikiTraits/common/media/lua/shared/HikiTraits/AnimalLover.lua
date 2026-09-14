-- Hiki Traits: Animal Lover
local Library = require "HikiTraits/Library"

HikiTraits.AnimalLover = HikiTraits.AnimalLover or {
    TRAIT_ID = "hikitraits:animal_lover",
    GRACE_HOURS = 24,
    UNHAPPINESS_PER_HOUR = 10,
}
local Trait = HikiTraits.AnimalLover
local TIMER_KEY = "lastPetHour"
local COMMAND = Trait.TRAIT_ID .. ":pet"

local function recordPetting(context)
    Library.State.markWorldTime(context.character, Trait.TRAIT_ID, TIMER_KEY)
end

local function registerPetHook(id, method, whenAction, afterWhen)
    Library.TimedActionManager.registerAuthoritative({
        id = Trait.TRAIT_ID .. ":" .. id,
        command = COMMAND,
        traitId = Trait.TRAIT_ID,
        module = "TimedActions/Animals/ISPetAnimal",
        className = "ISPetAnimal",
        method = method,
        cooldownMs = 1000,
        whenAction = whenAction,
        afterWhen = afterWhen,
        onServer = recordPetting,
    })
end

registerPetHook("complete", "complete", nil, function(context)
    return context.completed == true
end)
registerPetHook("animation", "animEvent", function(context)
    return context.arguments[1] == "pettingFinished"
end)

Library.Runtime.registerHour({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    when = function(context)
        return Library.State.elapsedWorldHours(
            context.character,
            Trait.TRAIT_ID,
            TIMER_KEY
        ) >= Trait.GRACE_HOURS
    end,
    effects = {
        Library.Effects.addStat(CharacterStat.UNHAPPINESS, Trait.UNHAPPINESS_PER_HOUR),
    },
})
