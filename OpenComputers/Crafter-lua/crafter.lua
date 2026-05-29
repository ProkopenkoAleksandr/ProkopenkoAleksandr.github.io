-- /lua/crafter.lua
-- Автоматическое пополнение МЭ-склада товарами магазина.
-- Раз в config.crafter_interval секунд:
--   1. Читает список товаров (через Firebase /shop, либо локальный /home/shop_data.json).
--   2. Через me_interface получает текущий stock каждого товара.
--   3. Если stock <= порога и нет активного crafting-job — заказывает крафт.
--   4. Логирует действия (локально и в Firebase /logs).
--
-- Можно запускать на отдельном OC-компьютере (нужны: internet card, me_interface).
-- Закрытие: Ctrl+Alt+C.

local component = require("component")
local event = require("event")
local os = require("os")
local io = require("io")
local fs = require("filesystem")
local computer = require("computer")
local config = require("config")
local network = require("network")
local json = require("json")

-- === Настройки (с дефолтами) ===
local INTERVAL = tonumber(config.crafter_interval) or 300  -- сек между проходами
local THRESHOLD = tonumber(config.crafter_threshold) or 0   -- заказывать если stock <= threshold
local DEFAULT_AMOUNT = tonumber(config.crafter_amount) or 64  -- сколько штук в одном заказе
local ENABLED = (config.crafter_enabled ~= false)            -- true по умолчанию

-- Активные крафтинги: key="id|damage" → CPU job
local activeJobs = {}

-- =========================================================
-- ВРЕМЯ И ЛОГГИРОВАНИЕ (по тому же шаблону что в main.lua)
-- =========================================================
local function formatUnixTime(unix)
    local z = math.floor(unix / 86400) + 719468
    local era = math.floor((z >= 0 and z or (z - 146096)) / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365)
    local y = yoe + era * 400
    local doy = doe - math.floor((365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100)))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp + (mp < 10 and 3 or -9)
    y = y + (m <= 2 and 1 or 0)
    local h = math.floor((unix % 86400) / 3600)
    local min = math.floor((unix % 3600) / 60)
    local s = math.floor(unix % 60)
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", y, m, d, h, min, s)
end

local function getRealTime()
    local tz = tonumber(config.timezone) or 0
    local tmp_file = "/home/HostTime.tmp"
    local f = io.open(tmp_file, "w")
    if f then
        f:write(""); f:close()
        local lm = fs.lastModified(tmp_file)
        fs.remove(tmp_file)
        if lm and lm > 0 then return formatUnixTime(math.floor(lm/1000) + tz*3600) end
    end
    return os.date("%Y-%m-%d %H:%M:%S") .. " (игр)"
end

