-- /lua/installer.lua  (ME-Snapshot)
local internet = require("internet")
local fs = require("filesystem")

local repo = "https://raw.githubusercontent.com/ProkopenkoAleksandr/ProkopenkoAleksandr.github.io/refs/heads/main/OpenComputers/me-snapshot/"

local files = {
    "config.lua",
    "network.lua",
    "json.lua",
    "me_snapshot.lua",
    "secret.lua.example",
}

print("=== УСТАНОВКА ME-Snapshot ===")
print("Подключение к GitHub...\n")

local function download(url)
    local handle
    local ok, err_or_content = pcall(function()
        handle = internet.request(url)
        local parts = {}
        for chunk in handle do parts[#parts + 1] = chunk end
        return table.concat(parts)
    end)
    if handle then
        pcall(function() handle:close() end)
        pcall(function() if handle.close then handle.close(handle) end end)
    end
    if ok then return err_or_content end
    return nil, tostring(err_or_content)
end

for _, file in ipairs(files) do
    io.write("Скачивание " .. file .. " ... ")
    local content, err = download(repo .. file)
    if not content then
        print("[ОШИБКА сети: " .. tostring(err) .. "]")
    elseif content:match("404: Not Found") then
        print("[ОШИБКА: Файл не найден на GitHub]")
    else
        local f = io.open("/home/" .. file, "w")
        if f then
            pcall(function() f:write(content) end)
            pcall(function() f:close() end)
            print("[OK]")
        else
            print("[ОШИБКА записи файла]")
        end
    end
end

local stale = { "/home/me_snapshot.log", "/home/HostTime.tmp" }
for _, p in ipairs(stale) do
    pcall(function() if fs.exists(p) then fs.remove(p) end end)
end

print("\n==============================")
print("Установка завершена!")
print("Не забудь edit /home/config.lua → firebase_url, db_secret.")
print("Запуск: me_snapshot")
print("==============================")
