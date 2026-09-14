-- Hiki Traits Library
-- Central scheduler for periodic and event-driven trait rules.

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}
HikiTraits.Library.Core = HikiTraits.Library.Core or {}

require "HikiTraits/Library/Core/Util"
require "HikiTraits/Library/Core/Logger"
require "HikiTraits/Library/Core/Traits"
require "HikiTraits/Library/Core/Effects"

local Core = HikiTraits.Library.Core
Core.Runtime = Core.Runtime or {}

local Runtime = Core.Runtime
local Effects = Core.Effects
local Logger = Core.Logger
local Traits = Core.Traits
local Util = Core.Util

local log = Logger.scoped("Runtime")

Runtime.Scope = Runtime.Scope or {
    AUTHORITATIVE = "authoritative",
    LOCAL = "local",
    SERVER = "server",
    CLIENT = "client",
    ANY = "any",
}

Runtime._minute = Runtime._minute or {}
Runtime._hour = Runtime._hour or {}
Runtime._interval = Runtime._interval or {}
Runtime._events = Runtime._events or {}
Runtime._eventDispatchers = Runtime._eventDispatchers or {}
Runtime._minuteEventInstalled = Runtime._minuteEventInstalled or false
Runtime._hourEventInstalled = Runtime._hourEventInstalled or false
Runtime._tickEventInstalled = Runtime._tickEventInstalled or false

local function registrationSorter(left, right)
    local leftPriority = tonumber(left.priority) or 500
    local rightPriority = tonumber(right.priority) or 500

    if leftPriority == rightPriority then
        return left.id < right.id
    end

    return leftPriority < rightPriority
end

