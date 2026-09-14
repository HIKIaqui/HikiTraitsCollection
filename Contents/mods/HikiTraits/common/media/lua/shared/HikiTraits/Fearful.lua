-- Hiki Traits: Fearful
local Library = require "HikiTraits/Library"

HikiTraits.Fearful = HikiTraits.Fearful or {
    TRAIT_ID = "hikitraits:fearful",
    SCAN_INTERVAL_MS = 100,
    TRIGGER_PANIC_LEVEL = 4,
    REARM_PANIC_LEVEL = 1,
    WETNESS = 100,
    VOICE_SOUND = "ShoutHey",
    WORLD_SOUND_RADIUS = 25,
    WORLD_SOUND_VOLUME = 25,
}
local Trait = HikiTraits.Fearful
local COMMAND = Trait.TRAIT_ID .. ":voice"
local lowerClothing = Library.ClothingManager.selectorByCoveredParts({
    BodyPartType.Groin,
})

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

Library.Triggers.registerHigh({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    intervalMs = Trait.SCAN_INTERVAL_MS,
    stateMode = "persistent",
    read = function(context)
        return context.character:getMoodles():getMoodleLevel(
            MoodleType.PANIC
        )
    end,
    triggerAt = Trait.TRIGGER_PANIC_LEVEL,
    rearmAt = Trait.REARM_PANIC_LEVEL,
    rearmInclusive = false,
    onTrigger = function(context)
        Library.ClothingManager.setWornWetness(
            context.character,
            Trait.WETNESS,
            lowerClothing
        )

        context.character:addWorldSoundUnlessInvisible(
            Trait.WORLD_SOUND_RADIUS,
            Trait.WORLD_SOUND_VOLUME,
            false
        )
        Library.Network.sendToClient(context.character, COMMAND, {})
    end,
})
