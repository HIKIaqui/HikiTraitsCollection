-- Hiki Traits
-- Selective Eater runtime behavior for Project Zomboid B42.20.

local Library = require "HikiTraits/Library"

HikiTraits = HikiTraits or {}
HikiTraits.SelectiveEater = HikiTraits.SelectiveEater or {}

local SelectiveEater = HikiTraits.SelectiveEater

SelectiveEater.TRAIT_ID = "hikitraits:selective_eater"

-- Penalties are defined for a full item. Partial portions scale every penalty
-- proportionally. "Allowed, but..." penalties stack with each other.
SelectiveEater.UNHAPPINESS_PER_FULL_ITEM = 25
SelectiveEater.COOKWARE_UNHAPPINESS_PER_FULL_ITEM = 5
SelectiveEater.COLD_UNHAPPINESS_PER_FULL_ITEM = 8
SelectiveEater.RAW_UNHAPPINESS_PER_FULL_ITEM = 12

-- Build 42 represents normal room-temperature food around heat 1.0. A food
-- marked GoodHot at or below this value counts as being served cold.
SelectiveEater.COLD_HEAT_THRESHOLD = 1.0

-- Keeping this enabled while building the whitelist. Every consumed food will
-- print its full type and whether the trait accepted or rejected it.
SelectiveEater.DEBUG = false

-- Strict whitelist. Keys must use the complete Module.ItemID form printed by
-- food:getFullType(), such as "Base.Apple".
--
-- This starter list deliberately favors whole foods and player-made dishes.
-- Build 42 or food mods may use additional/different IDs; DEBUG output exists
-- precisely so those can be added without guessing.
SelectiveEater.ALLOWED_FOODS = {
    -- Whole fruit
    ["Base.Apple"] = true,
    ["Base.Banana"] = true,
    ["Base.Blackberry"] = true,
    ["Base.Blueberry"] = true,
    ["Base.Cherry"] = true,
    ["Base.Grapes"] = true,
    ["Base.Lemon"] = true,
    ["Base.Lime"] = true,
    ["Base.Orange"] = true,
    ["Base.Peach"] = true,
    ["Base.Pear"] = true,
    ["Base.Strawberry"] = true,
    ["Base.Grapefruit"] = true,

    -- Whole vegetables
    ["Base.Broccoli"] = true,
    ["Base.Cabbage"] = true,
    ["Base.Carrot"] = true,
    ["Base.Corn"] = true,
    ["Base.Eggplant"] = true,
    ["Base.Leek"] = true,
    ["Base.Lettuce"] = true,
    ["Base.Onion"] = true,
    ["Base.Potato"] = true,
    ["Base.RedRadish"] = true,
    ["Base.Tomato"] = true,
    ["Base.Zucchini"] = true,

    -- Almost food
    ["Base.Hotdog"] = true,
    ["Base.PancakesRecipe"] = true,
    ["Base.Pancakes"] = true,
    ["Base.PotatoPancakes"] = true,
    ["Base.IcecreamSandwich"] = true,
    ["Base.ConeIcecream"] = true,
    ["Base.ConeIcecreamToppings"] = true,

    ["Base.Burrito"] = true,
    ["Base.BurritoRecipe"] = true,
    ["Base.CakeCarrot"] = true,
    ["Base.CakeCheeseCake"] = true,
    ["Base.Pie"] = true,
    ["Base.Painauchocolat"] = true,
    ["Base.CakeChocolate"] = true,
    ["Base.DoughnutChocolate"] = true,
    ["Base.Cornbread"] = true,
    ["Base.Corndog"] = true,
    ["Base.Cupcake"] = true,
    ["Base.Danish"] = true,
    ["Base.EggPoached"] = true,
    ["Base.EggScrambled"] = true,
    ["Base.SushiEgg"] = true,
    ["Base.ShrimpFried"] = true,
    ["Base.ShrimpFriedCraft"] = true,
    ["Base.Perogies"] = true,
    ["Base.Pizza"] = true,

    ["FunctionalAppliances.FAButteredPopcorn"] = true,
    ["FunctionalAppliances.FABucketofButteredPopcorn"] = true,
    ["FunctionalAppliances.FABucketofPopcorn"] = true,
    ["FunctionalAppliances.FATheaterPopcorn"] = true,



    -- Common prepared dishes. The exact B42.20 full types should be confirmed
    -- through DEBUG output before considering this list complete.
    ["Base.Burger"] = true,
    ["Base.FruitSalad"] = true,
    ["Base.FruitSaladClay"] = true,
    ["Base.EggOmelette"] = true,
    ["Base.PastaPan"] = true,
    ["Base.RicePan"] = true,
    ["Base.RoastedVegetables"] = true,
    ["Base.Salad"] = true,
    ["Base.SaladClay"] = true,
    ["Base.Sandwich"] = true,
    ["Base.Soup"] = true,
    ["Base.Stew"] = true,
    ["Base.StewBowl"] = true,
    ["Base.StewBowlClay"] = true,
    ["Base.PotOfStew"] = true,
    ["Base.PotForgedStew"] = true,
    ["Base.NoodleSoup"] = true,
    ["Base.SoupBowl"] = true,
    ["Base.SoupBowlClay"] = true,
    ["Base.Oatmeal"] = true,
    ["Base.BeanBowl"] = true,
    ["Base.CerealBowl"] = true,
    ["Base.PastaBowl"] = true,
    ["Base.PastaBowlClay"] = true,
    ["Base.RamenBowl"] = true,
    ["Base.RiceBowl"] = true,
    ["Base.RiceBowlClay"] = true,

    

    -- DRINKS because for some reason they are triggering shit

    ["Base.HotDrinkCopper"] = true,
    ["Base.HotDrinkGold"] = true,
    ["Base.HotDrinkMetal"] = true,
    ["Base.HotDrinkSilver"] = true,
    ["Base.HotDrinkTumbler"] = true,
    ["Base.HotDrinkClay"] = true,
    ["Base.HotDrinkTea"] = true,
    ["Base.HotDrinkSpiffo"] = true,
    ["Base.HotDrink"] = true,
    ["Base.HotDrinkRed"] = true,
    ["Base.HotDrinkTeaCeramic"] = true,
    ["Base.HotDrinkWhite"] = true,
    ["Base.TestHotDrink"] = true,
}

