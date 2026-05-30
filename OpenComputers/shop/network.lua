-- /lua/network.lua
local internet = require("internet")
local config = require("config")

local net = {}

function net.request(method, path, data)
    -- Защита: если ссылка не указана, отменяем запрос
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

    local success, response = pcall(function()
        local handle = internet.request(url, data, headers, method)
        local result = ""
        for chunk in handle do result = result .. chunk end
        return result
    end)
    
    if success then return true, response else return false, "Ошибка сети" end
end

function net.get(path) return net.request("GET", path) end
function net.put(path, data) return net.request("PUT", path, data) end
function net.patch(path, data) return net.request("PATCH", path, data) end

return net
