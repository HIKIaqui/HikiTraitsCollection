-- Hiki Traits Library
-- Central, chain-safe observation of vanilla timed-action methods.

require "HikiTraits/Library/Core"

HikiTraits.Library.Systems = HikiTraits.Library.Systems or {}

local Systems = HikiTraits.Library.Systems
Systems.TimedActionManager = Systems.TimedActionManager or {}

local TimedActionManager = Systems.TimedActionManager
local Effects = HikiTraits.Library.Effects
local Logger = HikiTraits.Library.Logger
local Network = HikiTraits.Library.Network
local Runtime = HikiTraits.Library.Runtime
local Traits = HikiTraits.Library.Traits
local Util = HikiTraits.Library.Util

local log = Logger.scoped("TimedActionManager")
local unpackValues = unpack or table.unpack

TimedActionManager._hooks = TimedActionManager._hooks or {}
TimedActionManager._registrationLocations =
    TimedActionManager._registrationLocations or {}

local function packValues(...)
    return { n = select("#", ...), ... }
end

local function orderedHandlers(handlers)
    local ordered = {}

    for _, handler in pairs(handlers) do
        ordered[#ordered + 1] = handler
    end

    table.sort(ordered, function(left, right)
        local leftPriority = tonumber(left.priority) or 500
        local rightPriority = tonumber(right.priority) or 500

        if leftPriority == rightPriority then
            return left.id < right.id
        end

        return leftPriority < rightPriority
    end)

    return ordered
end


local function scopeAllows(handler, character)
    local scope = handler.scope or Runtime.Scope.ANY
    local client = Util.isClientContext()
    local server = Util.isServerContext()

    if scope == Runtime.Scope.AUTHORITATIVE then
        return not client
    elseif scope == Runtime.Scope.SERVER then
        return server
    elseif scope == Runtime.Scope.CLIENT then
        return client
    elseif scope == Runtime.Scope.LOCAL then
        if server then
            return false
        end

        if character == nil then
            return handler.allowNoCharacter == true
        end

        local localPlayer = Util.safeCall(true, function()
            return character:isLocalPlayer()
        end)

        return localPlayer == true
    end

    return true
end


local function scopeExistsHere(scope)
    local selected = scope or Runtime.Scope.ANY
    local client = Util.isClientContext()
    local server = Util.isServerContext()

    if selected == Runtime.Scope.LOCAL then
        return not server
    elseif selected == Runtime.Scope.CLIENT then
        return client
    elseif selected == Runtime.Scope.SERVER then
        return server
    elseif selected == Runtime.Scope.AUTHORITATIVE then
        return not client
    end

    return true
end


function TimedActionManager.getActionState(action, ownerId)
    if action == nil then
        return nil
    end

    action._hikiTraitsLibraryState =
        action._hikiTraitsLibraryState or {}

    local key = tostring(ownerId)
    local state = action._hikiTraitsLibraryState[key]

    if type(state) ~= "table" then
        state = {}
        action._hikiTraitsLibraryState[key] = state
    end

    return state
end


function TimedActionManager.markOnce(action, ownerId, key)
    local state = TimedActionManager.getActionState(action, ownerId)
    if state == nil or state[key] == true then
        return false
    end

    state[key] = true
    return true
end


function TimedActionManager.wasMarked(action, ownerId, key)
    local state = TimedActionManager.getActionState(action, ownerId)
    return state ~= nil and state[key] == true
end


function TimedActionManager.getProgress(action)
    if action == nil or action.action == nil then
        return 0
    end

    local progress = Util.safeCall(0, function()
        return action:getJobDelta()
    end)

    return Util.clamp(tonumber(progress) or 0, 0, 1)
end


function TimedActionManager.getName(action)
    if action == nil then
        return "unknown action"
    end

    return tostring(action.Type or "unknown action")
end


local function getCharacter(handler, action, arguments)
    if type(handler.getCharacter) == "function" then
        local succeeded, character = pcall(
            handler.getCharacter,
            action,
            arguments
        )

        if not succeeded then
            log:error("character resolver %s failed: %s", handler.id, character)
            return nil
        end

        return character
    end

    if action == nil then
        return nil
    end

    return action[handler.characterField or "character"]
end


local function makeContext(bucket, handler, action, arguments, returns)
    local character = getCharacter(handler, action, arguments)

    return {
        id = handler.id,
        definition = handler,
        className = bucket.className,
        method = bucket.method,
        action = action,
        actionName = TimedActionManager.getName(action),
        state = TimedActionManager.getActionState(action, handler.id),
        character = character,
        characterKey = Util.characterKey(character),
        characterName = Util.characterName(character),
        arguments = arguments,
        returns = returns,
        result = returns and returns[1] or nil,
        completed = returns ~= nil and returns[1] == true,
        progress = TimedActionManager.getProgress(action),
        nowMs = Util.nowMilliseconds(),
        worldAgeHours = Util.worldAgeHours(),
        isClient = Util.isClientContext(),
        isServer = Util.isServerContext(),
        isSingleplayer = Util.isSingleplayerContext(),
    }
end


local function eligible(handler, context)
    local character = context.character

    if not scopeAllows(handler, character) then
        return false
    end

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

    if type(handler.when) == "function" then
        local succeeded, applies = pcall(handler.when, context)

        if not succeeded then
            log:error("condition %s failed: %s", handler.id, tostring(applies))
            return false
        end

        return applies == true
    end

    return true
end


local function invokeHandler(bucket, handler, phase, action, arguments, returns)
    local callback = handler[phase]
    if type(callback) ~= "function" then
        return
    end

    local context = makeContext(
        bucket,
        handler,
        action,
        arguments,
        returns
    )
    context.phase = phase

    if not eligible(handler, context) then
        return
    end

    local succeeded, problem = pcall(callback, context)
    if not succeeded then
        log:error(
            "%s %s callback failed on %s.%s: %s",
            handler.id,
            phase,
            bucket.className,
            bucket.method,
            tostring(problem)
        )
    end
end


function TimedActionManager.dispatch(bucket, action, ...)
    local arguments = packValues(...)
    local handlers = orderedHandlers(bucket.handlers)

    for index = 1, #handlers do
        invokeHandler(
            bucket,
            handlers[index],
            "before",
            action,
            arguments,
            nil
        )
    end

    -- Vanilla errors must remain visible. Swallowing one here would leave the
    -- timed-action queue in a state normally studied only by archaeologists.
    local returns = packValues(
        bucket.original(action, unpackValues(arguments, 1, arguments.n))
    )

    for index = 1, #handlers do
        invokeHandler(
            bucket,
            handlers[index],
            "after",
            action,
            arguments,
            returns
        )
    end

    return unpackValues(returns, 1, returns.n)
end


local function hookKey(className, method)
    return tostring(className) .. ":" .. tostring(method)
end


local function ensureHook(target, className, method)
    local key = hookKey(className, method)
    local bucket = TimedActionManager._hooks[key]

    if bucket ~= nil then
        return bucket
    end

    if type(target) ~= "table" or type(target[method]) ~= "function" then
        log:error("%s.%s was not found", tostring(className), tostring(method))
        return nil
    end

    bucket = {
        key = key,
        target = target,
        className = className,
        method = method,
        original = target[method],
        handlers = {},
    }

    bucket.wrapper = function(action, ...)
        return TimedActionManager.dispatch(bucket, action, ...)
    end

    target[method] = bucket.wrapper
    TimedActionManager._hooks[key] = bucket

    return bucket
end


function TimedActionManager.unregister(id)
    local key = tostring(id)
    local location = TimedActionManager._registrationLocations[key]

    if location == nil then
        return false
    end

    local bucket = TimedActionManager._hooks[location]
    if bucket ~= nil then
        bucket.handlers[key] = nil
    end

    TimedActionManager._registrationLocations[key] = nil
    return true
end


function TimedActionManager.register(specification)
    assert(type(specification) == "table", "timed-action hook is required")
    assert(Util.isNonEmptyString(specification.id), "hook id is required")
    assert(Util.isNonEmptyString(specification.className), "className is required")
    assert(Util.isNonEmptyString(specification.method), "method is required")
    assert(
        type(specification.before) == "function"
            or type(specification.after) == "function",
        "before or after callback is required"
    )

    local handler = Util.copyShallow(specification)
    handler.priority = tonumber(handler.priority) or 500
    handler.scope = handler.scope or Runtime.Scope.ANY
    handler.allowDead = handler.allowDead == true

    TimedActionManager.unregister(handler.id)

    -- Shared trait definitions can register local/client hooks safely: a
    -- dedicated server records no wrapper and never needs that UI action class.
    if not scopeExistsHere(handler.scope) then
        return handler
    end

    if handler.target == nil and Util.isNonEmptyString(handler.module) then
        local loaded, problem = pcall(require, handler.module)
        if not loaded then
            log:error("could not load %s: %s", handler.module, problem)
        end
    end

    if handler.target == nil then
        handler.target = _G[handler.className]
    end

    assert(type(handler.target) == "table", "hook target is required")

    local bucket = ensureHook(
        handler.target,
        handler.className,
        handler.method
    )

    if bucket == nil then
        return nil
    end

    bucket.handlers[handler.id] = handler
    TimedActionManager._registrationLocations[handler.id] = bucket.key

    Logger.debug(
        "TimedActionManager",
        handler.debug,
        "registered %s on %s.%s",
        handler.id,
        handler.className,
        handler.method
    )

    return handler
end


-- Bridges a local timed action to one authoritative server callback. The
-- payload is captured before vanilla mutates or clears the action, then sent
-- after it returns unless phase="before" was explicitly requested.
function TimedActionManager.registerAuthoritative(specification)
    assert(type(specification) == "table", "authoritative hook is required")
    assert(Util.isNonEmptyString(specification.id), "hook id is required")
    assert(
        type(specification.onServer) == "function"
            or specification.effects ~= nil,
        "onServer callback or effects are required"
    )

    local definition = Util.copyShallow(specification)
    definition.command = definition.command
        or ("TimedAction:" .. definition.id)
    definition.phase = definition.phase or "after"

    Network.registerServerHandler({
        id = definition.command,
        traitId = definition.traitId,
        allowDead = definition.allowDead,
        cooldownMs = definition.cooldownMs,
        validate = function(context, args)
            if type(definition.validate) ~= "function" then
                return true
            end

            return definition.validate(context, args) == true
        end,
        handle = function(networkContext, args)
            local context = {
                id = definition.id,
                definition = definition,
                character = networkContext.character,
                characterKey = networkContext.characterKey,
                characterName = networkContext.characterName,
                args = args,
                actionName = tostring(args.actionName or "unknown action"),
                progress = Util.clamp(
                    tonumber(args.progress) or 0,
                    0,
                    1
                ),
                nowMs = networkContext.nowMs,
                worldAgeHours = networkContext.worldAgeHours,
                isClient = networkContext.isClient,
                isServer = networkContext.isServer,
                isSingleplayer = networkContext.isSingleplayer,
            }

            if type(definition.serverWhen) == "function"
                and definition.serverWhen(context, args) ~= true then
                return
            end

            if definition.effects ~= nil then
                local effects = definition.effects
                if type(effects) == "function" then
                    effects = effects(context, args)
                end

                Effects.apply(context.character, effects, context)
            end

            if type(definition.onServer) == "function" then
                definition.onServer(context, args)
            end
        end,
    })

    -- A dedicated server only owns validation/effects. It never needs the
    -- client's action class or its animation helpers to be installed.
    if Util.isServerContext() then
        return definition
    end

    local hookId = definition.id .. ":local-action"
    local function capture(context)
        local state = TimedActionManager.getActionState(
            context.action,
            hookId
        )

        if state.sent or state.payload ~= nil then
            return
        end

        if type(definition.whenAction) == "function"
            and definition.whenAction(context) ~= true then
            state.rejected = true
            return
        end

        local payload = {}
        if type(definition.payload) == "function" then
            payload = definition.payload(context)
            if type(payload) ~= "table" then
                payload = {}
            end
        elseif type(definition.payload) == "table" then
            payload = Util.copyShallow(definition.payload)
        end

        payload.actionName = payload.actionName or context.actionName
        payload.progress = payload.progress or context.progress
        state.payload = payload

        if definition.phase == "before" then
            state.sent = Network.sendToServer(
                context.character,
                definition.command,
                payload
            )
        end
    end

    local function transmit(context)
        local state = TimedActionManager.getActionState(
            context.action,
            hookId
        )

        if definition.phase == "before" or state.sent
            or state.rejected or state.payload == nil then
            return
        end

        if type(definition.afterWhen) == "function"
            and definition.afterWhen(context, state.payload) ~= true then
            return
        end

        state.sent = Network.sendToServer(
            context.character,
            definition.command,
            state.payload
        )
    end

    definition.localHook = TimedActionManager.register({
        id = hookId,
        module = definition.module,
        target = definition.target,
        className = definition.className,
        method = definition.method,
        characterField = definition.characterField,
        getCharacter = definition.getCharacter,
        traitId = definition.traitId,
        priority = definition.priority,
        scope = Runtime.Scope.LOCAL,
        allowDead = definition.allowDead,
        before = capture,
        after = transmit,
    })

    return definition
end


TimedActionManager.registerRule = TimedActionManager.register


function TimedActionManager.getHook(className, method)
    return TimedActionManager._hooks[hookKey(className, method)]
end


return TimedActionManager
