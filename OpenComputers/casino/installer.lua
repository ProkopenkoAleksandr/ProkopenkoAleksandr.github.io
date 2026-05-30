-- /lua/casino_installer.lua  (Casino)
local internet = require("internet")
local fs = require("filesystem")

local repo = "https://raw.githubusercontent.com/ProkopenkoAleksandr/ProkopenkoAleksandr.github.io/refs/heads/main/OpenComputers/casino/"

-- На компе все файлы лежат с префиксом casino_ чтобы не конфликтовать с shop/obmen
local files = {
    "casino_config.lua",
    "casino_network.lua",
    "casino_me_logic.lua",
    "casino_gui.lua",
    "casino_json.lua",
    "casino_main.lua",
}

print("=== УСТАНОВКА КАЗИНО ===")
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
    -- В репо файлы лежат без casino_ префикса (config.lua, network.lua, …),
    -- мы скачиваем их и сохраняем уже с префиксом.
    local url = repo .. file:gsub("^casino_", "")
    local content, err = download(url)
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

local stale = { "/home/casino_logs.txt", "/home/casino_crash.log", "/home/HostTime.tmp" }
for _, p in ipairs(stale) do
    pcall(function() if fs.exists(p) then fs.remove(p) end end)
end

print("\n==============================")
print("Установка казино завершена!")
print("Не забудь edit /home/casino_config.lua → firebase_url, db_secret, admins.")
print("Запуск: casino_main")
print("==============================")
