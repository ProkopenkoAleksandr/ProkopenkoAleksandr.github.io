-- /lua/crafter.lua
-- GUI-приложение автокрафта МЭ-склада.
-- - Раз в config.crafter_interval секунд читает /shop и пытается заказать крафт
--   всех товаров, у которых stock <= порога.
-- - Показывает все активные заказы, статус, возраст, кнопку отмены.
-- - Кнопки: тик сейчас, пауза/авто, отменить всё, выход.
-- Закрытие: [ВЫХОД] или Ctrl+Alt+C.

local component = require("component")
local event = require("event")
local os = require("os")
local io = require("io")
local fs = require("filesystem")
local computer = require("computer")
local config = require("config")
local network = require("network")
local json = require("json")
local gui = require("gui")

event.shouldInterrupt = function() return false end

-- ===== Настройки =====
local INTERVAL = tonumber(config.crafter_interval) or 300
local THRESHOLD = tonumber(config.crafter_threshold) or 0
local DEFAULT_AMOUNT = tonumber(config.crafter_amount) or 64
local ENABLED_AT_START = (config.crafter_enabled ~= false)
local maxConcurrent = tonumber(config.crafter_max_concurrent) or 2
if maxConcurrent < 1 then maxConcurrent = 1 end

-- ===== Состояние =====
local activeJobs = {}  -- [key] = {job, name, amount, started_at, key, id, damage, start_stock, produced}
local recentLog = {}   -- лог в памяти (новые сверху)
local MAX_LOG_LINES = 60

local lastTickAt = -INTERVAL  -- чтобы первый тик случился сразу
local secondsToTick = 0
local paused = not ENABLED_AT_START
local meOk = true
local dbOk = false
local totalCompleted = 0
local totalFailed = 0

-- Опрос стоков для прогресса (раз в N секунд)
local PROGRESS_POLL = 5
local lastProgressAt = 0

-- Кэш последнего загруженного списка товаров (для добивания очереди между тиками)
local cachedItems = nil

-- =========================================================
-- УТИЛИТЫ
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
        if lm and lm > 0 then return formatUnixTime(math.floor(lm / 1000) + tz * 3600) end
    end
    return os.date("%Y-%m-%d %H:%M:%S") .. " (игр)"
end

local function pushLog(line)
    table.insert(recentLog, 1, line)
    while #recentLog > MAX_LOG_LINES do table.remove(recentLog) end
end

local function log(action, details)
    local t = getRealTime()
    local short = "[" .. t:sub(12, 19) .. "] " .. action .. " | " .. (details or "")
    pushLog(short)
    -- В файл — с полной датой
    local fileLine = string.format("[%s] %s | crafter | %s", t, action, details or "")
    local f = io.open("/home/crafter.log", "a")
    if f then f:write(fileLine .. "\n"); f:close() end
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
    -- В БД (опционально, не блокируем)
    if config.use_database then
        pcall(function()
            network.request("POST", "/logs", json.encode({
                time = t, action = action, user = "crafter", details = details or ""
            }))
        end)
    end
end

-- =========================================================
-- ИСТОЧНИК ТОВАРОВ
-- =========================================================
local function loadCrafterItems()
    if config.use_database then
        if not component.isAvailable("internet") then
            log("ОШИБКА", "Internet Card не найдена")
            return nil
        end
        if not config.firebase_url or config.firebase_url == "" or config.firebase_url == "заменить" then
            log("ОШИБКА", "firebase_url не настроен в /home/config.lua")
            return nil
        end
        local ok, res = network.get("/crafter")
        if not ok then log("ОШИБКА", "Запрос /crafter провалился: " .. tostring(res)); return nil end
        if not res or res == "null" then
            log("ИНФО", "В БД нет /crafter — добавь предметы через вкладку Автокрафт")
            return {}
        end
        local parsed = json.decode(res)
        if not parsed then log("ОШИБКА", "Невалидный JSON в /crafter"); return nil end
        if not parsed.items then return {} end
        local arr = {}
        if type(parsed.items) == "table" then
            if #parsed.items > 0 then arr = parsed.items
            else for _, v in pairs(parsed.items) do table.insert(arr, v) end end
        end
        return arr
    end
    local f = io.open("/home/crafter_data.json", "r")
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
-- МЭ-СЕТЬ
-- =========================================================
local function getStocks()
    local stocks = {}
    for addr in component.list("me_interface") do
        local proxy = component.proxy(addr)
        local ok, items = pcall(function() return proxy.getItemsInNetwork() end)
        if ok and items then
            for _, it in ipairs(items) do
                local key = (it.name or "") .. "|" .. math.floor(it.damage or 0)
                stocks[key] = (stocks[key] or 0) + (it.size or 0)
            end
            return stocks, true
        end
    end
    return stocks, false
