-- Hiki Traits Library
-- Consistent logging without making every trait reinvent debugLog().

HikiTraits = HikiTraits or {}
HikiTraits.Library = HikiTraits.Library or {}
HikiTraits.Library.Core = HikiTraits.Library.Core or {}

local Core = HikiTraits.Library.Core
Core.Logger = Core.Logger or {}

local Logger = Core.Logger

Logger.DEBUG = Logger.DEBUG or false
Logger._scopeDebug = Logger._scopeDebug or {}

local function formatMessage(template, ...)
    local message = tostring(template)

    if select("#", ...) == 0 then
        return message
    end

    local succeeded, formatted = pcall(string.format, message, ...)
    if succeeded then
        return formatted
    end

    return message .. " [formatting failed: " .. tostring(formatted) .. "]"
end

local function emit(scope, level, template, ...)
    local prefix = "[HikiTraits]"

    if scope ~= nil and scope ~= "" then
        prefix = prefix .. "[" .. tostring(scope) .. "]"
    end

    if level ~= nil and level ~= "" then
        prefix = prefix .. "[" .. tostring(level) .. "]"
    end

    print(prefix .. " " .. formatMessage(template, ...))
end

function Logger.setDebug(enabled)
    Logger.DEBUG = enabled == true
end

function Logger.setScopeDebug(scope, enabled)
    if scope ~= nil then
        Logger._scopeDebug[tostring(scope)] = enabled == true
    end
end

function Logger.isDebugEnabled(scope, source)
    if type(source) == "function" then
        local succeeded, enabled = pcall(source)
        if succeeded then
            return enabled == true
        end
    elseif source ~= nil then
        return source == true
    end

    if scope ~= nil and Logger._scopeDebug[tostring(scope)] ~= nil then
        return Logger._scopeDebug[tostring(scope)] == true
    end

    return Logger.DEBUG == true
end

function Logger.debug(scope, source, template, ...)
    if Logger.isDebugEnabled(scope, source) then
        emit(scope, "DEBUG", template, ...)
    end
end

function Logger.info(scope, template, ...)
    emit(scope, nil, template, ...)
end

function Logger.warn(scope, template, ...)
    emit(scope, "WARN", template, ...)
end

function Logger.error(scope, template, ...)
    emit(scope, "ERROR", template, ...)
end

function Logger.scoped(scope, debugSource)
    local scoped = {}

    function scoped:debug(template, ...)
        Logger.debug(scope, debugSource, template, ...)
    end

    function scoped:info(template, ...)
        Logger.info(scope, template, ...)
    end

    function scoped:warn(template, ...)
        Logger.warn(scope, template, ...)
    end

    function scoped:error(template, ...)
        Logger.error(scope, template, ...)
    end

    return scoped
end

return Logger