-- Public compatibility function. Other Hiki Traits files or food-mod patches
-- can whitelist an item without editing the event handler.
function SelectiveEater.allowFood(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        return false
    end

    SelectiveEater.ALLOWED_FOODS[fullType] = true
    return true
end

local function fullPenalty(context)
    local item = context.itemSnapshot or {}
    local evolved = item.evolvedRecipeName ~= nil
        and item.evolvedRecipeName ~= ""
    local allowed = SelectiveEater.ALLOWED_FOODS[item.fullType] == true
        or evolved

    if not allowed then
        return SelectiveEater.UNHAPPINESS_PER_FULL_ITEM
    end

    local cookware = item.eatType == "Pot" or item.eatType == "PotForged"
    local penalty = cookware
        and SelectiveEater.COOKWARE_UNHAPPINESS_PER_FULL_ITEM or 0

    if item.goodHot and (tonumber(item.heat) or 0)
        <= SelectiveEater.COLD_HEAT_THRESHOLD then
        penalty = penalty + SelectiveEater.COLD_UNHAPPINESS_PER_FULL_ITEM
    end

    if (cookware or evolved) and item.cookable and not item.cooked then
        penalty = penalty + SelectiveEater.RAW_UNHAPPINESS_PER_FULL_ITEM
    end

    return penalty
end

Library.ConsumptionManager.registerRule({
    id = SelectiveEater.TRAIT_ID,
    traitId = SelectiveEater.TRAIT_ID,
    kinds = Library.ConsumptionManager.Kind.FOOD,
    effects = {
        Library.Effects.addStat(CharacterStat.UNHAPPINESS, function(context)
            return fullPenalty(context) * context.portion
        end),
    },
})
