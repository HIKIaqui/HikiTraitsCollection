-- Hiki Traits: Fumbles Under Pressure
local Library = require "HikiTraits/Library"

HikiTraits.PanicFumbling = HikiTraits.PanicFumbling or {
    TRAIT_ID = "hikitraits:panic_fumbling",
    MAX_FAILURE_CHANCE = 0.30,
    PANIC_EXPONENT = 2,
    MINIMUM_ENDURANCE_LOSS = 0.00001,
    BANDAGE_SYNC_MASK = 0xc001966b8e,
    STITCH_SYNC_MASK = 0x00570188,
}
local Trait = HikiTraits.PanicFumbling

local function collectTreatments(character)
    local treatments = {}
    local parts = character:getBodyDamage():getBodyParts()

    for index = 0, parts:size() - 1 do
        local part = parts:get(index)
        if part:bandaged() then
            treatments[#treatments + 1] = { kind = "bandage", part = part }
        end
        if part:stitched() then
            treatments[#treatments + 1] = { kind = "stitch", part = part }
        end
    end

    return treatments
end

local function failTreatment(character, treatments)
    local treatment = treatments[ZombRand(#treatments) + 1]

    if treatment.kind == "bandage" then
        character:getBodyDamage():SetBandaged(
            treatment.part:getIndex(), false, 0, false, nil
        )
        if type(syncBodyPart) == "function" then
            syncBodyPart(treatment.part, Trait.BANDAGE_SYNC_MASK)
        end
    else
        treatment.part:setStitched(false)
        if type(syncBodyPart) == "function" then
            syncBodyPart(treatment.part, Trait.STITCH_SYNC_MASK)
        end
    end
end

Library.Runtime.registerMinute({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    onInactive = function(context)
        Library.State.Session.remove(
            context.character, Trait.TRAIT_ID, "previousEndurance"
        )
    end,
    run = function(context)
        local endurance = Library.Stats.get(
            context.character, CharacterStat.ENDURANCE
        )
        local previous = Library.State.Session.get(
            context.character, Trait.TRAIT_ID, "previousEndurance"
        )
        Library.State.Session.set(
            context.character, Trait.TRAIT_ID, "previousEndurance", endurance
        )

        if previous == nil
            or previous - endurance < Trait.MINIMUM_ENDURANCE_LOSS then
            return
        end

        local panic = Library.Util.clamp(
            Library.Stats.get(context.character, CharacterStat.PANIC), 0, 100
        )
        local treatments = collectTreatments(context.character)
        if panic <= 0 or #treatments == 0 then
            return
        end

        local chance = Trait.MAX_FAILURE_CHANCE
            * ((panic / 100) ^ Trait.PANIC_EXPONENT)
        if ZombRand(100000) < math.floor(chance * 100000 + 0.5) then
            failTreatment(context.character, treatments)
        end
    end,
})
