-- Hiki Traits Library
-- Central observation of food, fluid, world-water, and pill consumption.

require "HikiTraits/Library/Core"
require "HikiTraits/Library/Systems/TimedActionManager"

HikiTraits.Library.Systems = HikiTraits.Library.Systems or {}

local Systems = HikiTraits.Library.Systems
Systems.ConsumptionManager = Systems.ConsumptionManager or {}

local ConsumptionManager = Systems.ConsumptionManager
local Effects = HikiTraits.Library.Effects
local Logger = HikiTraits.Library.Logger
local Network = HikiTraits.Library.Network
local Runtime = HikiTraits.Library.Runtime
local TimedActionManager = Systems.TimedActionManager
local Traits = HikiTraits.Library.Traits
local Util = HikiTraits.Library.Util

local log = Logger.scoped("ConsumptionManager")
local unpackValues = unpack or table.unpack

ConsumptionManager.Kind = ConsumptionManager.Kind or {
    FOOD = "food",
    FLUID = "fluid",
    PILL = "pill",
}

ConsumptionManager.Source = ConsumptionManager.Source or {
    FOOD_COMPLETE = "foodComplete",
    FOOD_PARTIAL = "foodPartial",
    FLUID_CONTAINER = "fluidContainer",
    BOTTLE = "bottle",
    WORLD_WATER = "worldWater",
    PILL = "pill",
}

ConsumptionManager.NETWORK_COMMAND =
    ConsumptionManager.NETWORK_COMMAND or "ConsumptionObservedV1"
ConsumptionManager.MAX_NETWORK_LITERS =
    ConsumptionManager.MAX_NETWORK_LITERS or 5

ConsumptionManager._observers = ConsumptionManager._observers or {}
ConsumptionManager._orderedObservers =
    ConsumptionManager._orderedObservers or {}
ConsumptionManager._observerOrderDirty =
    ConsumptionManager._observerOrderDirty ~= false
ConsumptionManager._hooksInstalled =
    ConsumptionManager._hooksInstalled or false
ConsumptionManager._networkInstalled =
    ConsumptionManager._networkInstalled or false

local STATE_OWNER = "hikitraits:library:consumption-manager"

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

local function booleanMethod(object, method)
    local result, succeeded = callMethod(false, object, method)
    return succeeded and result == true
end

local function numberMethod(object, method)
    local result, succeeded = callMethod(nil, object, method)
    if not succeeded then
        return nil
    end

    return tonumber(result)
end

local function stringMethod(object, method)
    local result, succeeded = callMethod(nil, object, method)
    if not succeeded or result == nil then
        return nil
    end

    return tostring(result)
end

function ConsumptionManager.normalizePortion(portion, defaultValue)
    local normalized = tonumber(portion)

    if normalized == nil then
        normalized = tonumber(defaultValue) or 1
    end

    -- Vanilla uses 0-1, but accepting 0-100 makes compatibility adapters less
    -- surprising without allowing a single sandwich to feed a small nation.
    if normalized > 1 then
        normalized = normalized / 100
    end

    return Util.clamp(normalized, 0, 1)
end

function ConsumptionManager.getFluidContainer(item)
    local container = callMethod(nil, item, "getFluidContainer")
    return container
end

function ConsumptionManager.isSmokable(item)
    if item == nil or ItemTag == nil or ItemTag.SMOKABLE == nil then
        return false
    end

    local result, succeeded = callMethod(
        false,
        item,
        "hasTag",
        ItemTag.SMOKABLE
    )

    return succeeded and result == true
end

local function snapshotFluidProperties(properties)
    if properties == nil then
        return nil
    end

    return {
        alcohol = numberMethod(properties, "getAlcohol") or 0,
        calories = numberMethod(properties, "getCalories") or 0,
        carbohydrates =
            numberMethod(properties, "getCarbohydrates") or 0,
        lipids = numberMethod(properties, "getLipids") or 0,
        proteins = numberMethod(properties, "getProteins") or 0,
    }
end

