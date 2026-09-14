-- Hiki Traits: Meat Fueled
local Library = require "HikiTraits/Library"

HikiTraits.MeatFueled = HikiTraits.MeatFueled or {
    TRAIT_ID = "hikitraits:meat_fueled",
    ENDURANCE_PER_FULL_ITEM = 0.25,
    FRESH_MEATS = {
        ["Base.Beef"] = true,
        ["Base.Steak"] = true,
        ["Base.Pork"] = true,
        ["Base.PorkChop"] = true,
        ["Base.Venison"] = true,
        ["Base.ChickenWhole"] = true,
        ["Base.ChickenFillet"] = true,
        ["Base.Chicken"] = true,
        ["Base.ChickenWings"] = true,
        ["Base.ChickenFoot"] = true,
        ["Base.Ham"] = true,
        ["Base.HamSlice"] = true,
        ["Base.Smallbirdmeat"] = true,
        ["Base.MeatPatty"] = true,
        ["Base.FrogMeat"] = true,
        ["Base.MincedMeat"] = true,
        ["Base.Rabbitmeat"] = true,
        ["Base.Smallanimalmeat"] = true,
        ["Base.CompanionDogsDogMeat"] = true,
        ["Base.CompanionCatCatMeat"] = true,
        ["Base.QolcCorpseFlesh"] = true,
    },
}

local Trait = HikiTraits.MeatFueled

function Trait.registerFreshMeat(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        return false
    end

    Trait.FRESH_MEATS[fullType] = true
    return true
end

Library.ConsumptionManager.registerRule({
    id = Trait.TRAIT_ID,
    traitId = Trait.TRAIT_ID,
    kinds = Library.ConsumptionManager.Kind.FOOD,
    when = function(context)
        local item = context.itemSnapshot or {}
        return Trait.FRESH_MEATS[item.fullType] == true
            and item.fresh == true
            and item.frozen ~= true
            and item.burnt ~= true
    end,
    effects = {
        Library.Effects.addStat(CharacterStat.ENDURANCE, function(context)
            return Trait.ENDURANCE_PER_FULL_ITEM * context.portion
        end),
    },
})
