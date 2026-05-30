-- /lua/casino_network.lua
local internet = require("internet")
local config = require("casino_config")

local net = {}

function net.request(method, path, data)
    if not config.firebase_url or config.firebase_url == "" then
        return false, "URL базы данных не настроен в casino_config.lua"
    end
    
    -- Добавляем главный путь казино ко всем запросам
    local full_path = "/" .. (config.main_db_path or "casino") .. (path or "") .. ".json"

    local url = config.firebase_url .. full_path
    
    if config.db_secret and config.db_secret ~= "" then
        url = url .. "?auth=" .. config.db_secret
    end
    
    local headers = {}
    if data then headers["Content-Type"] = "application/json" end
    
    -- Firebase REST API использует X-HTTP-Method-Override для PATCH, но PUT и POST работают напрямую.
    if method == "PATCH" or method == "PUT" then
        headers["X-HTTP-Method-Override"] = method
    end

    local success, response = pcall(function()
        -- Для PUT/PATCH/POST отправляем как POST, для GET как GET
        local http_method = (method == "GET") and "GET" or "POST"
        local handle = internet.request(url, data, headers, http_method)
        local result = ""
        for chunk in handle do result = result .. chunk end
        return result
    end)
    
    if success then return true, response else return false, "Ошибка сети: " .. tostring(response) end
end

function net.get(path) return net.request("GET", path) end
function net.put(path, data) return net.request("PUT", path, data) end
function net.patch(path, data) return net.request("PATCH", path, data) end
-- POST для Firebase создает уникальный ID, что полезно для логов
function net.post(path, data) return net.request("POST", path, data) end

return net
