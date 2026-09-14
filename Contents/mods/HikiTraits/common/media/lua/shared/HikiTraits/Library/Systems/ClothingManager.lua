-- Hiki Traits Library
-- Worn-item queries, reusable equipment groups, and synchronized wetness.

require "HikiTraits/Library/Core"

HikiTraits.Library.Systems = HikiTraits.Library.Systems or {}

local Systems = HikiTraits.Library.Systems
Systems.ClothingManager = Systems.ClothingManager or {}

local ClothingManager = Systems.ClothingManager
local Logger = HikiTraits.Library.Logger
local Util = HikiTraits.Library.Util

local log = Logger.scoped("ClothingManager")
local unpackValues = unpack or table.unpack

ClothingManager._groups = ClothingManager._groups or {}
ClothingManager.EPSILON = ClothingManager.EPSILON or 0.001

local function callMethod(defaultValue, object, method, ...)
    if object == nil or type(object[method]) ~= "function" then
        return defaultValue, false
    end

    local arguments = { ... }
    local succeeded, result = pcall(function()
        return object[method](object, unpackValues(arguments))
    end)

    if not succeeded then
        return defaultValue, false
    end

    return result, true
end

local function normalizeSet(values)
    local normalized = {}

    if type(values) == "string" then
        normalized[values] = true
        return normalized
    end

    if type(values) ~= "table" then
        return normalized
    end

    for key, value in pairs(values) do
        if type(key) == "number" then
            normalized[tostring(value)] = true
        elseif value == true then
            normalized[tostring(key)] = true
        end
    end

    return normalized
end

local function objectLabel(value)
    if value == nil then
        return nil
    end

    local label, succeeded = callMethod(nil, value, "toString")
    if succeeded and label ~= nil then
        return tostring(label)
    end

    return tostring(value)
end

local function listSize(list)
    if list == nil then
        return 0
    end

    if type(list.size) == "function" then
        local size = callMethod(0, list, "size")
        return math.max(0, tonumber(size) or 0)
    end

    return #list
end

local function listGet(list, index)
    if list == nil then
        return nil
    end

    if type(list.get) == "function" then
        return callMethod(nil, list, "get", index)
    end

    return list[index + 1]
end

function ClothingManager.getWornItems(character)
    if character == nil then
        return nil
    end

    return callMethod(nil, character, "getWornItems")
end

function ClothingManager.getLocation(character, item)
    local wornItems = ClothingManager.getWornItems(character)
    if wornItems == nil or item == nil then
        return nil
    end

    local location, succeeded = callMethod(
        nil,
        wornItems,
        "getLocation",
        item
    )

    if succeeded and location ~= nil then
        return location
    end

    return nil
end

function ClothingManager.listWorn(character)
    local result = {}
    local wornItems = ClothingManager.getWornItems(character)
    if wornItems == nil then
        return result
    end

    local count = listSize(wornItems)
    for index = 0, count - 1 do
        local item = callMethod(
            nil,
            wornItems,
            "getItemByIndex",
            index
        )

        if item ~= nil then
            local fullType = callMethod(nil, item, "getFullType")
            result[#result + 1] = {
                index = index,
                item = item,
                fullType = fullType and tostring(fullType) or nil,
                location = ClothingManager.getLocation(character, item),
            }
        end
    end

    return result
end

function ClothingManager.registerGroup(id, definition)
    assert(Util.isNonEmptyString(id), "clothing group id is required")

    local group = definition
    if type(group) ~= "table"
        or (group.items == nil and group.matches == nil) then
        group = { items = definition }
    else
        group = Util.copyShallow(group)
    end

    group.id = id
    group.items = normalizeSet(group.items)
    assert(
        group.matches == nil or type(group.matches) == "function",
        "clothing group matches must be a function"
    )

    ClothingManager._groups[id] = group
    return group
end