function ConsumptionManager.snapshotFluid(fluidContainer)
    if fluidContainer == nil then
        return nil
    end

    local primaryType = nil
    local primaryFluid = callMethod(
        nil,
        fluidContainer,
        "getPrimaryFluid"
    )

    if primaryFluid ~= nil then
        primaryType = stringMethod(
            primaryFluid,
            "getFluidTypeString"
        )
    end

    local properties = callMethod(
        nil,
        fluidContainer,
        "getProperties"
    )

    local snapshot = {
        amount = numberMethod(fluidContainer, "getAmount") or 0,
        empty = booleanMethod(fluidContainer, "isEmpty"),
        primaryType = primaryType,
        properties = snapshotFluidProperties(properties),
        containsTaintedWater = false,
    }

    if primaryType == nil and Fluid ~= nil
        and Fluid.TaintedWater ~= nil then
        local contains = callMethod(
            false,
            fluidContainer,
            "contains",
            Fluid.TaintedWater
        )
        snapshot.containsTaintedWater = contains == true
    end

    snapshot.plainWater =
        primaryType == "Water"
        or primaryType == "TaintedWater"
        or (primaryType == nil and snapshot.containsTaintedWater)
    snapshot.alcoholic = snapshot.properties ~= nil
        and (tonumber(snapshot.properties.alcohol) or 0) > 0

    return snapshot
end

function ConsumptionManager.isPlainWater(value)
    local snapshot = value

    if type(snapshot) ~= "table" then
        snapshot = ConsumptionManager.snapshotFluid(value)
    end

    return snapshot ~= nil and snapshot.plainWater == true
end

function ConsumptionManager.snapshotItem(item)
    if item == nil then
        return nil
    end

    local fluid = ConsumptionManager.snapshotFluid(
        ConsumptionManager.getFluidContainer(item)
    )
    local alcoholic = booleanMethod(item, "isAlcoholic")
        or (numberMethod(item, "getAlcoholPower") or 0) > 0
        or (fluid ~= nil and fluid.alcoholic == true)

    return {
        fullType = stringMethod(item, "getFullType"),
        displayName = stringMethod(item, "getDisplayName"),
        fresh = booleanMethod(item, "isFresh"),
        frozen = booleanMethod(item, "isFrozen"),
        burnt = booleanMethod(item, "isBurnt"),
        cooked = booleanMethod(item, "isCooked"),
        cookable = booleanMethod(item, "isCookable"),
        goodHot = booleanMethod(item, "isGoodHot"),
        heat = numberMethod(item, "getHeat"),
        eatType = stringMethod(item, "getEatType"),
        evolvedRecipeName =
            stringMethod(item, "getEvolvedRecipeName"),
        alcoholic = alcoholic,
        alcoholPower = numberMethod(item, "getAlcoholPower") or 0,
        smokable = ConsumptionManager.isSmokable(item),
        fluid = fluid,
    }
end

function ConsumptionManager.isAlcoholic(value)
    if value == nil then
        return false
    end

    if type(value) == "table" then
        if value.alcoholic ~= nil then
            return value.alcoholic == true
        end

        if value.properties ~= nil then
            return (tonumber(value.properties.alcohol) or 0) > 0
        end
    end

    local itemSnapshot = ConsumptionManager.snapshotItem(value)
    return itemSnapshot ~= nil and itemSnapshot.alcoholic == true
end

local function normalizeKinds(kinds)
    if kinds == nil then
        return nil
    end

    if type(kinds) == "string" then
        return { [kinds] = true }
    end

    assert(type(kinds) == "table", "observer kinds must be a table")

    local normalized = {}
    for key, value in pairs(kinds) do
        if type(key) == "number" then
            normalized[tostring(value)] = true
        elseif value == true then
            normalized[tostring(key)] = true
        end
    end

    return normalized
end

