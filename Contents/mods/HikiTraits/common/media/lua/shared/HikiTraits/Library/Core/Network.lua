-- Hiki Traits Library
-- One validated command router shared by every trait package.

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}
HikiTraits.Library.Core = HikiTraits.Library.Core or {}

require "HikiTraits/Library/Core/Util"
require "HikiTraits/Library/Core/Logger"
require "HikiTraits/Library/Core/Traits"
require "HikiTraits/Library/Core/State"
require "HikiTraits/Library/Core/Runtime"

local Core = HikiTraits.Library.Core
Core.Network = Core.Network or {}

local Network = Core.Network
local Logger = Core.Logger
local Runtime = Core.Runtime
local State = Core.State
local Traits = Core.Traits
local Util = Core.Util

local log = Logger.scoped("Network")

Network.MODULE = Network.MODULE or "HikiTraitsLibrary"
Network._serverHandlers = Network._serverHandlers or {}
Network._clientHandlers = Network._clientHandlers or {}
Network._serverEventInstalled = Network._serverEventInstalled or false
Network._clientEventInstalled = Network._clientEventInstalled or false

local function normalizeHandler(specification)
    assert(type(specification) == "table", "network handler is required")
    assert(
        Util.isNonEmptyString(specification.id),
        "network handler id is required"
    )
    assert(
        type(specification.handle) == "function",
        "network handler callback is required"
    )

    local handler = Util.copyShallow(specification)
    handler.allowDead = handler.allowDead == true
    handler.cooldownMs = math.max(0, tonumber(handler.cooldownMs) or 0)

    return handler
end

local function makeContext(direction, handler, character, args)
    return {
        direction = direction,
        id = handler.id,
        traitId = handler.traitId,
        definition = handler,
        character = character,
        characterKey = Util.characterKey(character),
        characterName = Util.characterName(character),
        args = type(args) == "table" and args or {},
        nowMs = Util.nowMilliseconds(),
        worldAgeHours = Util.worldAgeHours(),
        isClient = Util.isClientContext(),
        isServer = Util.isServerContext(),
        isSingleplayer = Util.isSingleplayerContext(),
    }
end

local function eligible(handler, context)
    local character = context.character

    if character == nil then
        return handler.allowNoCharacter == true
    end

    if not handler.allowDead and Util.isDead(character) then
        return false
    end

    if handler.traitId ~= nil
        and not Traits.has(character, handler.traitId) then
        return false
    end

    if type(handler.validate) == "function" then
        local succeeded, valid = pcall(
            handler.validate,
            context,
            context.args
        )

        if not succeeded then
            log:error("validation for %s failed: %s", handler.id, valid)
            return false
        end

        if valid ~= true then
            return false
        end
    end

    return true
end

local function invoke(handler, context)
    if not eligible(handler, context) then
        return false
    end

    if handler.cooldownMs > 0 and context.character ~= nil then
        local cooldownKey = "network:" .. handler.id

        if not State.isCooldownReady(
            context.character,
            Network.MODULE,
            cooldownKey,
            handler.cooldownMs,
            context.nowMs
        ) then
            return false
        end

        -- Lock before entering third-party code. A failing or malicious
        -- callback must not turn a command into a zero-delay retry cannon.
        State.consumeCooldown(
            context.character,
            Network.MODULE,
            cooldownKey,
            context.nowMs
        )
    end

    local succeeded, problem = pcall(
        handler.handle,
        context,
        context.args
    )

    if not succeeded then
        log:error("handler %s failed: %s", handler.id, tostring(problem))
        return false
    end

    return true
end

local function findLocalCharacter(args)
    local players = Runtime.getPlayers(Runtime.Scope.LOCAL)
    local targetUsername = args and args.__hikiTargetUsername
    local targetOnlineId = tonumber(args and args.__hikiTargetOnlineId)

    for index = 1, #players do
        local character = players[index]

        if targetUsername ~= nil then
            local username = Util.safeCall(nil, function()
                return character:getUsername()
            end)

            if username == targetUsername then
                return character
            end
        elseif targetOnlineId ~= nil then
            local onlineId = Util.safeCall(nil, function()
                return character:getOnlineID()
            end)

            if tonumber(onlineId) == targetOnlineId then
                return character
            end
        end
    end

    return players[1]
