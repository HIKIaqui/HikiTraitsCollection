-- Hiki Traits: Road Tripper
local Library = require "HikiTraits/Library"

HikiTraits.RoadTripper = HikiTraits.RoadTripper or {
    TRAIT_ID = "hikitraits:road_tripper",
    STRESS_REDUCTION_PER_MINUTE = 0.0075,
    UNHAPPINESS_REDUCTION_PER_MINUTE = 0.5,
    MINIMUM_SPEED_KMH = 5,
}
local Trait = HikiTraits.RoadTripper

Library.Runtime.registerMinute({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    when = function(context)
        local vehicle = context.character:getVehicle()
        return vehicle ~= nil and vehicle:getDriver() == context.character
            and vehicle:getCurrentAbsoluteSpeedKmHour() >= Trait.MINIMUM_SPEED_KMH
    end,
    effects = {
        Library.Effects.removeStat(CharacterStat.STRESS, Trait.STRESS_REDUCTION_PER_MINUTE),
        Library.Effects.removeStat(CharacterStat.UNHAPPINESS, Trait.UNHAPPINESS_REDUCTION_PER_MINUTE),
    },
})