end

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

-- =========================================================
-- УПРАВЛЕНИЕ JOB-АМИ
-- =========================================================
local function jobStatus(j)
    local ok_d, done = pcall(function() return j.job.isDone() end)
    local ok_c, cancel = pcall(function() return j.job.isCanceled() end)
    local ok_f, failed = pcall(function() return j.job.hasFailed() end)
    if ok_d and done then return "готов" end
    if ok_c and cancel then return "отменён" end
    if ok_f and failed then return "провален" end
    return "идёт"
end

local function pruneFinishedJobs()
    for key, j in pairs(activeJobs) do
        local s = jobStatus(j)
        if s == "готов" then
            totalCompleted = totalCompleted + 1
            log("ЗАВЕРШЁН", j.name .. " x" .. j.amount)
            activeJobs[key] = nil
        elseif s == "отменён" then
            log("ОТМЕНЁН", j.name .. " x" .. j.amount)
            activeJobs[key] = nil
        elseif s == "провален" then
            totalFailed = totalFailed + 1
            log("ПРОВАЛ", j.name .. " x" .. j.amount)
            activeJobs[key] = nil
        end
    end
end

-- =========================================================
-- ПРОГРЕСС ВЫПОЛНЕНИЯ
-- Снимаем актуальные стоки из МЭ и считаем produced = current - start_stock.
-- Если игрок забрал что-то — produced не уменьшаем (берём max со старым значением).
-- Если produced >= amount → крафт считаем готовым и удаляем из activeJobs.
-- =========================================================
local function updateProgress(stocksFromTick)
    local now = computer.uptime()
    if not stocksFromTick and (now - lastProgressAt) < PROGRESS_POLL then return nil end

    local stocks
    if stocksFromTick then
        stocks = stocksFromTick
    else
        local ok
        stocks, ok = getStocks()
        meOk = ok
        if not ok then return nil end
    end
    lastProgressAt = now

    for key, j in pairs(activeJobs) do
        local cur = stocks[key] or 0
        local delta = cur - (j.start_stock or 0)
        if delta > (j.produced or 0) then
            j.produced = math.min(delta, j.amount)
        end
        if (j.produced or 0) >= j.amount then
            totalCompleted = totalCompleted + 1
            log("ЗАВЕРШЁН", j.name .. " x" .. j.amount .. " (по стоку)")
            pcall(function() j.job.cancel() end)
            activeJobs[key] = nil
        end
    end
    return stocks  -- возвращаем стоки, чтобы tryFillSlots их переиспользовала
end

local function cancelJob(j)
    if not j or not j.job then return false end
    local ok = pcall(function() j.job.cancel() end)
    if not ok then pcall(function() j.job.Cancel() end) end
    return true
end

-- =========================================================
-- ПОДСЧЁТ АКТИВНЫХ
-- =========================================================
local function countActive()
    local n = 0
    for _ in pairs(activeJobs) do n = n + 1 end
    return n
end

