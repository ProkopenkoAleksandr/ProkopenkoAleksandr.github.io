-- /lua/installer.lua  (ME-Snapshots)
local internet = require("internet")

-- ССЫЛКА НА ПАПКУ С ФАЙЛАМИ В РЕПОЗИТОРИИ НА GITHUB (со слешем на конце)
local repo = "https://raw.githubusercontent.com/ProkopenkoAleksandr/ProkopenkoAleksandr.github.io/refs/heads/main/OpenComputers/ME-Snapshots/"

local files = {
    "config.lua",
    "network.lua",
    "json.lua",
    "me_snapshot.lua",
}

print("=== УСТАНОВКА ME-Snapshots ===")
print("Подключение к GitHub...\n")

for _, file in ipairs(files) do
    io.write("Скачивание " .. file .. " ... ")
    local url = repo .. file
    local success, response = pcall(internet.request, url)
    if success then
        local content = ""
        for chunk in response do content = content .. chunk end
        if content:match("404: Not Found") then
            print("[ОШИБКА: Файл не найден]")
        else
            local f = io.open("/home/" .. file, "w")
            if f then f:write(content); f:close(); print("[OK]")
            else print("[ОШИБКА записи файла]") end
        end
    else
        print("[ОШИБКА сети]")
    end
end

print("\n==============================")
print("Установка успешно завершена!")
print("Запуск программы:")
print("me_snapshot")
print("==============================")
