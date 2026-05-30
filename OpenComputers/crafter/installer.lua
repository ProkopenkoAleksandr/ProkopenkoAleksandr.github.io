-- /lua/installer.lua  (Crafter)
local internet = require("internet")
local fs = require("filesystem")

-- ССЫЛКА НА ПАПКУ С ФАЙЛАМИ В РЕПОЗИТОРИИ НА GITHUB (со слешем на конце)
local repo = "https://raw.githubusercontent.com/ProkopenkoAleksandr/ProkopenkoAleksandr.github.io/refs/heads/main/OpenComputers/crafter/"

local files = {
    "config.lua",
    "network.lua",
    "json.lua",
    "gui.lua",
    "crafter.lua",
}

print("=== УСТАНОВКА АВТОКРАФТЕРА ===")
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

-- Удаляем известные устаревшие файлы от прошлых версий (если остались)
local stale = { "/home/crafter.log", "/home/HostTime.tmp" }
for _, p in ipairs(stale) do
    pcall(function() if fs.exists(p) then fs.remove(p) end end)
end

print("\n==============================")
print("Установка завершена!")
print("Не забудь edit /home/config.lua → firebase_url, db_secret.")
print("Запуск: crafter")
print("==============================")