local function orderedObservers()
    if not ConsumptionManager._observerOrderDirty then
        return ConsumptionManager._orderedObservers
    end

    local ordered = {}
    for _, observer in pairs(ConsumptionManager._observers) do
        ordered[#ordered + 1] = observer
    end

    table.sort(ordered, function(left, right)
        if left.priority == right.priority then
            return left.id < right.id
        end

        return left.priority < right.priority
    end)

    ConsumptionManager._orderedObservers = ordered
    ConsumptionManager._observerOrderDirty = false
    return ordered
end

local function scopeAllows(observer, context)
    local scope = observer.scope or Runtime.Scope.AUTHORITATIVE

    if scope == Runtime.Scope.AUTHORITATIVE then
        return not context.isClient
    elseif scope == Runtime.Scope.SERVER then
        return context.isServer
    elseif scope == Runtime.Scope.CLIENT then
        return context.isClient
    elseif scope == Runtime.Scope.LOCAL then
        if context.isServer then
            return false
        end

        local localPlayer = Util.safeCall(true, function()
            return context.character:isLocalPlayer()
        end)
        return localPlayer == true
    end

    return true
end

local function observerIsEligible(observer, context)
    if observer.kinds ~= nil and observer.kinds[context.kind] ~= true then
        return false
    end

    if not scopeAllows(observer, context) then
        return false
    end

    if context.character == nil then
        return observer.allowNoCharacter == true
    end

    if not observer.allowDead and Util.isDead(context.character) then
        return false
    end

    if observer.traitId ~= nil
        and not Traits.has(context.character, observer.traitId) then
        return false
    end

    if type(observer.when) == "function" then
        local succeeded, applies = pcall(observer.when, context)

        if not succeeded then
            log:error("condition %s failed: %s", observer.id, applies)
            return false
        end

        return applies == true
    end

    return true
end

local function applyObserver(observer, context)
    if not observerIsEligible(observer, context) then
        return
    end

    context.observerId = observer.id
    context.definition = observer

    if observer.effects ~= nil then
        local effects = observer.effects

        if type(effects) == "function" then
            local succeeded, resolved = pcall(effects, context)
            if not succeeded then
                log:error("effects %s failed: %s", observer.id, resolved)
                return
            end

            effects = resolved
        end

        local succeeded, result = pcall(
            Effects.apply,
            context.character,
            effects,
            context
        )

        if not succeeded then
            log:error("effects %s failed: %s", observer.id, result)
            return
        end

        context.effectResults = result
    end

    if type(observer.onConsume) == "function" then
        local succeeded, problem = pcall(observer.onConsume, context)
        if not succeeded then
            log:error("observer %s failed: %s", observer.id, problem)
        end
    end
end

function ConsumptionManager.dispatch(context)
    if type(context) ~= "table" then
        return false
    end

    context.isClient = Util.isClientContext()
    context.isServer = Util.isServerContext()
    context.isSingleplayer = Util.isSingleplayerContext()
    context.nowMs = context.nowMs or Util.nowMilliseconds()
    context.worldAgeHours =
        context.worldAgeHours or Util.worldAgeHours()
    context.characterKey = Util.characterKey(context.character)
    context.characterName = Util.characterName(context.character)

    local observers = orderedObservers()
    for index = 1, #observers do
        applyObserver(observers[index], context)
    end

    return true
end

local function serializableContext(context)
    return {
        kind = context.kind,
        source = context.source,
        fullType = context.fullType,
        portion = context.portion,
        liters = context.liters,
        completed = context.completed == true,
        interrupted = context.interrupted == true,
        itemSnapshot = context.itemSnapshot,
        fluidSnapshot = context.fluidSnapshot,
    }
end

local function emit(context)
    if context == nil or context.character == nil then
        return false
    end

    context.portion = ConsumptionManager.normalizePortion(
        context.portion,
        context.kind == ConsumptionManager.Kind.FOOD and 1 or 0
    )
    context.liters = math.max(0, tonumber(context.liters) or 0)
    context.fullType = context.fullType
        or (context.itemSnapshot and context.itemSnapshot.fullType)

    if context.portion <= 0 and context.liters <= 0
        and context.kind ~= ConsumptionManager.Kind.PILL then
        return false
    end

    if Util.isClientContext() then
        -- Local/client observers may drive presentation immediately. Gameplay
        -- observers run after the serialized event reaches the server.
        ConsumptionManager.dispatch(context)
        Network.sendToServer(
            context.character,
            ConsumptionManager.NETWORK_COMMAND,
            serializableContext(context)
        )
        return true
    end

    if Util.isServerContext() then
        -- Player timed actions are reported by their owning client. Ignoring
        -- a possible mirrored server action prevents applying the same meal
        -- twice on server configurations that reconstruct timed actions.
        return false
    end

    return ConsumptionManager.dispatch(context)
end

local function makeContext(action, kind, source)
    return {
        character = action and action.character or nil,
        action = action,
        kind = kind,
        source = source,
        completed = false,
        interrupted = false,
        fromNetwork = false,
    }
end

local function foodBefore(context, partial)
    local action = context.action
    local state = TimedActionManager.getActionState(action, STATE_OWNER)
    if state.foodSnapshot ~= nil then
        return
    end

    local food = partial and context.arguments[1] or action.item
    local progress = partial and tonumber(context.arguments[2]) or 1
    if partial and progress ~= nil and progress > 0.95 then
        progress = 1
    end

    local requested = ConsumptionManager.normalizePortion(
        action.percentage,
        1
    )
    state.foodItem = food
    state.foodSnapshot = ConsumptionManager.snapshotItem(food)
    state.foodPortion = partial
        and requested * Util.clamp(progress or 0, 0, 1)
        or requested
end

local function foodAfter(context, partial)
    local action = context.action
    local state = TimedActionManager.getActionState(action, STATE_OWNER)

    if state.foodEmitted
        or (not partial and context.completed ~= true) then
        return
    end

    state.foodEmitted = true
    local event = makeContext(
        action,
        ConsumptionManager.Kind.FOOD,
        partial and ConsumptionManager.Source.FOOD_PARTIAL
            or ConsumptionManager.Source.FOOD_COMPLETE
    )
    event.item = state.foodItem
    event.itemSnapshot = state.foodSnapshot
    event.portion = state.foodPortion
    event.completed = not partial
    event.interrupted = partial
    emit(event)
end

local function fluidActionSnapshot(context)
    local state = TimedActionManager.getActionState(
        context.action,
        STATE_OWNER
    )

    if state.fluidStartAmount ~= nil then
        return
    end

    local container = context.action.fluidContainer
    if container == nil then
        return
    end

    state.fluidContainer = container
    state.fluidStartAmount = numberMethod(container, "getAmount") or 0
    state.fluidSnapshot = ConsumptionManager.snapshotFluid(container)
    state.fluidItem = context.action.item
    state.fluidItemSnapshot = ConsumptionManager.snapshotItem(
        context.action.item
    )
end

local function settleFluidAction(context, completed)
    local action = context.action
    local state = TimedActionManager.getActionState(action, STATE_OWNER)
    if state.fluidSettled then
        return
    end

    state.fluidSettled = true
    local container = state.fluidContainer or action.fluidContainer
    local amountAfter = numberMethod(container, "getAmount")
    local consumed = 0

    if state.fluidStartAmount ~= nil and amountAfter ~= nil then
        consumed = math.max(0, state.fluidStartAmount - amountAfter)
    end

    local event = makeContext(
        action,
        ConsumptionManager.Kind.FLUID,
        ConsumptionManager.Source.FLUID_CONTAINER
    )
    event.item = state.fluidItem
    event.itemSnapshot = state.fluidItemSnapshot
    event.fluidContainer = container
    event.fluidSnapshot = state.fluidSnapshot
    event.liters = consumed
    event.completed = completed == true
    event.interrupted = completed ~= true
    emit(event)
end

local function bottleBefore(context)
    local action = context.action
    local state = TimedActionManager.getActionState(action, STATE_OWNER)
    local item = action.item or context.arguments[1]
    local container = ConsumptionManager.getFluidContainer(item)

    state.bottleItem = item
    state.bottleItemSnapshot = ConsumptionManager.snapshotItem(item)
    state.bottleContainer = container
    state.bottleFluidSnapshot =
        ConsumptionManager.snapshotFluid(container)
    state.bottleAmountBefore = numberMethod(container, "getAmount") or 0
end

local function bottleAfter(context)
    local action = context.action
    local state = TimedActionManager.getActionState(action, STATE_OWNER)
    local amountAfter = numberMethod(state.bottleContainer, "getAmount")
    if amountAfter == nil then
        return
    end

    local consumed = math.max(
        0,
        (tonumber(state.bottleAmountBefore) or amountAfter) - amountAfter
    )
    local event = makeContext(
        action,
        ConsumptionManager.Kind.FLUID,
        ConsumptionManager.Source.BOTTLE
    )
    event.item = state.bottleItem
    event.itemSnapshot = state.bottleItemSnapshot
    event.fluidContainer = state.bottleContainer
    event.fluidSnapshot = state.bottleFluidSnapshot
    event.liters = consumed
    event.completed = true
    emit(event)
end

local function worldAmount(action)
    return numberMethod(action and action.waterObject, "getFluidAmount")
end

local function worldTransferBefore(context)
    local action = context.action
    if action.item ~= nil then
        return
    end

    local state = TimedActionManager.getActionState(action, STATE_OWNER)
    state.worldDirectDrink = true
    state.worldAmountBefore = worldAmount(action) or 0

    if state.worldFluidSnapshot == nil then
        local container = callMethod(
            nil,
            action.waterObject,
            "getFluidContainer"
        )
        state.worldFluidSnapshot =
            ConsumptionManager.snapshotFluid(container) or {
                primaryType = "Water",
                plainWater = true,
                amount = state.worldAmountBefore,
            }
    end
end

local function worldTransferAfter(context)
    local action = context.action
    local state = TimedActionManager.getActionState(action, STATE_OWNER)
    if not state.worldDirectDrink then
        return
    end

    local amountAfter = worldAmount(action)
    if amountAfter == nil then
        return
    end

    local consumed = math.max(
        0,
        (tonumber(state.worldAmountBefore) or amountAfter) - amountAfter
    )
    state.worldConsumed = (tonumber(state.worldConsumed) or 0) + consumed
end

local function settleWorldAction(context, completed)
    local action = context.action
    local state = TimedActionManager.getActionState(action, STATE_OWNER)
    if state.worldSettled or not state.worldDirectDrink then
        return
    end

    state.worldSettled = true
    local event = makeContext(
        action,
        ConsumptionManager.Kind.FLUID,
        ConsumptionManager.Source.WORLD_WATER
    )
    event.fluidSnapshot = state.worldFluidSnapshot
    event.liters = tonumber(state.worldConsumed) or 0
    event.completed = completed == true
    event.interrupted = completed ~= true
    emit(event)
end

local function pillBefore(context)
    local state = TimedActionManager.getActionState(
        context.action,
        STATE_OWNER
    )
    local item = context.action.item
        or context.action.pill
        or context.arguments[1]

    state.pillItem = item
    state.pillSnapshot = ConsumptionManager.snapshotItem(item)
end

local function pillAfter(context)
    if context.completed ~= true then
        return
    end

    local action = context.action
    local state = TimedActionManager.getActionState(action, STATE_OWNER)
    if state.pillEmitted then
        return
    end

    state.pillEmitted = true
    local event = makeContext(
        action,
        ConsumptionManager.Kind.PILL,
        ConsumptionManager.Source.PILL
    )
    event.item = state.pillItem
    event.itemSnapshot = state.pillSnapshot
    event.portion = 1
    event.completed = true
    emit(event)
end

local function registerHook(specification)
    local registered = TimedActionManager.register(specification)
    return registered ~= nil
end

local function installHooks()
    if ConsumptionManager._hooksInstalled then
        return true
    end

    require "TimedActions/ISEatFoodAction"
    require "TimedActions/ISDrinkFluidAction"
    require "TimedActions/ISDrinkFromBottle"
    require "TimedActions/ISTakeWaterAction"
    require "TimedActions/ISTakePillAction"

    local hooks = {
        {
            id = STATE_OWNER .. ":food-complete",
            target = ISEatFoodAction,
            className = "ISEatFoodAction",
            method = "complete",
            before = function(context) foodBefore(context, false) end,
            after = function(context) foodAfter(context, false) end,
        },
        {
            id = STATE_OWNER .. ":food-partial",
            target = ISEatFoodAction,
            className = "ISEatFoodAction",
            method = "eat",
            before = function(context) foodBefore(context, true) end,
            after = function(context) foodAfter(context, true) end,
        },
        {
            id = STATE_OWNER .. ":fluid-update",
            target = ISDrinkFluidAction,
            className = "ISDrinkFluidAction",
            method = "updateEat",
            before = fluidActionSnapshot,
        },
        {
            id = STATE_OWNER .. ":fluid-complete",
            target = ISDrinkFluidAction,
            className = "ISDrinkFluidAction",
            method = "complete",
            after = function(context)
                settleFluidAction(context, context.completed)
            end,
        },
        {
            id = STATE_OWNER .. ":fluid-stop",
            target = ISDrinkFluidAction,
            className = "ISDrinkFluidAction",
            method = "stop",
            after = function(context) settleFluidAction(context, false) end,
        },
        {
            id = STATE_OWNER .. ":bottle-drink",
            target = ISDrinkFromBottle,
            className = "ISDrinkFromBottle",
            method = "drink",
            before = bottleBefore,
            after = bottleAfter,
        },
        {
            id = STATE_OWNER .. ":world-transfer",
            target = ISTakeWaterAction,
            className = "ISTakeWaterAction",
            method = "transferFluid",
            before = worldTransferBefore,
            after = worldTransferAfter,
        },
        {
            id = STATE_OWNER .. ":world-complete",
            target = ISTakeWaterAction,
            className = "ISTakeWaterAction",
            method = "complete",
            after = function(context)
                settleWorldAction(context, context.completed)
            end,
        },
        {
            id = STATE_OWNER .. ":world-stop",
            target = ISTakeWaterAction,
            className = "ISTakeWaterAction",
            method = "stop",
            after = function(context) settleWorldAction(context, false) end,
        },
        {
            id = STATE_OWNER .. ":pill-complete",
            target = ISTakePillAction,
            className = "ISTakePillAction",
            method = "complete",
            before = pillBefore,
            after = pillAfter,
        },
    }

    local installed = true
    for index = 1, #hooks do
        if not registerHook(hooks[index]) then
            installed = false
        end
    end

    ConsumptionManager._hooksInstalled = installed
    if installed then
        log:debug("central consumption hooks installed")
    end

    return installed
end

local function validNetworkContext(context)
    if type(context.args) ~= "table" then
        return false
    end

    local kind = context.args.kind
    return kind == ConsumptionManager.Kind.FOOD
        or kind == ConsumptionManager.Kind.FLUID
        or kind == ConsumptionManager.Kind.PILL
end

local function installNetwork()
    if ConsumptionManager._networkInstalled then
        return
    end

    Network.registerServerHandler({
        id = ConsumptionManager.NETWORK_COMMAND,
        cooldownMs = 0,
        validate = validNetworkContext,
        handle = function(networkContext, args)
            local event = {
                character = networkContext.character,
                kind = args.kind,
                source = tostring(args.source or "network"),
                fullType = args.fullType and tostring(args.fullType) or nil,
                portion = ConsumptionManager.normalizePortion(
                    args.portion,
                    0
                ),
                liters = Util.clamp(
                    tonumber(args.liters) or 0,
                    0,
                    ConsumptionManager.MAX_NETWORK_LITERS
                ),
                completed = args.completed == true,
                interrupted = args.interrupted == true,
                itemSnapshot = type(args.itemSnapshot) == "table"
                    and args.itemSnapshot or nil,
                fluidSnapshot = type(args.fluidSnapshot) == "table"
                    and args.fluidSnapshot or nil,
                fromNetwork = true,
            }

            if event.kind ~= ConsumptionManager.Kind.PILL
                and event.portion <= 0 and event.liters <= 0 then
                return
            end

            ConsumptionManager.dispatch(event)
        end,
    })

    ConsumptionManager._networkInstalled = true
end


function ConsumptionManager.unregisterObserver(id)
    local key = tostring(id)
    if ConsumptionManager._observers[key] == nil then
        return false
    end

    ConsumptionManager._observers[key] = nil
    ConsumptionManager._observerOrderDirty = true
    return true
end


function ConsumptionManager.registerObserver(specification)
    assert(type(specification) == "table", "consumption observer is required")
    assert(Util.isNonEmptyString(specification.id), "observer id is required")
    assert(
        type(specification.onConsume) == "function"
            or specification.effects ~= nil,
        "onConsume callback or effects are required"
    )

    local observer = Util.copyShallow(specification)
    observer.priority = tonumber(observer.priority) or 500
    observer.scope = observer.scope or Runtime.Scope.AUTHORITATIVE
    observer.allowDead = observer.allowDead == true
    observer.kinds = normalizeKinds(observer.kinds)

    ConsumptionManager._observers[observer.id] = observer
    ConsumptionManager._observerOrderDirty = true
    installNetwork()

    -- Dedicated servers receive serialized consumption events and do not need
    -- client timed-action classes to exist at all.
    if not Util.isServerContext() then
        installHooks()
    end

    Logger.debug(
        "ConsumptionManager",
        observer.debug,
        "registered observer %s",
        observer.id
    )

    return observer
end


ConsumptionManager.registerRule = ConsumptionManager.registerObserver
ConsumptionManager.ensureInstalled = function()
    installNetwork()

    if Util.isServerContext() then
        return true
    end

    return installHooks()
end

return ConsumptionManager
