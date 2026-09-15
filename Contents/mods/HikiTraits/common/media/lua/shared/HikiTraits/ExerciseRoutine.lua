-- Hiki Traits: Exercise Routine
local Library = require "HikiTraits/Library"

HikiTraits.ExerciseRoutine = HikiTraits.ExerciseRoutine or {
    TRAIT_ID = "hikitraits:exercise_routine",
    GRACE_HOURS = 24,
    MINIMUM_EXERCISE_HOURS = 10 / 60,
    EXERCISE_TIME_TOLERANCE_HOURS = 0.001,
    SERVER_COOLDOWN_MS = 1000,
    UNHAPPINESS_PER_HOUR = 10,
}
local Trait = HikiTraits.ExerciseRoutine
local TIMER_KEY = "lastExerciseHour"
local ACTION_OWNER = Trait.TRAIT_ID .. ":action"
local COMMAND = Trait.TRAIT_ID .. ":completed-exercise"

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

local function exerciseDurationHours(context)
    local state = Library.TimedActionManager.getActionState(
        context.action,
        ACTION_OWNER
    )
    state.startedAt = tonumber(state.startedAt) or context.worldAgeHours

    return math.max(0, context.worldAgeHours - state.startedAt)
end

local function registerExerciseEndHook(id, method, afterWhen)
    Library.TimedActionManager.registerAuthoritative({
        id = Trait.TRAIT_ID .. ":" .. id,
        command = COMMAND,
        traitId = Trait.TRAIT_ID,
        module = "TimedActions/ISFitnessAction",
        className = "ISFitnessAction",
        method = method,
        cooldownMs = Trait.SERVER_COOLDOWN_MS,
        whenAction = function(context)
            return exerciseDurationHours(context)
                + Trait.EXERCISE_TIME_TOLERANCE_HOURS
                >= Trait.MINIMUM_EXERCISE_HOURS
        end,
        afterWhen = afterWhen,
        payload = function(context)
            return {
                durationHours = exerciseDurationHours(context),
            }
        end,
        validate = function(_, args)
            return tonumber(args and args.durationHours) ~= nil
                and tonumber(args.durationHours)
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
end

-- B42 ends fitness actions through stop() when their own exercise timer
-- expires. complete() is also observed as a compatibility fallback for other
-- timed-action paths and mods. Both share one server command/cooldown, so the
-- same session can never reset the routine twice.
registerExerciseEndHook("stop", "stop")
registerExerciseEndHook("complete", "complete", function(context)
    return context.completed == true
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
