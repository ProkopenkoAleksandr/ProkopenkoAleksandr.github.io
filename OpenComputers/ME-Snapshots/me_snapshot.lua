-- /lua/me_snapshot.lua
-- Снимает содержимое МЭ-сети раз в N секунд и публикует в Firebase /me_snapshot.
-- Простая консольная программа без GUI — пишет статус в stdout.
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

event.shouldInterrupt = function() return false end

local INTERVAL = tonumber(config.snapshot_interval) or 60
local MIN_SIZE = tonumber(config.min_size) or 1
local MAX_ITEMS = tonumber(config.max_items) or 5000

-- =========================================================
-- ВРЕМЯ (как у крафтера — точное по lastModified файла)
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
    local tmp = "/home/HostTime.tmp"
    local f = io.open(tmp, "w")
    if f then
        f:write(""); f:close()
        local lm = fs.lastModified(tmp)
        fs.remove(tmp)
        if lm and lm > 0 then return formatUnixTime(math.floor(lm / 1000) + tz * 3600) end
    end
    return os.date("%Y-%m-%d %H:%M:%S") .. " (игр)"
end

local function logToFile(msg)
    local f = io.open("/home/me_snapshot.log", "a")
    if f then f:write("[" .. getRealTime() .. "] " .. msg .. "\n"); f:close() end
    -- ротация
    local sz = fs.size("/home/me_snapshot.log")
    if sz and sz > 30000 then
        local fr = io.open("/home/me_snapshot.log", "r")
        if fr then
            fr:seek("end", -10000)
            local tail = fr:read("*a") or ""
            fr:close()
            local nl = tail:find("\n", 1, true)
            if nl then tail = tail:sub(nl + 1) end
            local fw = io.open("/home/me_snapshot.log", "w")
            if fw then fw:write(tail); fw:close() end
        end
    end
end

-- =========================================================
-- СНЯТИЕ SNAPSHOT'А
-- =========================================================
local function snapMe()
    for addr in component.list("me_interface") do
        local proxy = component.proxy(addr)
        local ok, list = pcall(function() return proxy.getItemsInNetwork() end)
        if ok and list then return list end
    end
    return nil
end

local function buildSnapshot(rawItems)
    -- агрегируем (на случай если один и тот же id|damage встречается несколько раз)
    local agg = {}
    for _, it in ipairs(rawItems) do
        local dmg = math.floor(it.damage or 0)
        local size = math.floor(it.size or 0)
        if size >= MIN_SIZE then
            local key = (it.name or "unknown") .. "|" .. dmg
            if agg[key] then
                agg[key].size = agg[key].size + size
            else
                agg[key] = {
                    id = it.name,
                    damage = dmg,
                    label = it.label or it.name,
                    size = size,
                }
            end
        end
    end
    -- перекладываем в массив + сортируем по убыванию size
    local arr = {}
    local totalSize = 0
    for _, v in pairs(agg) do
        table.insert(arr, v)
        totalSize = totalSize + v.size
    end
    table.sort(arr, function(a, b) return a.size > b.size end)
    -- отрезаем хвост если слишком много
    local truncated = false
    if #arr > MAX_ITEMS then
        local tail = #arr - MAX_ITEMS
        for i = #arr, MAX_ITEMS + 1, -1 do arr[i] = nil end
        truncated = tail
    end
    return {
        updated_at = getRealTime(),
        unique_count = #arr,
        total_size = totalSize,
        truncated = truncated,
        items = arr,
    }
end

-- =========================================================
-- ОТПРАВКА В FIREBASE
-- =========================================================
local function publishSnapshot(snap)
    if not config.firebase_url or config.firebase_url == "" or config.firebase_url == "заменить" then
        logToFile("ОШИБКА: firebase_url не настроен — edit /home/config.lua")
        return false
    end
    local body = json.encode(snap)
    local ok, res = network.put("/me_snapshot", body)
    if not ok then
        logToFile("ОШИБКА publish: " .. tostring(res))
        return false
    end
    return true, #body
end

-- =========================================================
-- ЦИКЛ
-- =========================================================
print("=== ME-Snapshot ===")
print("Интервал:    " .. INTERVAL .. " сек")
print("Min size:    " .. MIN_SIZE)
print("Max items:   " .. MAX_ITEMS)
print("Источник:    Firebase /me_snapshot")
print("Закрытие:    Ctrl+Alt+C")
print()
logToFile("СТАРТ interval=" .. INTERVAL .. "s, min_size=" .. MIN_SIZE .. ", max=" .. MAX_ITEMS)

local iter = 0
while true do
    iter = iter + 1
    local raw = snapMe()
    if not raw then
        print("[" .. iter .. "] нет связи с me_interface, повтор через " .. INTERVAL .. " с")
        logToFile("ME no link")
    else
        local snap = buildSnapshot(raw)
        local ok, bytes = publishSnapshot(snap)
        if ok then
            print(string.format("[%d] %s: %d позиций, %d шт, payload ~%d KB%s",
                iter, snap.updated_at, snap.unique_count, snap.total_size,
                math.floor((bytes or 0) / 1024),
                snap.truncated and (" (trunc " .. snap.truncated .. ")") or ""))
            logToFile(string.format("OK %d позиций / %d шт / %d KB",
                snap.unique_count, snap.total_size, math.floor((bytes or 0) / 1024)))
        else
            print("[" .. iter .. "] публикация провалилась — смотри /home/me_snapshot.log")
        end
        snap = nil; raw = nil  -- освобождаем большие таблицы для GC
    end

    -- ждём INTERVAL секунд, реагируем на Ctrl+Alt+C
    local target = computer.uptime() + INTERVAL
    while computer.uptime() < target do
        local ev = event.pull(1, "interrupted")
        if ev then
            logToFile("СТОП")
            os.exit()
        end
    end
end
