-- Hiki Traits Library
-- Cached CharacterTrait resolution and safe character checks.

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}
HikiTraits.Library.Core = HikiTraits.Library.Core or {}

local Core = HikiTraits.Library.Core
Core.Traits = Core.Traits or {}

local Traits = Core.Traits

Traits._cache = Traits._cache or {}

function Traits.resolve(traitId)
    if type(traitId) ~= "string" or traitId == "" then
        return nil
    end

    local cached = Traits._cache[traitId]
    if cached ~= nil then
        return cached
    end

    if CharacterTrait == nil or ResourceLocation == nil then
        return nil
    end

    local succeeded, trait = pcall(function()
        return CharacterTrait.get(ResourceLocation.of(traitId))
    end)

    -- Do not cache misses. Registries may not be ready during early loading.
    if succeeded and trait ~= nil then
        Traits._cache[traitId] = trait
        return trait
    end

    return nil
end

function Traits.has(character, traitOrId)
    if character == nil or traitOrId == nil then
        return false
    end

    local trait = traitOrId
    if type(traitOrId) == "string" then
        trait = Traits.resolve(traitOrId)
    end

    if trait == nil then
        return false
    end

    local succeeded, result = pcall(function()
        return character:hasTrait(trait)
    end)

    return succeeded and result == true
end

function Traits.hasAny(character, traitIds)
    if type(traitIds) ~= "table" then
        return false
    end

    for index = 1, #traitIds do
        if Traits.has(character, traitIds[index]) then
            return true
        end
    end

    return false
end

function Traits.hasAll(character, traitIds)
    if type(traitIds) ~= "table" then
        return false
    end

    for index = 1, #traitIds do
        if not Traits.has(character, traitIds[index]) then
            return false
        end
    end

    return true
end

function Traits.clearCache(traitId)
    if traitId == nil then
        Traits._cache = {}
        return
    end

    Traits._cache[tostring(traitId)] = nil
end

return Traits