function ClothingManager.unregisterGroup(id)
    local key = tostring(id)
    if ClothingManager._groups[key] == nil then
        return false
    end

    ClothingManager._groups[key] = nil
    return true
end

function ClothingManager.addToGroup(id, fullType)
    local group = ClothingManager._groups[tostring(id)]
    if group == nil then
        group = ClothingManager.registerGroup(tostring(id), {})
    end

    if not Util.isNonEmptyString(fullType) then
        return false
    end

    group.items[fullType] = true
    return true
end

function ClothingManager.getGroup(id)
    return ClothingManager._groups[tostring(id)]
end

function ClothingManager.isInGroup(item, groupOrId, entry)
    if item == nil then
        return false
    end

    local group = groupOrId
    if type(groupOrId) == "string" then
        group = ClothingManager._groups[groupOrId]
    end

    if type(group) ~= "table" then
        return false
    end

    local fullType = entry and entry.fullType
    if fullType == nil then
        fullType = callMethod(nil, item, "getFullType")
        fullType = fullType and tostring(fullType) or nil
    end

    if fullType ~= nil and group.items[fullType] == true then
        return true
    end

    if type(group.matches) == "function" then
        local succeeded, matches = pcall(group.matches, item, entry)
        if not succeeded then
            log:error("group %s matcher failed: %s", group.id, matches)
            return false
        end

        return matches == true
    end

    return false
end

local function selectorMatches(selector, item, entry)
    if selector == nil then
        return true
    end

    if type(selector) == "function" then
        local succeeded, matches = pcall(selector, item, entry)
        if not succeeded then
            log:error("clothing selector failed: %s", matches)
            return false
        end

        return matches == true
    end

    if type(selector) == "string" then
        if ClothingManager._groups[selector] ~= nil then
            return ClothingManager.isInGroup(item, selector, entry)
        end

        return entry.fullType == selector
    end

    if type(selector) == "table" then
        if selector.items ~= nil or selector.matches ~= nil then
            return ClothingManager.isInGroup(item, selector, entry)
        end

        local set = normalizeSet(selector)
        return set[entry.fullType] == true
    end

    return false
end

