-- Hiki Traits: Unhinged - Ear Ringing
local Library = require "HikiTraits/Library"

HikiTraitsUnhinged = HikiTraitsUnhinged or {}
HikiTraitsUnhinged.EarRinging = HikiTraitsUnhinged.EarRinging or {
    TRAIT_ID = "hikitraitsunhinged:ear_ringing",
    SOUND_ID = "HikiTraitsEarRinging",
    HEARING_PROTECTORS = {
        ["Base.Hat_EarMuff_Protectors"] = true,
        ["Base.Hat_EarMuffs"] = true,
    },
    _soundByPlayer = {},
}
local Trait = HikiTraitsUnhinged.EarRinging
local PROTECTOR_GROUP = Trait.TRAIT_ID .. ":protectors"

Library.ClothingManager.registerGroup(PROTECTOR_GROUP, Trait.HEARING_PROTECTORS)

function Trait.registerHearingProtector(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        return false
    end

    Trait.HEARING_PROTECTORS[fullType] = true
    return Library.ClothingManager.addToGroup(PROTECTOR_GROUP, fullType)
end

Library.Runtime.registerEvent("OnWeaponSwingHitPoint", {
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    scope = Library.Runtime.Scope.LOCAL,
    when = function(context)
        local weapon = context.arguments[2]
        return weapon ~= nil and weapon:isAimedFirearm()
            and not Library.ClothingManager.hasWornGroup(
                context.character, PROTECTOR_GROUP
            )
    end,
    run = function(context)
        local playerNumber = context.character:getPlayerNum()
        local soundManager = getSoundManager()
        local previous = Trait._soundByPlayer[playerNumber]

        if previous ~= nil and soundManager:isPlayingUISound(previous) then
            soundManager:stopUISound(previous)
        end

        Trait._soundByPlayer[playerNumber] = soundManager:playUISound(Trait.SOUND_ID)
    end,
})