-- =========================================================
-- ДОБИВАНИЕ ОЧЕРЕДИ
-- Использует кэшированный список товаров и переданные/свежие стоки.
-- Запускает столько новых крафтов, чтобы countActive() достигло maxConcurrent.
-- Вызывается между основными тиками — даёт быструю реакцию на завершение крафта.
-- =========================================================
local function tryFillSlots(stocks)
    if paused then return end
    if not cachedItems then return end
    if countActive() >= maxConcurrent then return end

    if not stocks then
        local ok
        stocks, ok = getStocks()
        meOk = ok
        if not ok then return end
    end

    local started = 0
    for _, it in ipairs(cachedItems) do
        if countActive() >= maxConcurrent then break end
        if it.id and it.id ~= "" and it.enabled ~= false then
            local dmg = math.floor(tonumber(it.damage) or 0)
            local key = it.id .. "|" .. dmg
            local stock = stocks[key] or 0
            local keep = tonumber(it.keep_amount) or 1
            if stock < keep and not activeJobs[key] then
                local target = tonumber(it.craft_amount) or DEFAULT_AMOUNT
                local job = requestCraft(it.id, dmg, target)
                if job then
                    activeJobs[key] = {
                        job = job, name = it.name or it.id,
                        amount = target, started_at = computer.uptime(),
                        key = key, id = it.id, damage = dmg,
                        start_stock = stock, produced = 0,
                    }
                    started = started + 1
                    log("ЗАКАЗАН", (it.name or it.id) .. " x" .. target
                        .. " (из очереди, stock=" .. stock .. "/" .. keep .. ")")
                end
            end
        end
    end
end