local function orderedEntries(source)
    local entries = {}

    for _, entry in pairs(source) do
        entries[#entries + 1] = entry
    end

    table.sort(entries, registrationSorter)
    return entries
end

local function validateSpecification(specification)
    assert(type(specification) == "table", "runtime specification is required")
    assert(
        Util.isNonEmptyString(specification.id),
        "runtime specification id is required"
    )
    assert(
        specification.run == nil
            or type(specification.run) == "function",
        "runtime run callback must be a function"
    )
    assert(
        specification.when == nil
            or type(specification.when) == "function",
        "runtime condition must be a function"
    )
    assert(
        specification.effects ~= nil
            or type(specification.run) == "function",
        "runtime specification needs effects or a run callback"
    )
end

local function normalizeSpecification(specification)
    validateSpecification(specification)

    local normalized = Util.copyShallow(specification)
    normalized.priority = tonumber(normalized.priority) or 500
    normalized.scope = normalized.scope or Runtime.Scope.AUTHORITATIVE
    normalized.allowDead = normalized.allowDead == true
    normalized.allowNoCharacter = normalized.allowNoCharacter == true

    return normalized
end

local function appendUniqueCharacter(characters, character)
    if character == nil then
        return
    end

    for index = 1, #characters do
        if characters[index] == character then
            return
        end
    end

    characters[#characters + 1] = character
end

local function localPlayers()
    local players = {}

    if type(getNumActivePlayers) == "function"
        and type(getSpecificPlayer) == "function" then
        local count = tonumber(getNumActivePlayers()) or 0

        for index = 0, count - 1 do
            appendUniqueCharacter(players, getSpecificPlayer(index))
        end
    end

    if #players == 0 and type(getPlayer) == "function" then
        appendUniqueCharacter(players, getPlayer())
    end

    return players
end

local function serverPlayers()
    local players = {}

    if type(getOnlinePlayers) ~= "function" then
        return players
    end

    local onlinePlayers = getOnlinePlayers()
    if onlinePlayers == nil then
        return players
    end

    for index = 0, onlinePlayers:size() - 1 do
        appendUniqueCharacter(players, onlinePlayers:get(index))
    end

    return players
end

function Runtime.getPlayers(scope)
    local selectedScope = scope or Runtime.Scope.AUTHORITATIVE
    local client = Util.isClientContext()
    local server = Util.isServerContext()

    if selectedScope == Runtime.Scope.AUTHORITATIVE then
        if client then
            return {}
        end

        if server then
            return serverPlayers()
        end

        return localPlayers()
    elseif selectedScope == Runtime.Scope.LOCAL then
        if server then
            return {}
        end

        return localPlayers()
    elseif selectedScope == Runtime.Scope.SERVER then
        if server then
            return serverPlayers()
        end

        return {}
    elseif selectedScope == Runtime.Scope.CLIENT then
        if client then
            return localPlayers()
        end

        return {}
    end

    if server then
        return serverPlayers()
    end

    return localPlayers()
end

local function scopeAllowsEvent(scope, character)
    local selectedScope = scope or Runtime.Scope.AUTHORITATIVE
    local client = Util.isClientContext()
    local server = Util.isServerContext()

    if selectedScope == Runtime.Scope.AUTHORITATIVE then
        return not client
    elseif selectedScope == Runtime.Scope.SERVER then
        return server
    elseif selectedScope == Runtime.Scope.CLIENT then
        return client
    elseif selectedScope == Runtime.Scope.LOCAL then
        if server then
            return false
        end

        if character == nil then
            return true
        end

        local isLocal = Util.safeCall(true, function()
            return character:isLocalPlayer()
        end)

        return isLocal == true
    end

    return true
end

local function scopeExistsHere(scope)
    local selectedScope = scope or Runtime.Scope.AUTHORITATIVE
    local client = Util.isClientContext()
    local server = Util.isServerContext()

    if selectedScope == Runtime.Scope.AUTHORITATIVE then
        return not client
    elseif selectedScope == Runtime.Scope.LOCAL then
        return not server
    elseif selectedScope == Runtime.Scope.SERVER then
        return server
    elseif selectedScope == Runtime.Scope.CLIENT then
        return client
    end

    return true
end

local function makeContext(entry, character, schedule, nowMs, worldHours)
    return {
        id = entry.id,
        traitId = entry.traitId,
        definition = entry,
        character = character,
        characterKey = Util.characterKey(character),
        characterName = Util.characterName(character),
        schedule = schedule,
        nowMs = nowMs or Util.nowMilliseconds(),
        worldAgeHours = worldHours or Util.worldAgeHours(),
        isClient = Util.isClientContext(),
        isServer = Util.isServerContext(),
        isSingleplayer = Util.isSingleplayerContext(),
    }
end

local function reportFailure(entry, phase, problem)
    log:error(
        "%s failed during %s: %s",
        entry.id,
        phase,
        tostring(problem)
    )
end

local function safelyInvoke(entry, phase, callback, ...)
    local succeeded, result = pcall(callback, ...)

    if not succeeded then
        reportFailure(entry, phase, result)
        return false, nil
    end

    return true, result
end

local function isEntryActive(entry, context)
    if context.character == nil and not entry.allowNoCharacter then
        return false
    end

    if context.character ~= nil then
        if not entry.allowDead and Util.isDead(context.character) then
            return false
        end

        if entry.traitId ~= nil
            and not Traits.has(context.character, entry.traitId) then
            if type(entry.onInactive) == "function" then
                safelyInvoke(entry, "onInactive", entry.onInactive, context)
            end

            return false
        end
    end

    if type(entry.enabled) == "function" then
        local succeeded, enabled = safelyInvoke(
            entry,
            "enabled",
            entry.enabled,
            context
        )

        if not succeeded or enabled ~= true then
            return false
        end
    elseif entry.enabled == false then
        return false
    end

    if type(entry.when) == "function" then
        local succeeded, applies = safelyInvoke(
            entry,
            "condition",
            entry.when,
            context
        )

        if not succeeded or applies ~= true then
            return false
        end
    end

    return true
end

function Runtime.execute(entry, context)
    if not isEntryActive(entry, context) then
        return false, nil
    end

    local appliedResults = nil

    if entry.effects ~= nil then
        local effects = entry.effects

        if type(effects) == "function" then
            local succeeded, resolved = safelyInvoke(
                entry,
                "effect resolution",
                effects,
                context
            )

            if not succeeded then
                return false, nil
            end

            effects = resolved
        end

        local succeeded, results = safelyInvoke(
            entry,
            "effects",
            Effects.apply,
            context.character,
            effects,
            context
        )

        if not succeeded then
            return false, nil
        end

        appliedResults = results
        context.effectResults = results
    end

    local runResult = nil

    if type(entry.run) == "function" then
        local succeeded, result = safelyInvoke(
            entry,
            "run",
            entry.run,
            context
        )

        if not succeeded then
            return false, nil
        end

        runResult = result
        context.runResult = result
    end

    if type(entry.after) == "function" then
        safelyInvoke(entry, "after", entry.after, context)
    end

    return true, runResult or appliedResults
end

local function executeForPlayers(entries, schedule, nowMs, worldHours)
    local playerCache = {}

    for entryIndex = 1, #entries do
        local entry = entries[entryIndex]
        local scope = entry.scope
        local players = playerCache[scope]

        if players == nil then
            players = Runtime.getPlayers(scope)
            playerCache[scope] = players
        end

        if entry.allowNoCharacter and #players == 0
            and scopeAllowsEvent(scope, nil) then
            Runtime.execute(
                entry,
                makeContext(entry, nil, schedule, nowMs, worldHours)
            )
        else
            for playerIndex = 1, #players do
                local character = players[playerIndex]

                Runtime.execute(
                    entry,
                    makeContext(
                        entry,
                        character,
                        schedule,
                        nowMs,
                        worldHours
                    )
                )
            end
        end
    end
end

function Runtime.dispatchMinute()
    executeForPlayers(
        orderedEntries(Runtime._minute),
        "minute",
        Util.nowMilliseconds(),
        Util.worldAgeHours()
    )
end

function Runtime.dispatchHour()
    executeForPlayers(
        orderedEntries(Runtime._hour),
        "hour",
        Util.nowMilliseconds(),
        Util.worldAgeHours()
    )
end

function Runtime.dispatchTick()
    local nowMs = Util.nowMilliseconds()
    local worldHours = Util.worldAgeHours()
    local due = {}

    for _, entry in pairs(Runtime._interval) do
        local previous = tonumber(entry._lastRunMs)

        if previous == nil or nowMs < previous
            or nowMs - previous >= entry.intervalMs then
            entry._lastRunMs = nowMs
            due[#due + 1] = entry
        end
    end

    table.sort(due, registrationSorter)

    if #due > 0 then
        executeForPlayers(due, "interval", nowMs, worldHours)
    end
end

local function installMinuteEvent()
    if Runtime._minuteEventInstalled then
        return true
    end

    if Events == nil or Events.EveryOneMinute == nil then
        log:error("Events.EveryOneMinute is unavailable")
        return false
    end

    Runtime._minuteDispatcher = Runtime._minuteDispatcher or function()
        Runtime.dispatchMinute()
    end

    Events.EveryOneMinute.Add(Runtime._minuteDispatcher)
    Runtime._minuteEventInstalled = true
    return true
end

local function installHourEvent()
    if Runtime._hourEventInstalled then
        return true
    end

    if Events == nil or Events.EveryHours == nil then
        log:error("Events.EveryHours is unavailable")
        return false
    end

    Runtime._hourDispatcher = Runtime._hourDispatcher or function()
        Runtime.dispatchHour()
    end

    Events.EveryHours.Add(Runtime._hourDispatcher)
    Runtime._hourEventInstalled = true
    return true
end

local function installTickEvent()
    if Runtime._tickEventInstalled then
        return true
    end

    if Events == nil or Events.OnTick == nil then
        log:error("Events.OnTick is unavailable")
        return false
    end

    Runtime._tickDispatcher = Runtime._tickDispatcher or function()
        Runtime.dispatchTick()
    end

    Events.OnTick.Add(Runtime._tickDispatcher)
    Runtime._tickEventInstalled = true
    return true
end

function Runtime.unregister(id)
    if id == nil then
        return false
    end

    local key = tostring(id)
    local removed = Runtime._minute[key] ~= nil
        or Runtime._hour[key] ~= nil
        or Runtime._interval[key] ~= nil

    Runtime._minute[key] = nil
    Runtime._hour[key] = nil
    Runtime._interval[key] = nil

    for _, registrations in pairs(Runtime._events) do
        if registrations[key] ~= nil then
            registrations[key] = nil
            removed = true
        end
    end

    return removed
end

function Runtime.registerMinute(specification)
    local entry = normalizeSpecification(specification)
    Runtime.unregister(entry.id)
    Runtime._minute[entry.id] = entry
    if scopeExistsHere(entry.scope) then
        installMinuteEvent()
    end

    Logger.debug(
        "Runtime",
        entry.debug,
        "registered minute rule %s for %s",
        entry.id,
        tostring(entry.traitId)
    )

    return entry
end

function Runtime.registerHour(specification)
    local entry = normalizeSpecification(specification)
    Runtime.unregister(entry.id)
    Runtime._hour[entry.id] = entry
    if scopeExistsHere(entry.scope) then
        installHourEvent()
    end

    Logger.debug(
        "Runtime",
        entry.debug,
        "registered hourly rule %s for %s",
        entry.id,
        tostring(entry.traitId)
    )

    return entry
end

function Runtime.registerInterval(intervalMs, specification)
    local entry = normalizeSpecification(specification)
    local interval = tonumber(intervalMs)

    assert(interval ~= nil and interval > 0, "positive intervalMs is required")

    Runtime.unregister(entry.id)
    entry.intervalMs = interval
    Runtime._interval[entry.id] = entry
    if scopeExistsHere(entry.scope) then
        installTickEvent()
    end

    Logger.debug(
        "Runtime",
        entry.debug,
        "registered %d ms rule %s for %s",
        interval,
        entry.id,
        tostring(entry.traitId)
    )

    return entry
end

local function resolveEventCharacter(entry, arguments)
    if type(entry.getCharacter) == "function" then
        return entry.getCharacter(arguments)
    end

    return arguments[tonumber(entry.characterArgument) or 1]
end

function Runtime.dispatchEvent(eventName, ...)
    local registrations = Runtime._events[eventName]
    if registrations == nil then
        return
    end

    local arguments = { ... }
    local entries = orderedEntries(registrations)
    local nowMs = Util.nowMilliseconds()
    local worldHours = Util.worldAgeHours()

    for index = 1, #entries do
        local entry = entries[index]
        local character = resolveEventCharacter(entry, arguments)

        if scopeAllowsEvent(entry.scope, character)
            and (character ~= nil or entry.allowNoCharacter) then
            local context = makeContext(
                entry,
                character,
                "event",
                nowMs,
                worldHours
            )

            context.eventName = eventName
            context.arguments = arguments
            Runtime.execute(entry, context)
        end
    end
end

local function installNamedEvent(eventName)
    if Runtime._eventDispatchers[eventName] ~= nil then
        return true
    end

    local event = Events and Events[eventName]
    if event == nil then
        log:error("Events.%s is unavailable", eventName)
        return false
    end

    local dispatcher = function(...)
        Runtime.dispatchEvent(eventName, ...)
    end

    event.Add(dispatcher)
    Runtime._eventDispatchers[eventName] = dispatcher
    return true
end

function Runtime.registerEvent(eventName, specification)
    assert(Util.isNonEmptyString(eventName), "eventName is required")

    local entry = normalizeSpecification(specification)
    Runtime.unregister(entry.id)

    Runtime._events[eventName] = Runtime._events[eventName] or {}
    Runtime._events[eventName][entry.id] = entry
    -- A shared definition may describe a client/local presentation event.
    -- Dedicated servers keep the registration metadata but do not touch an
    -- event which may not exist in their Lua environment.
    if scopeAllowsEvent(entry.scope, nil) then
        installNamedEvent(eventName)
    end

    Logger.debug(
        "Runtime",
        entry.debug,
        "registered Events.%s rule %s for %s",
        eventName,
        entry.id,
        tostring(entry.traitId)
    )

    return entry
end

function Runtime.getRegistration(id)
    local key = tostring(id)

    if Runtime._minute[key] ~= nil then
        return Runtime._minute[key], "minute"
    end

    if Runtime._hour[key] ~= nil then
        return Runtime._hour[key], "hour"
    end

    if Runtime._interval[key] ~= nil then
        return Runtime._interval[key], "interval"
    end

    for eventName, registrations in pairs(Runtime._events) do
        if registrations[key] ~= nil then
            return registrations[key], eventName
        end
    end

    return nil, nil
end

return Runtime
