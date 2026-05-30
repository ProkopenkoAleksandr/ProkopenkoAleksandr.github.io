-- /lua/casino_installer.lua
local internet = require("internet")

-- ССЫЛКА НА ТВОЙ РЕПОЗИТОРИЙ НА GITHUB
local repo = "https://raw.githubusercontent.com/ProkopenkoAleksandr/ProkopenkoAleksandr.github.io/refs/heads/main/OpenComputers/casino/"

local files = {
    "casino_config.lua",
    "casino_network.lua",
    "casino_me_logic.lua",
    "casino_gui.lua",
    "casino_json.lua",
    "casino_main.lua"
}

print("=== УСТАНОВКА КАЗИНО ===")
print("Подключение к GitHub...\n")

for _, file in ipairs(files) do
    io.write("Скачивание " .. file .. " ... ")
    local url = repo .. file:gsub("casino_", "") 
    
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

print("==============================")
print("Установка казино завершена!")
print("Обязательно настройте /home/casino_config.lua")
print("Для первого запуска введите:")
print("casino_main")
print("==============================")
