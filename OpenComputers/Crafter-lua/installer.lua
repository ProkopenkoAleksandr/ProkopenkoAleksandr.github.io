-- /lua/installer.lua  (Crafter)
local internet = require("internet")

-- ССЫЛКА НА ТВОЙ РЕПОЗИТОРИЙ НА GITHUB (без слеша / на конце)
local repo = "https://https://raw.githubusercontent.com/ProkopenkoAleksandr/ProkopenkoAleksandr.github.io/refs/heads/main/OpenComputers/Crafter-lua/"

local files = {
    "config.lua",
    "network.lua",
    "json.lua",
    "crafter.lua"
}

print("=== УСТАНОВКА АВТОКРАФТЕРА ===")
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
            if f then
                f:write(content)
                f:close()
                print("[OK]")
            else
                print("[ОШИБКА записи файла]")
            end
        end
    else
        print("[ОШИБКА сети]")
    end
end

print("\n==============================")
print("Установка успешно завершена!")
print("Запуск автокрафтера:")
print("crafter")
print("==============================")
