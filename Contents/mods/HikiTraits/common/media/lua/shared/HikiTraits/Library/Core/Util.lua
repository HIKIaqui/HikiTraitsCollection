-- Hiki Traits Library
-- Generic helpers with no trait-specific behavior.

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}
HikiTraits.Library.Core = HikiTraits.Library.Core or {}

local Core = HikiTraits.Library.Core
Core.Util = Core.Util or {}

local Util = Core.Util

function Util.isNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

function Util.clamp(value, minimum, maximum)
    local number = tonumber(value)
    if number == nil then
        return minimum
    end

    if minimum ~= nil and number < minimum then
        return minimum
    end

    if maximum ~= nil and number > maximum then
        return maximum
    end

    return number
end

function Util.copyArray(source)
    local copy = {}

    if type(source) ~= "table" then
        return copy
    end

    for index = 1, #source do
        copy[index] = source[index]
    end

    return copy
end

function Util.copyShallow(source)
    local copy = {}

    if type(source) ~= "table" then
        return copy
    end

    for key, value in pairs(source) do
        copy[key] = value
    end

    return copy
end

function Util.safeCall(defaultValue, callback, ...)
    if type(callback) ~= "function" then
        return defaultValue, false
    end

    local succeeded, result = pcall(callback, ...)
    if not succeeded then
        return defaultValue, false
    end

    return result, true
end

function Util.isClientContext()
    return type(isClient) == "function" and isClient() == true
end

function Util.isServerContext()
    return type(isServer) == "function" and isServer() == true
end

function Util.isSingleplayerContext()
    return not Util.isClientContext() and not Util.isServerContext()
end

function Util.nowMilliseconds()
    if type(getTimestampMs) == "function" then
        return tonumber(getTimestampMs()) or 0
    end

    -- The game clock is a sufficient monotonic fallback for tests and unusual
    -- Lua contexts where getTimestampMs is not exposed.
    return math.floor(Util.worldAgeHours() * 3600000)
end

function Util.worldAgeHours()
    if type(getGameTime) ~= "function" then
        return 0
    end

    local gameTime = getGameTime()
    if gameTime == nil then
        return 0
    end

    return tonumber(gameTime:getWorldAgeHours()) or 0
end

function Util.characterName(character)
    if character == nil then
        return "unknown character"
    end

    local username = Util.safeCall(nil, function()
        return character:getUsername()
    end)

    if Util.isNonEmptyString(username) then
        return username
    end

    local displayName = Util.safeCall(nil, function()
        return character:getDisplayName()
    end)

    if Util.isNonEmptyString(displayName) then
        return displayName
    end

    return tostring(character)
end

function Util.characterKey(character)
    if character == nil then
        return "nil"
    end

    local username = Util.safeCall(nil, function()
        return character:getUsername()
    end)

    if Util.isNonEmptyString(username) then
        return "username:" .. username
    end

    local onlineId = Util.safeCall(nil, function()
        return character:getOnlineID()
    end)

    if onlineId ~= nil and tonumber(onlineId) ~= nil
        and tonumber(onlineId) >= 0 then
        return "online:" .. tostring(onlineId)
    end

    local playerNumber = Util.safeCall(nil, function()
        return character:getPlayerNum()
    end)

    if playerNumber ~= nil and tonumber(playerNumber) ~= nil
        and tonumber(playerNumber) >= 0 then
        return "local:" .. tostring(playerNumber)
    end

    return "object:" .. tostring(character)
end

function Util.isDead(character)
    if character == nil then
        return true
    end

    local dead, succeeded = Util.safeCall(false, function()
        return character:isDead()
    end)

    return succeeded and dead == true
end

function Util.resolveValue(value, context)
    if type(value) == "function" then
        return value(context)
    end

    return value
end

return Util
