-- /home/config.lua  (shop)
--
-- Токен НЕ хранится в этом файле — он лежит в /home/secret.lua
-- (который НЕ комитится в git, см. secret.lua.example).
--
-- Если /home/secret.lua не существует или пустой — программа упадёт с понятной
-- ошибкой "pocketbase_token не настроен".

local fs = require("filesystem")
local secret = {}
if fs.exists("/home/secret.lua") then
    local ok, loaded = pcall(dofile, "/home/secret.lua")
    if ok and type(loaded) == "table" then secret = loaded end
end

return {
    pocketbase_url   = "https://prorokius.space",
    pocketbase_token = secret.pocketbase_token or "",
    use_database     = true,

    log_source = "shop",
    timezone   = 3,

    admins = { "Prorokius", "__HAPKOMAH__" },
}