function ClothingManager.findWorn(character, selector)
    local matches = {}
    local worn = ClothingManager.listWorn(character)

    for index = 1, #worn do
        local entry = worn[index]
        if selectorMatches(selector, entry.item, entry) then
            matches[#matches + 1] = entry
        end
    end

    return matches
end

function ClothingManager.firstWorn(character, selector)
    local matches = ClothingManager.findWorn(character, selector)
    return matches[1]
end

function ClothingManager.hasWorn(character, selector)
    return ClothingManager.firstWorn(character, selector) ~= nil
end

function ClothingManager.hasWornGroup(character, groupId)
    return ClothingManager.hasWorn(character, groupId)
end

function ClothingManager.conditionWearing(selector)
    return function(context)
        return context ~= nil
            and ClothingManager.hasWorn(context.character, selector)
    end
end

function ClothingManager.getCoveredParts(item)
    local result = {}
    local covered = callMethod(nil, item, "getCoveredParts")
    local count = listSize(covered)

    for index = 0, count - 1 do
        local part = listGet(covered, index)
        result[#result + 1] = {
            value = part,
            name = objectLabel(part),
        }
    end

    return result
end

local function samePart(part, wanted)
    if part.value == wanted then
        return true
    end

    local wantedName = objectLabel(wanted)
    return wantedName ~= nil and part.name == wantedName
end

function ClothingManager.coversPart(item, bodyPart)
    local covered = ClothingManager.getCoveredParts(item)
    for index = 1, #covered do
        if samePart(covered[index], bodyPart) then
            return true
        end
    end

    return false
end

function ClothingManager.coversAny(item, bodyParts)
    if type(bodyParts) ~= "table" then
        return ClothingManager.coversPart(item, bodyParts)
    end

    for index = 1, #bodyParts do
        if ClothingManager.coversPart(item, bodyParts[index]) then
            return true
        end
    end

    return false
end

function ClothingManager.selectorByLocations(locations)
    local allowed = normalizeSet(locations)

    return function(_, entry)
        return entry ~= nil
            and entry.location ~= nil
            and allowed[objectLabel(entry.location)] == true
    end
end

function ClothingManager.selectorByCoveredParts(bodyParts)
    return function(item)
        return ClothingManager.coversAny(item, bodyParts)
    end
end

function ClothingManager.getWetness(item)
    local wetness = callMethod(nil, item, "getWetness")
    return tonumber(wetness)
end

function ClothingManager.sync(character, item, location)
    if character == nil or item == nil or not Util.isServerContext() then
        return false
    end

    local wornLocation = location
        or ClothingManager.getLocation(character, item)

    if wornLocation ~= nil and type(sendClothing) == "function" then
        local succeeded = pcall(
            sendClothing,
            character,
            wornLocation,
            item
        )

        if succeeded then
            return true
        end
    end

    if type(sendItemStats) == "function" then
        local succeeded = pcall(sendItemStats, item)
        if succeeded then
            return true
        end
    end

    log:warn("could not synchronize worn item %s", tostring(item))
    return false
end

function ClothingManager.setWetness(character, item, wanted, options)
    options = options or {}

    local before = ClothingManager.getWetness(item)
    if before == nil then
        return {
            item = item,
            before = nil,
            after = nil,
            delta = 0,
            changed = false,
        }
    end

    local target = Util.clamp(tonumber(wanted) or before, 0, 100)
    if math.abs(target - before)
        <= (tonumber(options.epsilon) or ClothingManager.EPSILON) then
        return {
            item = item,
            before = before,
            after = before,
            delta = 0,
            changed = false,
        }
    end

    local _, succeeded = callMethod(nil, item, "setWetness", target)
    local after = ClothingManager.getWetness(item) or target
    local result = {
        item = item,
        before = before,
        after = after,
        delta = after - before,
        changed = succeeded
            and math.abs(after - before) > ClothingManager.EPSILON,
    }

    if result.changed and options.sync ~= false then
        ClothingManager.sync(character, item, options.location)
    end

    return result
end

function ClothingManager.changeWetness(character, item, delta, options)
    local current = ClothingManager.getWetness(item)
    if current == nil then
        return ClothingManager.setWetness(character, item, 0, options)
    end

    return ClothingManager.setWetness(
        character,
        item,
        current + (tonumber(delta) or 0),
        options
    )
end

function ClothingManager.setWornWetness(
    character,
    wanted,
    selector,
    options
)
    local results = {}
    local matches = ClothingManager.findWorn(character, selector)

    for index = 1, #matches do
        local entry = matches[index]
        local result = ClothingManager.setWetness(
            character,
            entry.item,
            wanted,
            {
                epsilon = options and options.epsilon,
                sync = options == nil or options.sync ~= false,
                location = entry.location,
            }
        )
        result.entry = entry
        results[#results + 1] = result
    end

    return results
end

function ClothingManager.changeWornWetness(
    character,
    delta,
    selector,
    options
)
    local results = {}
    local matches = ClothingManager.findWorn(character, selector)

    for index = 1, #matches do
        local entry = matches[index]
        local result = ClothingManager.changeWetness(
            character,
            entry.item,
            delta,
            {
                epsilon = options and options.epsilon,
                sync = options == nil or options.sync ~= false,
                location = entry.location,
            }
        )
        result.entry = entry
        results[#results + 1] = result
    end

    return results
end

-- Shared vanilla group used by Ear Ringing and any future sound-sensitive
-- trait. Mods can extend it without replacing a hook or editing this file.
if ClothingManager._groups.hearingProtection == nil then
    ClothingManager.registerGroup("hearingProtection", {
        "Base.Hat_EarMuff_Protectors",
        "Base.Hat_EarMuffs",
    })
end

return ClothingManager
