-- Hiki Traits: Exercise Routine
local Library = require "HikiTraits/Library"

HikiTraits.ExerciseRoutine = HikiTraits.ExerciseRoutine or {
    TRAIT_ID = "hikitraits:exercise_routine",
    GRACE_HOURS = 24,
    MINIMUM_EXERCISE_HOURS = 10 / 60,
    EXERCISE_TIME_TOLERANCE_HOURS = 0.001,
    UNHAPPINESS_PER_HOUR = 1,
}
local Trait = HikiTraits.ExerciseRoutine
local TIMER_KEY = "lastExerciseHour"
local ACTION_OWNER = Trait.TRAIT_ID .. ":action"

Library.TimedActionManager.register({
    id = Trait.TRAIT_ID .. ":start",
    traitId = Trait.TRAIT_ID,
    module = "TimedActions/ISFitnessAction",
    className = "ISFitnessAction",
    method = "start",
    scope = Library.Runtime.Scope.LOCAL,
    before = function(context)
        local state = Library.TimedActionManager.getActionState(
            context.action,
            ACTION_OWNER
        )
        state.startedAt = context.worldAgeHours
    end,
})

Library.TimedActionManager.registerAuthoritative({
    id = Trait.TRAIT_ID .. ":qualifying-exercise",
    traitId = Trait.TRAIT_ID,
    module = "TimedActions/ISFitnessAction",
    className = "ISFitnessAction",
    method = "animEvent",
    whenAction = function(context)
        local event = context.arguments[1]
        if event ~= "ActiveAnimLooped" and event ~= "FitnessFinished" then
            return false
        end

        local state = Library.TimedActionManager.getActionState(
            context.action,
            ACTION_OWNER
        )
        state.startedAt = tonumber(state.startedAt) or context.worldAgeHours
        return context.worldAgeHours - state.startedAt
            + Trait.EXERCISE_TIME_TOLERANCE_HOURS
            >= Trait.MINIMUM_EXERCISE_HOURS
    end,
    onServer = function(context)
        Library.State.markWorldTime(
            context.character,
            Trait.TRAIT_ID,
            TIMER_KEY
        )
    end,
})

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
