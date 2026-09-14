-- Hiki Traits
-- Loads the small, domain-neutral foundation used by every trait system.

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}
HikiTraits.Library.Core = HikiTraits.Library.Core or {}

local Library = HikiTraits.Library
local Core = Library.Core

Library.API_VERSION = Library.API_VERSION or 1
Library.VERSION = Library.VERSION or "0.1.0"

require "HikiTraits/Library/Core/Util"
require "HikiTraits/Library/Core/Logger"
require "HikiTraits/Library/Core/Traits"
require "HikiTraits/Library/Core/Stats"
require "HikiTraits/Library/Core/State"
require "HikiTraits/Library/Core/Conditions"
require "HikiTraits/Library/Core/Effects"
require "HikiTraits/Library/Core/Runtime"
require "HikiTraits/Library/Core/Network"
require "HikiTraits/Library/Core/Triggers"

-- These aliases are the supported public surface. Consumers should not need
-- to know how the files beneath Core are organized.
Library.Util = Core.Util
Library.Logger = Core.Logger
Library.Traits = Core.Traits
Library.Stats = Core.Stats
Library.State = Core.State
Library.Conditions = Core.Conditions
Library.Effects = Core.Effects
Library.Runtime = Core.Runtime
Library.Network = Core.Network
Library.Triggers = Core.Triggers

return Core
