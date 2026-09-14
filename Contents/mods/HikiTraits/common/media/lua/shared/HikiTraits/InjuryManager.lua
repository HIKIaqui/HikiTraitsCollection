-- Hiki Traits compatibility facade.
-- Existing trait scripts keep this stable require path while the actual
-- implementation lives with the rest of the reusable systems.

require "HikiTraits/Library/Systems/InjuryManager"

HikiTraits.InjuryManager = HikiTraits.Library.Systems.InjuryManager

return HikiTraits.InjuryManager
