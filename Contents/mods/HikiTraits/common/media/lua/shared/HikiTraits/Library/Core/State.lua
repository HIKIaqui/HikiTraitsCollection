-- Hiki Traits Library
-- Persistent character data and disposable session state.

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}
HikiTraits.Library.Core = HikiTraits.Library.Core or {}

require "HikiTraits/Library/Core/Util"

local Core = HikiTraits.Library.Core
Core.State = Core.State or {}

local State = Core.State
local Util = Core.Util

State.ROOT_KEY = State.ROOT_KEY or "HikiTraitsLibrary"
State.DATA_VERSION = State.DATA_VERSION or 1
State._sessions = State._sessions or {}

State.Persistent = State.Persistent or {}
State.Session = State.Session or {}

local function persistentRoot(character, create)
    if character == nil then
        return nil
    end

    local modData = character:getModData()
    if modData == nil then
        return nil
    end

    local root = modData[State.ROOT_KEY]

    if type(root) ~= "table" and create then
        root = {
            version = State.DATA_VERSION,
            owners = {},
        }
        modData[State.ROOT_KEY] = root
    end

    if type(root) ~= "table" then
        return nil
    end

    if type(root.owners) ~= "table" and create then
        root.owners = {}
    end

    return root
end

local function persistentOwner(character, ownerId, create)
    local root = persistentRoot(character, create)
    if root == nil or type(root.owners) ~= "table" then
        return nil
    end

    local key = tostring(ownerId)
    local owner = root.owners[key]

    if type(owner) ~= "table" and create then
        owner = {}
        root.owners[key] = owner
    end

    return owner
end

local function sessionOwner(character, ownerId, create)
    if character == nil then
        return nil
    end

    local characterKey = Util.characterKey(character)
    local characterState = State._sessions[characterKey]

    if type(characterState) ~= "table" and create then
        characterState = {}
        State._sessions[characterKey] = characterState
    end

    if type(characterState) ~= "table" then
        return nil
    end

    local key = tostring(ownerId)
    local owner = characterState[key]

    if type(owner) ~= "table" and create then
        owner = {}
        characterState[key] = owner
    end

    return owner
end

local function getValue(owner, key, defaultValue)
    if owner == nil or owner[key] == nil then
        return defaultValue
    end

    return owner[key]
end

function State.Persistent.get(character, ownerId, key, defaultValue)
    return getValue(
        persistentOwner(character, ownerId, false),
        key,
        defaultValue
    )
end

function State.Persistent.set(character, ownerId, key, value)
    local owner = persistentOwner(character, ownerId, true)
    if owner == nil then
        return false
    end

    owner[key] = value
    return true
end

function State.Persistent.initialize(character, ownerId, key, defaultValue)
    local owner = persistentOwner(character, ownerId, true)
    if owner == nil then
        return defaultValue
    end

    if owner[key] == nil then
        owner[key] = defaultValue
    end

    return owner[key]
end

function State.Persistent.remove(character, ownerId, key)
    local owner = persistentOwner(character, ownerId, false)
    if owner ~= nil then
        owner[key] = nil
    end
end

function State.Persistent.clear(character, ownerId)
    local root = persistentRoot(character, false)
    if root ~= nil and type(root.owners) == "table" then
        root.owners[tostring(ownerId)] = nil
    end
end

function State.Session.get(character, ownerId, key, defaultValue)
    return getValue(
        sessionOwner(character, ownerId, false),
        key,
        defaultValue
    )
end

function State.Session.set(character, ownerId, key, value)
    local owner = sessionOwner(character, ownerId, true)
    if owner == nil then
        return false
    end

    owner[key] = value
    return true
end

function State.Session.initialize(character, ownerId, key, defaultValue)
    local owner = sessionOwner(character, ownerId, true)
    if owner == nil then
        return defaultValue
    end

    if owner[key] == nil then
        owner[key] = defaultValue
    end

    return owner[key]
end

function State.Session.remove(character, ownerId, key)
    local owner = sessionOwner(character, ownerId, false)
    if owner ~= nil then
        owner[key] = nil
    end
end

function State.Session.clear(character, ownerId)
    local characterState = State._sessions[Util.characterKey(character)]
    if type(characterState) == "table" then
        characterState[tostring(ownerId)] = nil
    end
end

function State.clearCharacterSession(character)
    if character ~= nil then
        State._sessions[Util.characterKey(character)] = nil
    end
end

function State.getStorage(mode)
    if mode == "session" then
        return State.Session
    end

    return State.Persistent
end

function State.initializeWorldTimestamp(character, ownerId, key, mode)
    local storage = State.getStorage(mode)
    local now = Util.worldAgeHours()
    local previous = tonumber(storage.get(character, ownerId, key))

    if previous == nil or previous > now then
        storage.set(character, ownerId, key, now)
        return now, true
    end

    return previous, false
end

function State.markWorldTime(character, ownerId, key, mode)
    local now = Util.worldAgeHours()
    State.getStorage(mode).set(character, ownerId, key, now)
    return now
end

function State.elapsedWorldHours(character, ownerId, key, mode)
    local timestamp = State.initializeWorldTimestamp(
        character,
        ownerId,
        key,
        mode
    )

    return math.max(0, Util.worldAgeHours() - timestamp)
end

function State.isCooldownReady(character, ownerId, key, durationMs, nowMs)
    local now = tonumber(nowMs) or Util.nowMilliseconds()
    local previous = tonumber(
        State.Session.get(character, ownerId, key)
    )

    if previous == nil or now < previous then
        return true
    end

    return now - previous >= math.max(0, tonumber(durationMs) or 0)
end

function State.consumeCooldown(character, ownerId, key, nowMs)
    local now = tonumber(nowMs) or Util.nowMilliseconds()
    State.Session.set(character, ownerId, key, now)
    return now
end

return State