local function log(action, details)
    local time = getRealTime()
    local line = string.format("[%s] %s | crafter | %s", time, action, details)
    print(line)
    local f = io.open("/home/crafter.log", "a")
    if f then f:write(line .. "\n"); f:close() end
    -- ротация лога
    local sz = fs.size("/home/crafter.log")
    if sz and sz > 100000 then
        local lines = {}
        local fr = io.open("/home/crafter.log", "r")
        if fr then for l in fr:lines() do table.insert(lines, l) end; fr:close() end
        local fw = io.open("/home/crafter.log", "w")
        if fw then
            local start = math.max(1, #lines - 200)
            for i = start, #lines do fw:write(lines[i] .. "\n") end
            fw:close()
        end
    end
    if config.use_database then
        pcall(function()
            network.request("POST", "/logs", json.encode({
                time = time, action = action, user = "crafter", details = details
            }))
        end)
    end
end

-- =========================================================
-- ИСТОЧНИК СПИСКА ТОВАРОВ
-- =========================================================
local function loadShopItems()
    -- сначала пробуем БД (актуальный список)
    if config.use_database and component.isAvailable("internet") then
        local ok, res = network.get("/shop")
        if ok and res and res ~= "null" then
            local parsed = json.decode(res)
            if parsed and parsed.items then
                if type(parsed.items) == "table" then
                    local arr = {}
                    if #parsed.items > 0 then arr = parsed.items
                    else for _, v in pairs(parsed.items) do table.insert(arr, v) end end
                    return arr
                end
            end
        end
    end
    -- фоллбек на локальный shop_data.json (если crafter живёт на том же компе)
    local f = io.open("/home/shop_data.json", "r")
    if f then
        local data = f:read("*a"); f:close()
        if data and data ~= "" then
            local parsed = json.decode(data)
            if parsed and parsed.items then return parsed.items end
        end
    end
    return nil
end

-- =========================================================
-- ЧТЕНИЕ СТОКОВ ИЗ МЭ
-- =========================================================
local function getStocks()
    local stocks = {}
    local got = false
    for addr in component.list("me_interface") do
        local proxy = component.proxy(addr)
        local ok, items = pcall(function() return proxy.getItemsInNetwork() end)
        if ok and items then
            for _, it in ipairs(items) do
                local key = (it.name or "") .. "|" .. math.floor(it.damage or 0)
                stocks[key] = (stocks[key] or 0) + (it.size or 0)
            end
            got = true
            break
        end
    end
    return stocks, got
end

-- =========================================================
-- ЗАКАЗ КРАФТА
-- =========================================================
local function requestCraft(id, damage, amount)
    for addr in component.list("me_interface") do
        local proxy = component.proxy(addr)
        local ok, list = pcall(function() return proxy.getCraftables({ name = id, damage = damage }) end)
        if ok and list and #list > 0 then
            local craft = list[1]
            local ok_r, job = pcall(function() return craft.request(amount) end)
            if ok_r and job then return job end
        end
    end
    return nil
end

local function pruneFinishedJobs()
    for k, job in pairs(activeJobs) do
        local done_ok, done = pcall(function() return job.isDone() end)
        local cancel_ok, cancel = pcall(function() return job.isCanceled() end)
        local failed_ok, failed = pcall(function() return job.hasFailed() end)
        if (done_ok and done) or (cancel_ok and cancel) or (failed_ok and failed) then
            activeJobs[k] = nil
            log("КРАФТ ЗАВЕРШЁН", k)
        end
    end
end

-- =========================================================
-- ОДНА ИТЕРАЦИЯ
-- =========================================================
local function tick()
    if not ENABLED then return end
    pruneFinishedJobs()
    local items = loadShopItems()
    if not items then log("ОШИБКА", "Не удалось загрузить shop/items"); return end

    local stocks, gotStocks = getStocks()
    if not gotStocks then log("ОШИБКА", "Нет связи с me_interface"); return end

    local requested = 0
    local skipped_active = 0
    local not_craftable = 0
    for _, it in ipairs(items) do
        if it.id and it.id ~= "" then
            local dmg = math.floor(tonumber(it.damage) or 0)
            local key = it.id .. "|" .. dmg
            local stock = stocks[key] or 0
            local target = tonumber(it.craft_amount) or DEFAULT_AMOUNT

            if stock <= THRESHOLD then
                if activeJobs[key] then
                    skipped_active = skipped_active + 1
                else
                    local job = requestCraft(it.id, dmg, target)
                    if job then
                        activeJobs[key] = job
                        requested = requested + 1
                        log("ЗАКАЗАН КРАФТ", (it.name or it.id) .. " x" .. target
                            .. " (stock=" .. stock .. ", id=" .. it.id .. ", damage=" .. dmg .. ")")
                    else
                        not_craftable = not_craftable + 1
                    end
                end
            end
        end
    end

    if requested > 0 or skipped_active > 0 then
        log("ИТЕРАЦИЯ", string.format(
            "товаров=%d, заказано=%d, уже_крафтится=%d, не_craftable=%d",
            #items, requested, skipped_active, not_craftable))
    end
end

-- =========================================================
-- ЦИКЛ
-- =========================================================
print("=== АВТОКРАФТ МАГАЗИНА ===")
print(string.format("Интервал: %d с, порог: %d, заказ по: %d шт", INTERVAL, THRESHOLD, DEFAULT_AMOUNT))
print("Источник: " .. (config.use_database and "Firebase /shop" or "локальный /home/shop_data.json"))
print("Закрытие: Ctrl+Alt+C")
log("СТАРТ", string.format("interval=%ds, threshold=%d, amount=%d",
    INTERVAL, THRESHOLD, DEFAULT_AMOUNT))

while true do
    local ok, err = pcall(tick)
    if not ok then log("FATAL_TICK", tostring(err)) end

    -- ждём INTERVAL секунд, реагируем на interrupted (Ctrl+Alt+C)
    local target_uptime = computer.uptime() + INTERVAL
    while computer.uptime() < target_uptime do
        local ev = event.pull(1, "interrupted")
        if ev then
            log("СТОП", "Остановлено пользователем")
            os.exit()
        end
    end
end
