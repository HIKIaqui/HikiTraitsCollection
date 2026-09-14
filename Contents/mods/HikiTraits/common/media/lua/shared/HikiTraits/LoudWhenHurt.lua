-- Hiki Traits: Loud When Hurt
local Library = require "HikiTraits/Library"

HikiTraits.LoudWhenHurt = HikiTraits.LoudWhenHurt or {
    TRAIT_ID = "hikitraits:loud_when_hurt",
    SCREAM_COOLDOWN_MS = 3000,
    VOICE_SOUND = "ShoutHey",
    WORLD_SOUND_RADIUS = 25,
    WORLD_SOUND_VOLUME = 25,
}
local Trait = HikiTraits.LoudWhenHurt
local COMMAND = Trait.TRAIT_ID .. ":voice"

Library.Network.registerClientHandler({
    id = COMMAND,
    traitId = Trait.TRAIT_ID,
    handle = function(context)
        if context.isSingleplayer then
            context.character:playerVoiceSound(Trait.VOICE_SOUND)
        else
            context.character:transmitPlayerVoiceSound(Trait.VOICE_SOUND)
        end
    end,
})

Library.InjuryManager.registerObserver({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    priority = 900,
    when = function(_, outcome)
        return outcome == nil or #outcome.resultingInjuries > 0
    end,
    observe = function(context, outcome)
        if outcome ~= nil and #outcome.resultingInjuries == 0 then
            return
        end

        if not Library.State.isCooldownReady(
            context.character,
            Trait.TRAIT_ID,
            "scream",
            Trait.SCREAM_COOLDOWN_MS,
            context.nowMs
        ) then
            return
        end

        Library.State.consumeCooldown(
            context.character, Trait.TRAIT_ID, "scream", context.nowMs
        )
        context.character:addWorldSoundUnlessInvisible(
            Trait.WORLD_SOUND_RADIUS,
            Trait.WORLD_SOUND_VOLUME,
            false
        )
        Library.Network.sendToClient(context.character, COMMAND, {})
    end,
})