end

function Network.dispatchClientCommand(module, command, character, args)
    if module ~= Network.MODULE then
        return
    end

    local handler = Network._serverHandlers[command]
    if handler == nil then
        return
    end

    invoke(
        handler,
        makeContext("toServer", handler, character, args)
    )
end

function Network.dispatchServerCommand(module, command, args)
    if module ~= Network.MODULE then
        return
    end

    local handler = Network._clientHandlers[command]
    if handler == nil then
        return
    end

    local character = findLocalCharacter(args)

    invoke(
        handler,
        makeContext("toClient", handler, character, args)
    )
end

local function installServerEvent()
    if Network._serverEventInstalled or not Util.isServerContext() then
        return
    end

    if Events == nil or Events.OnClientCommand == nil then
        log:error("Events.OnClientCommand is unavailable")
        return
    end

    Network._serverDispatcher = Network._serverDispatcher or function(
        module,
        command,
        character,
        args
    )
        Network.dispatchClientCommand(module, command, character, args)
    end

    Events.OnClientCommand.Add(Network._serverDispatcher)
    Network._serverEventInstalled = true
end

local function installClientEvent()
    if Network._clientEventInstalled or Util.isServerContext() then
        return
    end

    if Events == nil or Events.OnServerCommand == nil then
        log:error("Events.OnServerCommand is unavailable")
        return
    end

    Network._clientDispatcher = Network._clientDispatcher or function(
        module,
        command,
        args
    )
        Network.dispatchServerCommand(module, command, args)
    end

    Events.OnServerCommand.Add(Network._clientDispatcher)
    Network._clientEventInstalled = true
end

function Network.registerServerHandler(specification)
    local handler = normalizeHandler(specification)
    Network._serverHandlers[handler.id] = handler
    installServerEvent()
    return handler
end

function Network.registerClientHandler(specification)
    local handler = normalizeHandler(specification)
    Network._clientHandlers[handler.id] = handler
    installClientEvent()
    return handler
end

function Network.unregister(id)
    local key = tostring(id)
    local removed = Network._serverHandlers[key] ~= nil
        or Network._clientHandlers[key] ~= nil

    Network._serverHandlers[key] = nil
    Network._clientHandlers[key] = nil
    return removed
end

function Network.sendToServer(character, command, args)
    local handler = Network._serverHandlers[command]

    if Util.isClientContext() then
        if type(sendClientCommand) ~= "function" then
            return false
        end

        sendClientCommand(
            character,
            Network.MODULE,
            command,
            type(args) == "table" and args or {}
        )
        return true
    end

    -- Singleplayer has no network boundary, but exercising the same handler
    -- keeps behavior identical and testable.
    if not Util.isServerContext() and handler ~= nil then
        return invoke(
            handler,
            makeContext("localServer", handler, character, args)
        )
    end

    return false
end

function Network.sendToClient(character, command, args)
    local handler = Network._clientHandlers[command]
    local payload = Util.copyShallow(args)

    if character ~= nil then
        payload.__hikiTargetUsername = Util.safeCall(nil, function()
            return character:getUsername()
        end)
        payload.__hikiTargetOnlineId = Util.safeCall(nil, function()
            return character:getOnlineID()
        end)
    end

    if Util.isServerContext() then
        if type(sendServerCommand) ~= "function" then
            return false
        end

        sendServerCommand(character, Network.MODULE, command, payload)
        return true
    end

    if not Util.isClientContext() and handler ~= nil then
        return invoke(
            handler,
            makeContext("localClient", handler, character, payload)
        )
    end

    return false
end

return Network
