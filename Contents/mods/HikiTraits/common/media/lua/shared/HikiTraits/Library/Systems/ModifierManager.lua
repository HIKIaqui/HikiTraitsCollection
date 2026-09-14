-- Hiki Traits Library
-- Source-based, reversible modifiers that preserve external changes.

require "HikiTraits/Library/Core"

HikiTraits.Library.Systems = HikiTraits.Library.Systems or {}

local Systems = HikiTraits.Library.Systems
Systems.ModifierManager = Systems.ModifierManager or {}

local ModifierManager = Systems.ModifierManager
local Logger = HikiTraits.Library.Logger
local Runtime = HikiTraits.Library.Runtime
local State = HikiTraits.Library.State
local Traits = HikiTraits.Library.Traits
local Util = HikiTraits.Library.Util

local log = Logger.scoped("ModifierManager")
local unpackValues = unpack or table.unpack

ModifierManager.RUNTIME_ID =
    ModifierManager.RUNTIME_ID or "hikitraits:library:modifier-manager"
ModifierManager.STATE_OWNER =
    ModifierManager.STATE_OWNER or "hikitraits:library:modifiers"
ModifierManager.EPSILON = ModifierManager.EPSILON or 0.000001

ModifierManager._channels = ModifierManager._channels or {}
ModifierManager._sources = ModifierManager._sources or {}
ModifierManager._runtimeInstalled =
    ModifierManager._runtimeInstalled or false

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

local function channelStateKey(channelId, field)
    return tostring(channelId) .. ":" .. tostring(field)
end

local function stateNumber(character, channelId, field)
    return tonumber(State.Persistent.get(
        character,
        ModifierManager.STATE_OWNER,
        channelStateKey(channelId, field)
    ))
end

local function setStateNumber(character, channelId, field, value)
    State.Persistent.set(
        character,
        ModifierManager.STATE_OWNER,
        channelStateKey(channelId, field),
        tonumber(value)
    )
end

local function clearChannelState(character, channelId)
    local fields = { "baseline", "applied", "lastWritten" }

    for index = 1, #fields do
        State.Persistent.remove(
            character,
            ModifierManager.STATE_OWNER,
            channelStateKey(channelId, fields[index])
        )
    end
end

local function closeEnough(left, right, epsilon)
    if left == nil or right == nil then
        return false
    end

    return math.abs(left - right) <= epsilon
end

local function normalizeChannel(id, specification)
    assert(Util.isNonEmptyString(id), "modifier channel id is required")
    assert(type(specification) == "table", "channel definition is required")

    local channel = Util.copyShallow(specification)
    channel.id = id
    channel.epsilon = tonumber(channel.epsilon)
        or ModifierManager.EPSILON

    if channel.read == nil and Util.isNonEmptyString(channel.getter) then
        channel.read = function(character)
            local value, succeeded = callMethod(
                nil,
                character,
                channel.getter
            )

            if not succeeded then
                return nil
            end

            return tonumber(value)
        end
    end

    if channel.write == nil and Util.isNonEmptyString(channel.setter) then
        channel.write = function(character, value)
            local _, succeeded = callMethod(
                nil,
                character,
                channel.setter,
                value
            )
            return succeeded
        end
    end

    assert(type(channel.read) == "function", "channel read is required")
    assert(type(channel.write) == "function", "channel write is required")
    assert(
        channel.combine == nil or type(channel.combine) == "function",
        "channel combine must be a function"
    )
    assert(
        channel.apply == nil or type(channel.apply) == "function",
        "channel apply must be a function"
    )

    return channel
end

function ModifierManager.registerChannel(id, specification)
    local channel = normalizeChannel(id, specification)
    ModifierManager._channels[id] = channel
    return channel
end

function ModifierManager.unregisterChannel(id)
    local key = tostring(id)
    if ModifierManager._channels[key] == nil then
        return false
    end

    ModifierManager._channels[key] = nil
    return true
end

function ModifierManager.getChannel(id)
    return ModifierManager._channels[tostring(id)]
end

