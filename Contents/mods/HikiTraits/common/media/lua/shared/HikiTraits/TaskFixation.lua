-- Hiki Traits: Must Finish the Job
local Library = require "HikiTraits/Library"

HikiTraits.TaskFixation = HikiTraits.TaskFixation or {
    TRAIT_ID = "hikitraits:task_fixation",
    MINIMUM_PROGRESS = 0.15,
    STRESS_PER_INTERRUPTION = 0.10,
    SERVER_COOLDOWN_MS = 250,
}
local Trait = HikiTraits.TaskFixation

Library.TimedActionManager.registerAuthoritative({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    module = "TimedActions/ISBaseTimedAction",
    className = "ISBaseTimedAction",
    method = "stop",
    cooldownMs = Trait.SERVER_COOLDOWN_MS,
    whenAction = function(context)
        return context.progress >= Trait.MINIMUM_PROGRESS
    end,
    validate = function(_, args)
        local progress = tonumber(args and args.progress) or 0
        return progress >= Trait.MINIMUM_PROGRESS and progress <= 1
    end,
    effects = {
        Library.Effects.addStat(CharacterStat.STRESS, Trait.STRESS_PER_INTERRUPTION),
    },
})
