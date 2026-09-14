-- Hiki Traits Library
-- Loads reusable gameplay-domain systems without installing dormant hooks.

require "HikiTraits/Library/Core"

HikiTraits.Library.Systems = HikiTraits.Library.Systems or {}

local Library = HikiTraits.Library
local Systems = Library.Systems

require "HikiTraits/Library/Systems/TimedActionManager"
require "HikiTraits/Library/Systems/ConsumptionManager"
require "HikiTraits/Library/Systems/ClothingManager"
require "HikiTraits/Library/Systems/NutritionManager"
require "HikiTraits/Library/Systems/ModifierManager"
require "HikiTraits/Library/Systems/InjuryManager"

-- Short public aliases keep trait definition files readable.
Library.TimedActionManager = Systems.TimedActionManager
Library.ConsumptionManager = Systems.ConsumptionManager
Library.ClothingManager = Systems.ClothingManager
Library.NutritionManager = Systems.NutritionManager
Library.ModifierManager = Systems.ModifierManager
Library.InjuryManager = Systems.InjuryManager

return Systems