local function orderedSources(channelId)
    local result = {}

    for _, source in pairs(ModifierManager._sources) do
        if source.channel == channelId then
            result[#result + 1] = source
        end
    end

    table.sort(result, function(left, right)
        if left.priority == right.priority then
            return left.id < right.id
        end

        return left.priority < right.priority
    end)

    return result
end

local function sourceIsActive(source, context)
    if source.enabled == false then
        return false
    end

    if type(source.enabled) == "function" then
        local succeeded, enabled = pcall(source.enabled, context)
        if not succeeded then
            log:error("enabled %s failed: %s", source.id, enabled)
            return false
        end

        if enabled ~= true then
            return false
        end
    end

    if source.traitId ~= nil
        and not Traits.has(context.character, source.traitId) then
        return false
    end

    if type(source.when) == "function" then
        local succeeded, applies = pcall(source.when, context)
        if not succeeded then
            log:error("condition %s failed: %s", source.id, applies)
            return false
        end

        if applies ~= true then
            return false
        end
    end

    return true
end

local function resolveSourceValue(source, context)
    local value = source.value

    if type(value) == "function" then
        local succeeded, resolved = pcall(value, context)
        if not succeeded then
            log:error("value %s failed: %s", source.id, resolved)
            return nil
        end

        value = resolved
    end

    return tonumber(value)
end

local function collectContributions(channel, context)
    local sources = orderedSources(channel.id)
    local contributions = {}

    for index = 1, #sources do
        local source = sources[index]

        if sourceIsActive(source, context) then
            local value = resolveSourceValue(source, context)
            if value ~= nil then
                contributions[#contributions + 1] = {
                    id = source.id,
                    value = value,
                    source = source,
                }
            end
        end
    end

    return contributions
end

local function combineContributions(channel, contributions, context)
    if type(channel.combine) == "function" then
        return tonumber(channel.combine(contributions, context)) or 0
    end

    local total = 0
    for index = 1, #contributions do
        total = total + contributions[index].value
    end

    return total
end

local function inferBaseline(character, channel, current)
    local previousBaseline = stateNumber(character, channel.id, "baseline")
    local previousApplied = stateNumber(character, channel.id, "applied")
    local previousWritten = stateNumber(
        character,
        channel.id,
        "lastWritten"
    )

    if previousBaseline == nil or previousApplied == nil
        or previousWritten == nil then
        return current, 0
    end

    if type(channel.inferBaseline) == "function" then
        local succeeded, baseline = pcall(
            channel.inferBaseline,
            current,
            {
                baseline = previousBaseline,
                applied = previousApplied,
                lastWritten = previousWritten,
            },
            character
        )

        if succeeded and tonumber(baseline) ~= nil then
            return tonumber(baseline), previousApplied
        elseif not succeeded then
            log:error("baseline inference %s failed: %s", channel.id, baseline)
        end
    end

    -- If the value still equals our previous write, our modifier survived.
    -- If it instead equals the stored baseline, the game reset the property
    -- while loading. Any third value is treated as an external live change.
    if closeEnough(current, previousWritten, channel.epsilon) then
        return current - previousApplied, previousApplied
    elseif closeEnough(current, previousBaseline, channel.epsilon) then
        return current, 0
    end

    return current - previousApplied, previousApplied
end

local function writeTarget(character, channel, target, context)
    local succeeded, result = pcall(
        channel.write,
        character,
        target,
        context
    )

    if not succeeded then
        log:error("write %s failed: %s", channel.id, result)
        return false
    end

    if result == false then
        return false
    end

    if type(channel.sync) == "function" then
        local syncSucceeded, problem = pcall(
            channel.sync,
            character,
            context
        )

        if not syncSucceeded then
            log:error("sync %s failed: %s", channel.id, problem)
        end
    end

    return true
end

function ModifierManager.refreshChannel(character, channelOrId, baseContext)
    local channel = channelOrId
    if type(channelOrId) == "string" then
        channel = ModifierManager._channels[channelOrId]
    end

    if character == nil or type(channel) ~= "table" then
        return nil
    end

    local succeeded, rawCurrent = pcall(channel.read, character)
    local current = succeeded and tonumber(rawCurrent) or nil

    if current == nil then
        if not succeeded then
            log:error("read %s failed: %s", channel.id, rawCurrent)
        end
        return nil
    end

    local context = Util.copyShallow(baseContext or {})
    context.character = character
    context.characterKey = Util.characterKey(character)
    context.characterName = Util.characterName(character)
    context.channel = channel
    context.current = current
    context.nowMs = context.nowMs or Util.nowMilliseconds()
    context.worldAgeHours =
        context.worldAgeHours or Util.worldAgeHours()

    local baseline, previousApplied = inferBaseline(
        character,
        channel,
        current
    )
    context.baseline = baseline
    context.previousApplied = previousApplied

    local contributions = collectContributions(channel, context)
    local aggregate = combineContributions(
        channel,
        contributions,
        context
    )
    context.contributions = contributions
    context.aggregate = aggregate

    local target
    if type(channel.apply) == "function" then
        local applied, resolved = pcall(
            channel.apply,
            baseline,
            aggregate,
            contributions,
            context
        )

        if not applied then
            log:error("apply %s failed: %s", channel.id, resolved)
            return nil
        end

        target = tonumber(resolved)
    else
        target = baseline + aggregate
    end

    if target == nil then
        return nil
    end

    target = Util.clamp(target, channel.minimum, channel.maximum)
    local changed = not closeEnough(current, target, channel.epsilon)

    if changed and not writeTarget(character, channel, target, context) then
        return nil
    end

    local after = target
    local readAfterSucceeded, readAfter = pcall(channel.read, character)
    if readAfterSucceeded and tonumber(readAfter) ~= nil then
        after = tonumber(readAfter)
    end

    local actualApplied = after - baseline

    setStateNumber(character, channel.id, "baseline", baseline)
    setStateNumber(character, channel.id, "applied", actualApplied)
    setStateNumber(character, channel.id, "lastWritten", after)

    local result = {
        channel = channel.id,
        before = current,
        after = after,
        baseline = baseline,
        previousApplied = previousApplied,
        requestedAggregate = aggregate,
        applied = actualApplied,
        delta = after - current,
        changed = changed,
        contributions = contributions,
    }

    if type(channel.after) == "function" then
        local afterSucceeded, problem = pcall(
            channel.after,
            context,
            result
        )

        if not afterSucceeded then
            log:error("after %s failed: %s", channel.id, problem)
        end
    end

    return result
end

function ModifierManager.refresh(character, baseContext)
    local results = {}

    if character == nil then
        return results
    end

    for id, channel in pairs(ModifierManager._channels) do
        local hasSource = false

        for _, source in pairs(ModifierManager._sources) do
            if source.channel == id then
                hasSource = true
                break
            end
        end

        local hadApplied = stateNumber(character, id, "applied")
        if hasSource or (hadApplied ~= nil and hadApplied ~= 0) then
            local result = ModifierManager.refreshChannel(
                character,
                channel,
                baseContext
            )
            if result ~= nil then
                results[#results + 1] = result
            end
        end
    end

    return results
end

local function ensureRuntime()
    if ModifierManager._runtimeInstalled then
        return
    end

    Runtime.registerMinute({
        id = ModifierManager.RUNTIME_ID,
        scope = Runtime.Scope.ANY,
        priority = 200,
        run = function(context)
            ModifierManager.refresh(context.character, context)
        end,
    })

    ModifierManager._runtimeInstalled = true
end

local function refreshActivePlayers()
    local players = Runtime.getPlayers(Runtime.Scope.ANY)
    for index = 1, #players do
        ModifierManager.refresh(players[index])
    end
end

function ModifierManager.unregisterSource(id)
    local key = tostring(id)
    if ModifierManager._sources[key] == nil then
        return false
    end

    ModifierManager._sources[key] = nil
    refreshActivePlayers()
    return true
end

function ModifierManager.registerSource(specification)
    assert(type(specification) == "table", "modifier source is required")
    assert(Util.isNonEmptyString(specification.id), "source id is required")
    assert(
        Util.isNonEmptyString(specification.channel),
        "source channel is required"
    )
    assert(
        ModifierManager._channels[specification.channel] ~= nil,
        "unknown modifier channel " .. tostring(specification.channel)
    )
    assert(
        tonumber(specification.value) ~= nil
            or type(specification.value) == "function",
        "source value must be a number or function"
    )

    local source = Util.copyShallow(specification)
    source.priority = tonumber(source.priority) or 500

    ModifierManager._sources[source.id] = source
    ensureRuntime()
    refreshActivePlayers()

    Logger.debug(
        "ModifierManager",
        source.debug,
        "registered source %s on %s",
        source.id,
        source.channel
    )

    return source
end

ModifierManager.register = ModifierManager.registerSource

function ModifierManager.getSource(id)
    return ModifierManager._sources[tostring(id)]
end

function ModifierManager.clearCharacter(character, restore)
    if character == nil then
        return false
    end

    if restore ~= false then
        for id, channel in pairs(ModifierManager._channels) do
            local baseline = stateNumber(character, id, "baseline")
            if baseline ~= nil then
                local context = {
                    character = character,
                    channel = channel,
                    baseline = baseline,
                    aggregate = 0,
                }
                writeTarget(character, channel, baseline, context)
            end
        end
    end

    State.Persistent.clear(character, ModifierManager.STATE_OWNER)
    return true
end

-- B42's explicit additive carrying-capacity field. More channels can be
-- registered by Hiki Traits or compatibility mods without modifying this file.
if ModifierManager._channels.maxWeightDelta == nil then
    ModifierManager.registerChannel("maxWeightDelta", {
        getter = "getMaxWeightDelta",
        setter = "setMaxWeightDelta",
    })
end

return ModifierManager
