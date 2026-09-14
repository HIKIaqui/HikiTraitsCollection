-- Hiki Traits
-- Public entry point for the shared trait library.

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}

local Library = HikiTraits.Library

Library.API_VERSION = 1
Library.VERSION = "0.3.0"

require "HikiTraits/Library/Core"
require "HikiTraits/Library/Systems"

return Library