-- =========================================================
-- ОСНОВНОЙ ТИК
-- Загружает /shop, обновляет cachedItems, заполняет слоты до maxConcurrent.
-- =========================================================
local function tick()
    pruneFinishedJobs()

    local stocks, gotStocks = getStocks()
    meOk = gotStocks
    if not gotStocks then
        log("ОШИБКА", "Нет связи с me_interface")
        return
    end

    local items = loadCrafterItems()
    dbOk = (items ~= nil)
    if not items then return end
    cachedItems = items  -- запоминаем для tryFillSlots между тиками

    local requested = 0
    local already = 0
    local capped = 0
    local skipped = 0
    local disabled = 0
    for _, it in ipairs(items) do
        if it.enabled == false then
            disabled = disabled + 1
        elseif it.id and it.id ~= "" then
            local dmg = math.floor(tonumber(it.damage) or 0)
            local key = it.id .. "|" .. dmg
            local stock = stocks[key] or 0
            local keep = tonumber(it.keep_amount) or 1
            local target = tonumber(it.craft_amount) or DEFAULT_AMOUNT

            if stock < keep then
                if activeJobs[key] then
                    already = already + 1
                elseif countActive() >= maxConcurrent then
                    capped = capped + 1   -- товар в очереди, ждёт свободного слота
                else
                    local job = requestCraft(it.id, dmg, target)
                    if job then
                        activeJobs[key] = {
                            job = job, name = it.name or it.id,
                            amount = target, started_at = computer.uptime(),
                            key = key, id = it.id, damage = dmg,
                            start_stock = stock, produced = 0,
                        }
                        requested = requested + 1
                        log("ЗАКАЗАН", (it.name or it.id) .. " x" .. target
                            .. " (stock=" .. stock .. "/" .. keep .. ")")
                    else
                        skipped = skipped + 1
                    end
                end
            end
        end
    end
    if requested > 0 or already > 0 or capped > 0 or skipped > 0 then
        log("ТИК", string.format(
            "заказано=%d, уже_крафтится=%d, в_очереди=%d, не_craftable=%d, выкл=%d, всего=%d, лимит=%d",
            requested, already, capped, skipped, disabled, #items, maxConcurrent))
    end

    -- сразу пересчитываем прогресс по уже полученным стокам (без двойного запроса в ME)
    updateProgress(stocks)
end

-- =========================================================
-- РЕНДЕР
-- =========================================================
local function buildState()
    -- сортируем jobs по времени создания (новые сверху)
    local arr = {}
    for _, j in pairs(activeJobs) do table.insert(arr, j) end
    table.sort(arr, function(a, b) return (a.started_at or 0) > (b.started_at or 0) end)
    local out = {}
    local now = computer.uptime()
    for _, j in ipairs(arr) do
        table.insert(out, {
            key = j.key, name = j.name, amount = j.amount,
            produced = j.produced or 0,
            status = jobStatus(j),
            age_sec = math.floor(now - (j.started_at or now)),
        })
    end
    return {
        jobs = out,
        recentLog = recentLog,
        secondsToTick = secondsToTick,
        totalCompleted = totalCompleted,
        totalFailed = totalFailed,
        meOk = meOk,
        dbOk = dbOk,
        paused = paused,
        maxConcurrent = maxConcurrent,
        activeCount = countActive(),
    }
end

local function redraw()
    pcall(function() gui.draw(buildState()) end)
end

-- =========================================================
-- ОБРАБОТКА КНОПОК
-- =========================================================
local function handleClick(id)
    if id == "force_tick" then
        lastTickAt = -INTERVAL  -- следующий тик сразу
        log("СОБЫТИЕ", "Принудительный тик")
    elseif id == "pause" then
        paused = not paused
        log("СОБЫТИЕ", paused and "Автокрафт приостановлен" or "Автокрафт включён")
    elseif id == "cancel_all" then
        local n = 0
        for _, j in pairs(activeJobs) do
            cancelJob(j); n = n + 1
        end
        log("СОБЫТИЕ", "Отменены все крафты (" .. n .. ")")
    elseif id == "limit_dec" then
        if maxConcurrent > 1 then
            maxConcurrent = maxConcurrent - 1
            log("СОБЫТИЕ", "Лимит одновременных крафтов: " .. maxConcurrent)
        end
    elseif id == "limit_inc" then
        maxConcurrent = maxConcurrent + 1
        log("СОБЫТИЕ", "Лимит одновременных крафтов: " .. maxConcurrent)
        -- при увеличении лимита сразу добиваем очередь
        local stocks = updateProgress()
        if stocks then tryFillSlots(stocks) else tryFillSlots() end
    elseif id == "quit" then
        log("СТОП", "Выход по кнопке")
        gpu = component.gpu
        gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
        require("term").clear()
        os.exit()
    elseif id and id:match("^cancel_%d+$") then
        local idx = tonumber(id:match("%d+"))
        -- собираем активные в том же порядке, что в buildState
        local arr = {}
        for _, j in pairs(activeJobs) do table.insert(arr, j) end
        table.sort(arr, function(a, b) return (a.started_at or 0) > (b.started_at or 0) end)
        local j = arr[idx]
        if j then
            cancelJob(j)
            log("ОТМЕНА", "Запрошена отмена: " .. j.name)
            -- статус обновится на следующем pruneFinishedJobs
        end
    end
end

-- =========================================================
-- ОСНОВНОЙ ЦИКЛ
-- =========================================================
log("СТАРТ", string.format("interval=%ds, default_amount=%d, max_concurrent=%d",
    INTERVAL, DEFAULT_AMOUNT, maxConcurrent))

local function loop()
    redraw()
    while true do
        local sinceLast = computer.uptime() - lastTickAt
        secondsToTick = math.max(0, INTERVAL - math.floor(sinceLast))

        -- Запускаем тик, если пора и не на паузе
        if not paused and sinceLast >= INTERVAL then
            local ok, err = pcall(tick)
            if not ok then log("FATAL_TICK", tostring(err)) end
            lastTickAt = computer.uptime()
            redraw()
        end

        -- Подтягиваем статусы и прогресс, при свободных слотах сразу добиваем очередь
        pruneFinishedJobs()
        local stocks = updateProgress()
        if stocks then tryFillSlots(stocks) end

        local ev = { event.pull(1) }
        local name = ev[1]
        if name == "touch" then
            local x, y = ev[3], ev[4]
            local id = gui.checkClick(x, y)
            if id then
                pcall(computer.beep, 1000, 0.05)
                handleClick(id)
                redraw()
            end
        elseif name == "key_down" then
            local code = ev[3]
            -- F = принудительный тик, E = выход, P = пауза
            if code == 33 then handleClick("force_tick"); redraw()      -- F
            elseif code == 18 then handleClick("quit")                   -- E
            elseif code == 25 then handleClick("pause"); redraw() end    -- P
        elseif name == "interrupted" then
            handleClick("quit")
        elseif not name then
            -- таймаут event.pull — просто перерисуем (обновим таймеры)
            redraw()
        end
    end
end

local ok, err = pcall(loop)
if not ok then
    log("CRASH", tostring(err))
    component.gpu.setBackground(0x000000)
    component.gpu.setForeground(0xFF5555)
    require("term").clear()
    print("Программа упала: " .. tostring(err))
    print("Лог: /home/crafter.log")
end
