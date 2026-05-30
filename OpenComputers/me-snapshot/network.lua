-- /lua/network.lua
-- HTTP-клиент для Firebase Realtime DB.
--
-- Memory-safe реализация:
-- 1. Используем table.concat вместо `result = result .. chunk` —
--    последнее даёт O(n^2) аллокаций промежуточных строк (на больших ответах
--    это десятки МБ временного мусора в Lua-heap).
-- 2. Явно закрываем handle через handle:close() / handle.close(handle) —
--    иначе TCP-соединение остаётся открытым в Java-mostе OC, держит буфер
--    и при многократных запросах копится утечка нативной памяти.
-- 3. Очищаем все большие переменные в nil сразу после использования,
--    чтобы Lua-GC смог их собрать на следующем event.pull-тике.

local internet = require("internet")
local config = require("config")

local net = {}

local function safeClose(handle)
    if not handle then return end
    -- В разных версиях OC у handle разный API. Пробуем оба варианта без падения.
    pcall(function() handle:close() end)
    pcall(function() if handle.close then handle.close(handle) end end)
end

function net.request(method, path, data)
    if not config.firebase_url or config.firebase_url == "" then
        return false, "URL базы данных не настроен в config.lua"
    end

    local url = config.firebase_url .. path .. ".json"
    if config.db_secret and config.db_secret ~= "" then
        url = url .. "?auth=" .. config.db_secret
    end

    local headers = {}
    if data then headers["Content-Type"] = "application/json" end
    headers["X-HTTP-Method-Override"] = method

    -- handle вынесен наружу pcall, чтобы можно было гарантированно закрыть в finally
    local handle
    local success, errOrResult = pcall(function()
        handle = internet.request(url, data, headers, method)
        local parts = {}
        for chunk in handle do parts[#parts + 1] = chunk end
        local result = table.concat(parts)
        parts = nil  -- освобождаем массив чанков сразу
        return result
    end)

    safeClose(handle)
    handle = nil
    headers = nil
    url = nil

    if success then return true, errOrResult else return false, "Ошибка сети: " .. tostring(errOrResult) end
end

function net.get(path) return net.request("GET", path) end
function net.put(path, data) return net.request("PUT", path, data) end
function net.patch(path, data) return net.request("PATCH", path, data) end
function net.post(path, data) return net.request("POST", path, data) end

return net
