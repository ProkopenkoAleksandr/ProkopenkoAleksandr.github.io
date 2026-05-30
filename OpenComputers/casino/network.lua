-- /lua/casino_network.lua
-- Memory-safe HTTP-клиент для Firebase (логика идентична shop/network.lua,
-- разница: все пути префиксируются config.main_db_path = "casino").
--
-- Memory-fixes:
--   1) table.concat вместо `result = result .. chunk` — избегаем O(n^2) аллокаций.
--   2) Явное handle:close() в finally — освобождаем нативный TCP-буфер OC.
--   3) Большие переменные → nil сразу, чтобы Lua-GC мог собрать на event.pull-тике.

local internet = require("internet")
local config = require("casino_config")

local net = {}

local function safeClose(handle)
    if not handle then return end
    pcall(function() handle:close() end)
    pcall(function() if handle.close then handle.close(handle) end end)
end

function net.request(method, path, data)
    if not config.firebase_url or config.firebase_url == "" then
        return false, "URL базы данных не настроен в casino_config.lua"
    end

    local full_path = "/" .. (config.main_db_path or "casino") .. (path or "") .. ".json"
    local url = config.firebase_url .. full_path
    if config.db_secret and config.db_secret ~= "" then
        url = url .. "?auth=" .. config.db_secret
    end

    local headers = {}
    if data then headers["Content-Type"] = "application/json" end
    -- Firebase REST: PUT/PATCH через POST + X-HTTP-Method-Override
    if method == "PATCH" or method == "PUT" then
        headers["X-HTTP-Method-Override"] = method
    end
    local http_method = (method == "GET") and "GET" or "POST"

    local handle
    local success, errOrResult = pcall(function()
        handle = internet.request(url, data, headers, http_method)
        local parts = {}
        for chunk in handle do parts[#parts + 1] = chunk end
        local result = table.concat(parts)
        parts = nil
        return result
    end)

    safeClose(handle)
    handle = nil
    headers = nil
    url = nil
    full_path = nil

    if success then return true, errOrResult else return false, "Ошибка сети: " .. tostring(errOrResult) end
end

function net.get(path)         return net.request("GET",   path) end
function net.put(path, data)   return net.request("PUT",   path, data) end
function net.patch(path, data) return net.request("PATCH", path, data) end
-- POST для Firebase создает уникальный ID, что полезно для логов
function net.post(path, data)  return net.request("POST",  path, data) end

return net
