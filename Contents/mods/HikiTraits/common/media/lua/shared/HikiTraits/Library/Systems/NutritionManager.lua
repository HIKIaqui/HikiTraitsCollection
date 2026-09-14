-- Hiki Traits Library
-- Nutrition snapshots, mutations, conditions, and scheduled trait rules.

require "HikiTraits/Library/Core"

HikiTraits.Library.Systems = HikiTraits.Library.Systems or {}

local Systems = HikiTraits.Library.Systems
Systems.NutritionManager = Systems.NutritionManager or {}

local NutritionManager = Systems.NutritionManager
local Effects = HikiTraits.Library.Effects
local Logger = HikiTraits.Library.Logger
local Runtime = HikiTraits.Library.Runtime
local Util = HikiTraits.Library.Util

local log = Logger.scoped("NutritionManager")
local unpackValues = unpack or table.unpack

NutritionManager.EPSILON = NutritionManager.EPSILON or 0.000001
NutritionManager._rules = NutritionManager._rules or {}

NutritionManager.Metric = NutritionManager.Metric or {
    WEIGHT = "weight",
    CALORIES = "calories",
    CARBOHYDRATES = "carbohydrates",
    LIPIDS = "lipids",
    PROTEINS = "proteins",
}

local METRICS = {
    weight = { getter = "getWeight", setter = "setWeight" },
    calories = { getter = "getCalories", setter = "setCalories" },
    carbohydrates = {
        getter = "getCarbohydrates",
        setter = "setCarbohydrates",
    },
    lipids = { getter = "getLipids", setter = "setLipids" },
    proteins = { getter = "getProteins", setter = "setProteins" },
}

local METRIC_ALIASES = {
    carb = "carbohydrates",
    carbs = "carbohydrates",
    carbohydrate = "carbohydrates",
    protein = "proteins",
    lipid = "lipids",
    fat = "lipids",
    fats = "lipids",
}

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

local function normalizeMetric(metric)
    if metric == nil then
        return nil
    end

    local normalized = string.lower(tostring(metric))
    return METRIC_ALIASES[normalized] or normalized
end

local function unchanged(metric, value)
    return {
        metric = metric,
        before = value,
        after = value,
        delta = 0,
        changed = false,
    }
end

function NutritionManager.getNutrition(character)
    if character == nil then
        return nil
    end

    return callMethod(nil, character, "getNutrition")
end

function NutritionManager.get(character, metric)
    local key = normalizeMetric(metric)
    local definition = METRICS[key]
    local nutrition = NutritionManager.getNutrition(character)

    if definition == nil or nutrition == nil then
        return nil
    end

    local value, succeeded = callMethod(
        nil,
        nutrition,
        definition.getter
    )

    if not succeeded then
        return nil
    end

    return tonumber(value)
end

function NutritionManager.hasWeightTrouble(character)
    local nutrition = NutritionManager.getNutrition(character)
    local trouble, succeeded = callMethod(
        false,
        nutrition,
        "characterHaveWeightTrouble"
    )

    return succeeded and trouble == true
end

function NutritionManager.snapshot(character)
    local nutrition = NutritionManager.getNutrition(character)
    if nutrition == nil then
        return nil
    end

    local snapshot = {
        object = nutrition,
        weightTrouble = NutritionManager.hasWeightTrouble(character),
    }

    for metric, _ in pairs(METRICS) do
        snapshot[metric] = NutritionManager.get(character, metric)
    end

    local flags = {
        increasingWeight = "isIncWeight",
        rapidlyIncreasingWeight = "isIncWeightLot",
        decreasingWeight = "isDecWeight",
    }

    for field, method in pairs(flags) do
        local value, succeeded = callMethod(false, nutrition, method)
        snapshot[field] = succeeded and value == true
    end

    return snapshot
end

function NutritionManager.sync(character)
    if character == nil or not Util.isServerContext() then
        return false
    end

    if type(sendPlayerNutrition) ~= "function" then
        return false
    end

    local succeeded, problem = pcall(sendPlayerNutrition, character)
    if not succeeded then
        log:error("nutrition synchronization failed: %s", problem)
        return false
    end

    return true
end

function NutritionManager.set(character, metric, wanted, options)
    options = options or {}

    local key = normalizeMetric(metric)
    local definition = METRICS[key]
    local nutrition = NutritionManager.getNutrition(character)
    local before = NutritionManager.get(character, key)

    if definition == nil or nutrition == nil or before == nil then
        return unchanged(key, before)
    end

    local target = tonumber(wanted)
    if target == nil then
        return unchanged(key, before)
    end

    target = Util.clamp(
        target,
        tonumber(options.minimum),
        tonumber(options.maximum)
    )
    if math.abs(target - before)
        <= (tonumber(options.epsilon) or NutritionManager.EPSILON) then
        return unchanged(key, before)
    end

    local _, succeeded = callMethod(
        nil,
        nutrition,
        definition.setter,
        target
    )
    local after = NutritionManager.get(character, key) or target
    local result = {
        metric = key,
        before = before,
        after = after,
        delta = after - before,
        changed = succeeded
            and math.abs(after - before) > NutritionManager.EPSILON,
    }

    if result.changed and options.sync ~= false then
        NutritionManager.sync(character)
    end

    return result
end

function NutritionManager.change(character, metric, delta, options)
    local current = NutritionManager.get(character, metric)
    if current == nil then
        return unchanged(normalizeMetric(metric), nil)
    end

    return NutritionManager.set(
        character,
        metric,
        current + (tonumber(delta) or 0),
        options
    )
end

function NutritionManager.setWeight(character, value, options)
    return NutritionManager.set(character, "weight", value, options)
end

function NutritionManager.changeWeight(character, delta, options)
    return NutritionManager.change(character, "weight", delta, options)
end

function NutritionManager.matches(snapshot, specification)
    if snapshot == nil then
        return false
    end

    local spec = specification or {}
    local metric = normalizeMetric(spec.metric)

    if metric ~= nil then
        local value = tonumber(snapshot[metric])
        if value == nil then
            return false
        end

        local minimum = tonumber(spec.minimum)
        local maximum = tonumber(spec.maximum)
        local above = tonumber(spec.above)
        local below = tonumber(spec.below)

        if spec.minimum ~= nil
            and (minimum == nil or value < minimum) then
            return false
        end

        if spec.maximum ~= nil
            and (maximum == nil or value > maximum) then
            return false
        end

        if spec.above ~= nil
            and (above == nil or value <= above) then
            return false
        end

        if spec.below ~= nil
            and (below == nil or value >= below) then
            return false
        end
    end

    if spec.weightTrouble ~= nil
        and snapshot.weightTrouble ~= (spec.weightTrouble == true) then
        return false
    end

    return true
end

function NutritionManager.condition(specification)
    local spec = Util.copyShallow(specification or {})

    return function(context)
        if context == nil or context.character == nil then
            return false
        end

        local snapshot = context.nutrition
            or NutritionManager.snapshot(context.character)
        context.nutrition = snapshot
        return NutritionManager.matches(snapshot, spec)
    end
end

function NutritionManager.atLeast(metric, minimum)
    return NutritionManager.condition({
        metric = metric,
        minimum = minimum,
    })
end

function NutritionManager.atMost(metric, maximum)
    return NutritionManager.condition({
        metric = metric,
        maximum = maximum,
    })
end

function NutritionManager.between(metric, minimum, maximum)
    return NutritionManager.condition({
        metric = metric,
        minimum = minimum,
        maximum = maximum,
    })
end

function NutritionManager.weightTrouble(wanted)
    return NutritionManager.condition({
        weightTrouble = wanted ~= false,
    })
end

local function applyRule(rule, context)
    context.nutrition = NutritionManager.snapshot(context.character)

    if not NutritionManager.matches(context.nutrition, rule) then
        return false
    end

    if type(rule.when) == "function" then
        local succeeded, applies = pcall(rule.when, context)

        if not succeeded then
            log:error("condition %s failed: %s", rule.id, applies)
            return false
        end

        if applies ~= true then
            return false
        end
    end

    if rule.effects ~= nil then
        local effects = rule.effects
        if type(effects) == "function" then
            local succeeded, resolved = pcall(effects, context)
            if not succeeded then
                log:error("effects %s failed: %s", rule.id, resolved)
                return false
            end

            effects = resolved
        end

        Effects.apply(context.character, effects, context)
    end

    if type(rule.run) == "function" then
        local succeeded, result = pcall(rule.run, context)
        if not succeeded then
            log:error("rule %s failed: %s", rule.id, result)
            return false
        end

        context.runResult = result
    end

    if type(rule.after) == "function" then
        local succeeded, problem = pcall(rule.after, context)
        if not succeeded then
            log:error("after %s failed: %s", rule.id, problem)
        end
    end

    return true
end

function NutritionManager.unregisterRule(id)
    local key = tostring(id)
    NutritionManager._rules[key] = nil
    return Runtime.unregister(key)
end

function NutritionManager.registerRule(specification)
    assert(type(specification) == "table", "nutrition rule is required")
    assert(Util.isNonEmptyString(specification.id), "rule id is required")
    assert(
        specification.effects ~= nil
            or type(specification.run) == "function",
        "nutrition rule requires effects or run"
    )

    local rule = Util.copyShallow(specification)
    rule.metric = normalizeMetric(rule.metric)
    rule.priority = tonumber(rule.priority) or 500
    rule.scope = rule.scope or Runtime.Scope.AUTHORITATIVE

    NutritionManager.unregisterRule(rule.id)
    NutritionManager._rules[rule.id] = rule

    local runtimeSpecification = {
        id = rule.id,
        traitId = rule.traitId,
        priority = rule.priority,
        scope = rule.scope,
        allowDead = rule.allowDead,
        enabled = rule.enabled,
        debug = rule.debug,
        run = function(context)
            return applyRule(rule, context)
        end,
    }

    if tonumber(rule.intervalMs) ~= nil then
        return Runtime.registerInterval(
            tonumber(rule.intervalMs),
            runtimeSpecification
        )
    end

    return Runtime.registerMinute(runtimeSpecification)
end

return NutritionManager
