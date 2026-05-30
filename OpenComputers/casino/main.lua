-- /home/casino_main.lua
local component = require("component")
local event = require("event")
local os = require("os")
local io = require("io")
local fs = require("filesystem")
local unicode = require("unicode")
local gui = require("casino_gui")
local computer = require("computer")
local config = require("casino_config")
local me = require("casino_me_logic")
local network = require("casino_network")
local json = require("casino_json")

-- === ОТКЛЮЧАЕМ БЕЗУСЛОВНОЕ ЗАКРЫТИЕ НА CTRL+ALT+C ===
event.shouldInterrupt = function() return false end

-- === БРОНЯ ОТ ГОНКИ ЗАГРУЗКИ (Ждем 5 секунд, пока сервер прогрузит МЭ сеть и чанки) ===
os.sleep(5)

-- === ИНИЦИАЛИЗАЦИЯ ИСТИННОГО РАНДОМА ===
math.randomseed(os.time() + (os.clock() * 1000))

local me_ok, me_msg = me.init()
local CUR = config.currency_name or "ЭМ"

local OWNER_NAME = "Администратор"
if config.admins then for k, v in pairs(config.admins) do OWNER_NAME = k; break end end

local casino_cases = {}
local users_db = {} 
local casino_name = "КАЗИНО"

local currentUser = nil
local idleTimer = 0
local msgTimer = 0
local syncTimer = 15
local state = "casino"
local ed_data = {}
local log_filter = ""
local selectedCaseIndex = nil
local selectedItemIndex = nil
local roulette_strip = {}
local roulette_winner = nil
local roulette_start_time = 0
local roulette_duration = 7 -- секунды
local roulette_target_pos = 0
local roulette_start_pos = 0

local currentPage = 1
local ITEMS_PER_PAGE = 6
local adminPage = 1
local ADMIN_ITEMS_PER_PAGE = 17

-- === ПЕРЕМЕННЫЕ ДЛЯ БЕГУЩЕЙ СТРОКИ ===
local marquee_offset = 0
local marquee_str = "ИДЕТ ЗАГРУЗКА ИСТОРИИ ВЫИГРЫШЕЙ..."
local marquee_timer = 0

-- === КАСТОМНЫЙ КАЛЕНДАРЬ ===
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

-- === ТРЮК С ФАЙЛОМ ДЛЯ РЕАЛЬНОГО ВРЕМЕНИ ===
local function getRealTime()
    local tz = tonumber(config.timezone) or 0
    local tmp_file = "/home/HostTime.tmp"
    
    local file = io.open(tmp_file, "w")
    if file then
        pcall(function() file:write("") end)
        pcall(function() file:close() end)

        local lastModifiedMs = fs.lastModified(tmp_file)
        pcall(function() fs.remove(tmp_file) end)

        if lastModifiedMs and lastModifiedMs > 0 then
            local current_unix = math.floor(lastModifiedMs / 1000)
            return formatUnixTime(current_unix + (tz * 3600))
        end
    end

    return os.date("%Y-%m-%d %H:%M:%S") .. " (Игр.)"
end

-- Heartbeat для дашборда — пишет в корневой /heartbeats/casino (без casino/ префикса).
-- network.lua casino автоматически добавляет main_db_path, поэтому здесь — прямой запрос.
local internet = require("internet")
local heartbeatTimer = 0
local startedAt_hb = nil

local function getRealTimeMs_hb()
    local tmp = "/home/HostTime.tmp"
    local f = io.open(tmp, "w")
    if not f then return nil end
    pcall(function() f:write("") end)
    pcall(function() f:close() end)
    local lm = fs.lastModified(tmp)
    pcall(function() fs.remove(tmp) end)
    if lm and lm > 0 then return lm end
    return nil
end

local function sendHeartbeat(stopped)
    if not (config.use_database and component.isAvailable("internet")) then return end
    if not config.firebase_url or config.firebase_url == "" then return end
    if not startedAt_hb then startedAt_hb = getRealTime() end
    pcall(function()
        local url = config.firebase_url .. "/heartbeats/casino.json"
        if config.db_secret and config.db_secret ~= "" then
            url = url .. "?auth=" .. config.db_secret
        end
        local body = json.encode({
            name = "Казино",
            type = "casino",
            last_seen = getRealTime(),
            last_seen_ms = getRealTimeMs_hb(),
            started_at = startedAt_hb,
            cases_count = #casino_cases,
            online_user = (currentUser and currentUser.name) or nil,
            stopped = stopped or false,
        })
        local headers = {
            ["Content-Type"] = "application/json",
            ["X-HTTP-Method-Override"] = "PUT",
        }
        local handle = internet.request(url, body, headers, "POST")
        for _ in handle do end  -- drain (необходимо для отправки запроса)
        -- Закрываем handle явно, иначе TCP-буфер OC утекает
        pcall(function() handle:close() end)
        pcall(function() if handle.close then handle.close(handle) end end)
        handle = nil; body = nil; headers = nil; url = nil
    end)
end

-- Логирование ТОЛЬКО в Firebase /casino/logs. На диске не сохраняем — экономим RAM/диск OC.
local function writeLog(action, user, details)
    if not (config.use_database and component.isAvailable("internet")) then return end
    pcall(function()
        network.post("/logs", json.encode({
            time = getRealTime(), action = action, user = user, details = details
        }))
    end)
end

-- Удаляем старый локальный лог-файл (если остался от прошлых версий)
-- Удаляем осколки от прошлых версий программы
pcall(function() if fs.exists("/home/casino_logs.txt") then fs.remove("/home/casino_logs.txt") end end)
pcall(function() if fs.exists("/home/casino_crash.log") then fs.remove("/home/casino_crash.log") end end)
pcall(function() if fs.exists("/home/HostTime.tmp") then fs.remove("/home/HostTime.tmp") end end)

local function loadLogsLocal(filter)
    -- Логи теперь только в админке сайта
    return {
        "Логи теперь только в админке (Firebase / casino/logs).",
        "Открой админку → вкладка \"Казино → Логи\".",
        "На компьютере локальные логи отключены для экономии памяти.",
    }
end

local function loadUsersLocal()
    local f = io.open("/home/casino_users.json", "r")
    if f then
        local data = f:read("*a")
        if data and data ~= "" then users_db = json.decode(data) or {} end
        f:close()
    end
end

local function loadCasinoLocal()
    local f = io.open("/home/casino_data.json", "r")
    if f then
        local data = f:read("*a")
        f:close()
        if data and data ~= "" then
            local parsed = json.decode(data)
            if parsed then
                if parsed.cases then casino_cases = parsed.cases end
                if parsed.casino_name then casino_name = parsed.casino_name end
            end
        end
    end
end

local function saveUser()
    if not currentUser then return end
    if not users_db[currentUser.name] then users_db[currentUser.name] = { balance = 0, spent = 0 } end
    users_db[currentUser.name].balance = currentUser.balance
    users_db[currentUser.name].spent = currentUser.spent
    
    local f = io.open("/home/casino_users.json", "w")
    if f then f:write(json.encode(users_db)); f:close() end
    
    if config.use_database and component.isAvailable("internet") then
        pcall(function() network.patch("/users/" .. currentUser.name, json.encode({ balance = currentUser.balance, spent = currentUser.spent })) end)
    end
end

local function saveCasino()
    local data = { cases = casino_cases, casino_name = casino_name }
    local encoded = json.encode(data)
    local f = io.open("/home/casino_data.json", "w")
    if f then f:write(encoded); f:close() end
    
    if config.use_database and component.isAvailable("internet") then
        pcall(function() network.put("/data", encoded) end)
    end
end

local function loadDB()
    if config.use_database and component.isAvailable("internet") then
        local succ_data, res_data = network.get("/data")
        if succ_data and res_data and res_data ~= "null" then
            local parsed = json.decode(res_data)
            if parsed then
                if parsed.cases then casino_cases = parsed.cases end
                if parsed.casino_name then casino_name = parsed.casino_name end
            end
        else loadCasinoLocal() end
        
        local succ_u, res_u = network.get("/users")
        if succ_u and res_u and res_u ~= "null" then
            local parsed_u = json.decode(res_u)
            if parsed_u then users_db = parsed_u end
        else loadUsersLocal() end
    else
        loadCasinoLocal()
        loadUsersLocal()
    end
end

-- === НОВЫЙ ТОП 15 ===
local function getTop15Players()
    local sorted = {}
    for name, data in pairs(users_db) do table.insert(sorted, {name = name, spent = data.spent or 0}) end
    table.sort(sorted, function(a, b) return a.spent > b.spent end)
    local top15 = {}
    for i = 1, math.min(15, #sorted) do table.insert(top15, sorted[i]) end
    return top15
end

-- === ЧТЕНИЕ ПОБЕД ДЛЯ БЕГУЩЕЙ СТРОКИ ===
local function getRecentWinsString()
    local logs = loadLogsLocal("ВЫИГРЫШ")
    local wins = {}
    for _, line in ipairs(logs) do
        -- Ищем паттерн в логе
        local user, details = line:match("ВЫИГРЫШ%s*|%s*(.-)%s*|%s*(.*)")
        if user and details then
            -- Вытаскиваем предмет и кейс
            local item, case = details:match("Выиграл (.-) из кейса (.*)")
            if item and case then
                table.insert(wins, string.format("*** %s: %s | %s ***", user, item, case))
            end
        end
        if #wins >= 10 then break end
    end
    if #wins == 0 then return "ПОКА НИКТО НИЧЕГО НЕ ВЫИГРАЛ... БУДЬ ПЕРВЫМ!        " end
    return table.concat(wins, "        ") .. "        "
end

local function getPageItems(list, perPage)
    local maxPage = math.ceil(#list / perPage)
    if maxPage < 1 then maxPage = 1 end
    if currentPage > maxPage then currentPage = maxPage end
    local pageData = {}
    local startIdx = (currentPage - 1) * perPage + 1
    local endIdx = math.min(startIdx + perPage - 1, #list)
    for i = startIdx, endIdx do table.insert(pageData, {item = list[i], origIdx = i}) end
    return pageData, maxPage
end

local function getAdminPageItems(list, limit)
    limit = limit or ADMIN_ITEMS_PER_PAGE
    local maxPage = math.ceil(#list / limit)
    if maxPage < 1 then maxPage = 1 end
    if adminPage > maxPage then adminPage = maxPage end
    local pageData = {}
    local startIdx = (adminPage - 1) * limit + 1
    local endIdx = math.min(startIdx + limit - 1, #list)
    for i = startIdx, endIdx do table.insert(pageData, {item = list[i], origIdx = i}) end
    return pageData, maxPage
end

local function easeOutCubic(t)
    return 1 - math.pow(1 - t, 3)
end

local function refreshScreen()
    if state == "casino" then
        -- Обновляем текст выигрышей
        marquee_str = getRecentWinsString()
        
        gui.drawStatic(currentUser, currentUser and idleTimer or nil, getTop15Players(), casino_name, me.getDepositPrices())
        gui.drawMarquee(marquee_str, marquee_offset)
        local pItems, maxPage = getPageItems(casino_cases, ITEMS_PER_PAGE)
        gui.drawCases(pItems, currentPage, maxPage)
        if not me_ok then component.gpu.set(2, component.gpu.getResolution(), "СИСТЕМНАЯ ОШИБКА: " .. me_msg) end
    elseif state == "view_case" then
        gui.drawCaseView(casino_cases[selectedCaseIndex])
    elseif state == "admin_edit_case" then
        local case = casino_cases[selectedCaseIndex]
        gui.drawCaseEditor(case, case.items or {})
    elseif state == "admin_edit_item" then
        gui.drawItemEditor(ed_data, false)
    elseif state == "admin_edit_dep_item" then
        gui.drawItemEditor(ed_data, true)
    elseif string.match(state, "admin") and not string.match(state, "wait_scan") then
        local listToPass = {}
        local perPage = ADMIN_ITEMS_PER_PAGE
        if state == "admin_cases" then 
            listToPass = casino_cases
        elseif state == "admin_logs" then 
            listToPass = loadLogsLocal(log_filter)
            perPage = 30
        elseif state == "admin_deposit" then
            for k, v in pairs(me.getDepositPrices()) do
                local p_name = type(v) == "table" and v.name or k
                local p_price = type(v) == "table" and v.price or v
                table.insert(listToPass, {name = p_name, price = p_price, orig_key = k})
            end
            table.sort(listToPass, function(a,b) return a.name < b.name end)
        end
        
        local pItems, maxP = getAdminPageItems(listToPass, perPage)
        if state == "admin_deposit" then
            for _, pItem in ipairs(pItems) do pItem.origIdx = pItem.item.orig_key end
        end
        
        gui.drawAdmin(state:gsub("admin_", ""), pItems, adminPage, maxP, log_filter)
    elseif state == "editor" then
        gui.drawStatic(currentUser, idleTimer, getTop15Players(), casino_name, me.getDepositPrices())
        gui.drawEditorModal(ed_data)
    end
end

local function showMsg(title, text, isError, timeout)
    state = "modal_msg"
    msgTimer = timeout or 0
    gui.drawNotification(title, text, isError)
end

-- Инициализация
loadDB()
refreshScreen()

local last_tick = computer.uptime()

-- =========================================================================
-- ВЕСЬ ТЕЛО ЦИКЛА ВЫНЕСЕНО В ФУНКЦИЮ ДЛЯ ЗАЩИТЫ ОТ ВЫГРУЗКИ ЧАНКОВ
-- =========================================================================
local function casinoTick()
    local ev, _, arg1, arg2, arg3, arg4, arg5 = event.pull(0.01)
    local current_uptime = computer.uptime()
    
    -- Двигатель бегущей строки (обновляется каждые 0.15 сек)
    if state == "casino" and current_uptime - marquee_timer >= 0.15 then
        marquee_timer = current_uptime
        marquee_offset = marquee_offset + 1
        gui.drawMarquee(marquee_str, marquee_offset)
    end
    
    -- Heartbeat для дашборда: раз в 30 сек
    if current_uptime - heartbeatTimer >= 30 then
        heartbeatTimer = current_uptime
        sendHeartbeat()
    end

    -- === СИСТЕМА ТОЧНОГО ВРЕМЕНИ ===
    if current_uptime - last_tick >= 1 then
        last_tick = current_uptime

        if state == "modal_msg" and msgTimer > 0 then
            msgTimer = msgTimer - 1
            if msgTimer <= 0 then 
                if ed_data.return_to then state = ed_data.return_to; ed_data.return_to = nil else state = "casino" end
                refreshScreen()
            end
        end
        
        if currentUser and state ~= "modal_msg" and not string.match(state, "wait_scan") and not string.match(state, "editor") and not string.match(state, "admin") and state ~= "roulette" then
            idleTimer = idleTimer - 1
            if idleTimer <= 0 then 
                currentUser = nil; state = "casino"; currentPage = 1
                refreshScreen()
            else
                if state == "casino" then gui.drawTick(currentUser, idleTimer) end
            end
        end
        
        if state == "casino" then
            if config.use_database and component.isAvailable("internet") then
                syncTimer = syncTimer - 1
                if syncTimer <= 0 then
                    syncTimer = 15
                    loadDB() 
                    if currentUser and users_db[currentUser.name] then
                        currentUser.balance = users_db[currentUser.name].balance
                        currentUser.spent = users_db[currentUser.name].spent
                    end
                    refreshScreen()
                end
            end
        end
    end
    
    if not ev then 
        if state == "roulette" then
            local elapsed = computer.uptime() - roulette_start_time
            if elapsed >= roulette_duration then
                state = "casino"
                ed_data.return_to = "casino"
                
                local win_qty = roulette_winner.qty or 1
                local ok, msg, num_given = me.givePrize(roulette_winner.id, roulette_winner.damage, win_qty)
                
                if ok and num_given > 0 then
                    local logText = "Выиграл " .. roulette_winner.name .. " (x" .. win_qty .. ") из кейса " .. ed_data.case_name
                    local msgText = "Вы получили: " .. roulette_winner.name .. " (x" .. win_qty .. ")"
                    writeLog("ВЫИГРЫШ", currentUser.name, logText)
                    showMsg("ВЫИГРЫШ!", msgText, false, 5)
                else
                    currentUser.balance = currentUser.balance + ed_data.case_price
                    writeLog("ОШИБКА ВЫДАЧИ", currentUser.name, "Не удалось выдать " .. roulette_winner.name .. ". " .. msg)
                    showMsg("ОШИБКА ВЫДАЧИ", "Не удалось выдать приз. Средства возвращены. " .. msg, true, 5)
                end
                saveUser()
                roulette_strip = {}
                roulette_winner = nil
                refreshScreen()
            else
                local t = elapsed / roulette_duration
                local current_pos = roulette_start_pos + (roulette_target_pos - roulette_start_pos) * easeOutCubic(t)
                gui.drawRoulette(roulette_strip, current_pos)
            end
        end
    else
        if currentUser and state ~= "roulette" then 
            idleTimer = 30
            if state == "casino" then gui.drawTick(currentUser, idleTimer) end
        end
        
        if ev == "interrupted" then
            if currentUser and currentUser.isAdmin then
                component.gpu.setBackground(0x000000)
                component.gpu.setForeground(0xFFFFFF)
                require("term").clear()
                print("Программа завершена администратором: " .. currentUser.name)
                error("ADMIN_EXIT")
            else
                showMsg("ОТКАЗ В ДОСТУПЕ", "Только администратор может закрыть программу!", true, 3)
            end
        elseif ev == "key_down" and (state == "editor" or state == "admin_edit_item" or state == "admin_edit_dep_item") then
            local char = arg1; local code = arg2
            local val
            if ed_data.focus == "name" then val = ed_data.name 
            elseif ed_data.focus == "price" then val = tostring(ed_data.price)
            elseif ed_data.focus == "chance" then val = tostring(ed_data.chance)
            elseif ed_data.focus == "qty" then val = tostring(ed_data.qty)
            end
            if val then
                if code == 14 then
                    if unicode.len(val) > 0 then val = unicode.sub(val, 1, -2) end
                elseif char >= 32 then val = val .. unicode.char(char) end
                
                if ed_data.focus == "name" then ed_data.name = val
                elseif ed_data.focus == "price" then ed_data.price = val
                elseif ed_data.focus == "chance" then ed_data.chance = val
                elseif ed_data.focus == "qty" then ed_data.qty = val
                end
                refreshScreen()
            end
        elseif ev == "clipboard" and (state == "editor" or state == "admin_edit_item" or state == "admin_edit_dep_item") then
            local text = arg1
            if ed_data.focus == "name" then ed_data.name = ed_data.name .. text
            elseif ed_data.focus == "price" then ed_data.price = tostring(ed_data.price) .. text
            elseif ed_data.focus == "chance" then ed_data.chance = tostring(ed_data.chance) .. text
            elseif ed_data.focus == "qty" then ed_data.qty = tostring(ed_data.qty) .. text
            end
            refreshScreen()
        elseif ev == "scroll" and state ~= "roulette" then
            local dir = arg4
            local player_name = arg5
            if currentUser and currentUser.name ~= player_name then computer.beep(400, 0.1)
            else
                if state == "casino" then
                    if dir > 0 and currentPage > 1 then currentPage = currentPage - 1; refreshScreen()
                    elseif dir < 0 then currentPage = currentPage + 1; refreshScreen() end
                elseif string.match(state, "admin") then
                    if dir > 0 and adminPage > 1 then adminPage = adminPage - 1; refreshScreen()
                    elseif dir < 0 then adminPage = adminPage + 1; refreshScreen() end
                end
            end
        elseif ev == "touch" and state ~= "roulette" then
            local x = arg1; local y = arg2; local player_name = arg4
            if currentUser and currentUser.name ~= player_name then computer.beep(400, 0.1)
            else
                local action = gui.checkClick(x, y)
                if action then
                    computer.beep(1000, 0.05)
                    if action == "page_prev" then currentPage = currentPage - 1; refreshScreen()
                    elseif action == "page_next" then currentPage = currentPage + 1; refreshScreen()
                    elseif action == "adm_prev" then adminPage = adminPage - 1; refreshScreen()
                    elseif action == "adm_next" then adminPage = adminPage + 1; refreshScreen()
                    elseif action == "close_admin" then state = "casino"; refreshScreen()
                    elseif action == "close_view" then state = "casino"; refreshScreen()
                    elseif action == "close_modal" then 
                        if string.match(state, "wait_scan") then
                            local stack, msg = me.peekInput()
                            if not stack then
                                ed_data.return_to = state == "admin_wait_scan" and "admin_edit_case" or "admin_deposit"
                                showMsg("ОШИБКА СКАНЕРА", msg, true, 4)
                            else
                                local isDeposit = (state == "admin_wait_scan_dep")
                                state = isDeposit and "admin_edit_dep_item" or "admin_edit_item"
                                ed_data.is_new = true
                                ed_data.name = stack.label or stack.name
                                ed_data.price = "0"
                                ed_data.chance = "10"
                                ed_data.qty = "1" -- Количество по умолчанию
                                ed_data.orig_id = stack.name
                                ed_data.damage = stack.damage or 0
                                ed_data.focus = isDeposit and "price" or "name"
                                refreshScreen()
                            end
                        else
                            state = "casino"; msgTimer = 0; refreshScreen()
                        end
                    elseif action == "filter_logs" then
                        ed_data = {target = "log_filter", focus = "name", name = log_filter}
                        state = "editor"; refreshScreen()
                    elseif action == "clear_filter" then
                        log_filter = ""; adminPage = 1; refreshScreen()
                    elseif action == "adm_name" then
                        ed_data = {target = "casino_name", focus = "name", name = casino_name}
                        state = "editor"; refreshScreen()
                    elseif action:match("adm_edit_") then
                        local origIdx = tonumber(action:match("%d+"))
                        if state == "admin_cases" then
                            state = "admin_edit_case"
                            selectedCaseIndex = origIdx
                            refreshScreen()
                        end
                    elseif state == "editor" then
                        if action == "focus_name" then ed_data.focus = "name"; refreshScreen()
                        elseif action == "focus_price" then ed_data.focus = "price"; refreshScreen()
                        elseif action == "ed_cancel" then
                             state = "admin_cases"; refreshScreen()
                        elseif action == "ed_save" then
                            local p_str = tostring(ed_data.price):gsub(",", ".")
                            if ed_data.target ~= "log_filter" and (p_str == "" or not tonumber(p_str)) then 
                                showMsg("ОШИБКА", "Цена должна быть числом!", true)
                            else
                                if ed_data.target == "log_filter" then
                                    log_filter = ed_data.name; state = "admin_logs"; adminPage = 1; refreshScreen()
                                elseif ed_data.target == "casino_name" then
                                    casino_name = ed_data.name; saveCasino(); state = "admin_cases"; refreshScreen()
                                elseif ed_data.target == "add_case" then
                                    table.insert(casino_cases, { name = ed_data.name, price = tonumber(p_str), items = {} })
                                    writeLog("КЕЙС ДОБАВЛЕН", currentUser.name, ed_data.name .. " за " .. p_str .. " " .. CUR)
                                    saveCasino(); state = "admin_cases"; adminPage = 1; refreshScreen()
                                end
                            end
                        end
                    elseif state == "admin_edit_case" then
                        if action == "back_to_admin" then state = "admin_cases"; selectedCaseIndex = nil; refreshScreen() 
                        elseif action == "case_add_item" then
                            state = "admin_wait_scan"
                            gui.drawNotification("СКАНИРОВАНИЕ", "Положите 1 предмет в сундук и нажмите ОК", false)
                        elseif action:match("case_edit_item_") then
                            selectedItemIndex = tonumber(action:match("%d+"))
                            local item = casino_cases[selectedCaseIndex].items[selectedItemIndex]
                            state = "admin_edit_item"
                            ed_data.is_new = false
                            ed_data.name = item.name
                            ed_data.price = tostring(item.price)
                            ed_data.chance = tostring(item.chance)
                            ed_data.qty = tostring(item.qty or 1)
                            ed_data.orig_id = item.id
                            ed_data.damage = item.damage
                            ed_data.focus = "name"
                            refreshScreen()
                        elseif action:match("case_del_item_") then
                            local item_idx = tonumber(action:match("%d+"))
                            table.remove(casino_cases[selectedCaseIndex].items, item_idx)
                            saveCasino(); refreshScreen()
                        end
                    elseif string.match(state, "admin_edit_") then
                        if action == "focus_name" then ed_data.focus = "name"
                        elseif action == "focus_price" then ed_data.focus = "price"
                        elseif action == "focus_chance" then ed_data.focus = "chance"
                        elseif action == "focus_qty" then ed_data.focus = "qty"
                        elseif action == "item_ed_cancel" then state = (state == "admin_edit_dep_item") and "admin_deposit" or "admin_edit_case"
                        elseif action == "item_ed_save" then
                            local p_str = tostring(ed_data.price):gsub(",", ".")
                            local price = tonumber(p_str)
                            
                            if state == "admin_edit_dep_item" then
                                if not price then
                                    ed_data.return_to = "admin_edit_dep_item"
                                    showMsg("ОШИБКА", "Цена должна быть числом!", true, 4)
                                else
                                    local key = ed_data.orig_id .. (ed_data.damage > 0 and (":"..ed_data.damage) or "")
                                    local prices = me.getDepositPrices()
                                    prices[key] = { price = price, name = ed_data.name }
                                    me.saveDepositPrices(prices)
                                    state = "admin_deposit"
                                end
                            else
                                local c_str = tostring(ed_data.chance):gsub(",", ".")
                                local chance = tonumber(c_str)
                                local q_str = tostring(ed_data.qty):gsub(",", ".")
                                local qty = math.floor(tonumber(q_str) or 1)
                                if qty < 1 then qty = 1 end
                                
                                if not price or not chance then
                                    ed_data.return_to = "admin_edit_item"
                                    showMsg("ОШИБКА", "Цена и шанс должны быть числами!", true, 4)
                                else
                                    local item_data = {
                                        name = ed_data.name, price = price, chance = chance, qty = qty,
                                        id = ed_data.orig_id, damage = ed_data.damage
                                    }
                                    if ed_data.is_new then
                                        table.insert(casino_cases[selectedCaseIndex].items, item_data)
                                    else
                                        casino_cases[selectedCaseIndex].items[selectedItemIndex] = item_data
                                    end
                                    saveCasino()
                                    state = "admin_edit_case"
                                end
                            end
                        end
                        refreshScreen()
                    elseif state == "casino" then
                        if action == "login" then
                            local is_adm = false; if config.admins and config.admins[player_name] then is_adm = true end
                            local bal, spent = 0, 0
                            if users_db[player_name] then 
                                bal = users_db[player_name].balance or 0
                                spent = users_db[player_name].spent or 0
                            else
                                if config.use_database and component.isAvailable("internet") then
                                    local succ, res = network.get("/users/" .. player_name)
                                    if succ and res and res ~= "null" then
                                        local udata = json.decode(res)
                                        if udata then 
                                            bal = udata.balance or 0
                                            spent = udata.spent or 0
                                        end
                                    end
                                end
                            end
                            currentUser = { name = player_name, balance = bal, spent = spent, isAdmin = is_adm }; idleTimer = 30; refreshScreen()
                        elseif action == "logout" then currentUser = nil; currentPage = 1; refreshScreen()
                        elseif action == "admin_panel" then state = "admin_cases"; adminPage = 1; refreshScreen()
                        elseif action == "deposit" then
                            if not currentUser then showMsg("ОШИБКА", "Сначала авторизуйтесь!", true)
                            else
                                local success, msg, earned = me.sellAllToBalance()
                                if success and earned > 0 then 
                                    currentUser.balance = currentUser.balance + earned; saveUser()
                                    writeLog("ПОПОЛНЕНИЕ", currentUser.name, msg .. " Зачислено: " .. earned .. " " .. CUR)
                                    showMsg("УСПЕШНО", msg .. " Зачислено: " .. earned .. " " .. CUR, false, 3)
                                else showMsg("ОШИБКА", msg, true) end
                            end
                        elseif action:match("open_case_") then
                            local case_idx = tonumber(action:match("%d+"))
                            local case = casino_cases[case_idx]
                            
                            if not currentUser then 
                                showMsg("ОШИБКА", "Сначала авторизуйтесь!", true, 3) 
                            elseif not case.items or #case.items == 0 then 
                                showMsg("ОШИБКА", "Этот кейс пуст!", true, 3) 
                            elseif currentUser.balance < case.price then 
                                showMsg("ОШИБКА", "Недостаточно средств!", true, 3) 
                            else
                                currentUser.balance = currentUser.balance - case.price
                                currentUser.spent = (currentUser.spent or 0) + case.price
                                local total_chance = 0
                                for _, item in ipairs(case.items) do total_chance = total_chance + item.chance end
                                local random_num = math.random() * total_chance
                                local cumulative_chance = 0
                                for _, item in ipairs(case.items) do
                                    cumulative_chance = cumulative_chance + item.chance
                                    if random_num <= cumulative_chance then
                                        roulette_winner = item
                                        break
                                    end
                                end
                                if not roulette_winner then roulette_winner = case.items[#case.items] end
                                roulette_strip = {}
                                for i=1, 50 do
                                    table.insert(roulette_strip, case.items[math.random(#case.items)])
                                end
                                roulette_target_pos = 41 + (math.random() * 0.5 - 0.25)
                                roulette_strip[41] = roulette_winner
                                ed_data.case_name = case.name
                                ed_data.case_price = case.price
                                state = "roulette"
                                roulette_start_pos = math.random(5, 15)
                                roulette_start_time = computer.uptime()
                                refreshScreen()
                            end
                        elseif action:match("view_case_") then
                            local case_idx = tonumber(action:match("%d+"))
                            selectedCaseIndex = case_idx
                            state = "view_case"
                            refreshScreen()
                        end
                    elseif string.match(state, "admin") then
                        if action == "adm_cases" then state = "admin_cases"; adminPage = 1; refreshScreen()
                        elseif action == "adm_logs" then state = "admin_logs"; adminPage = 1; refreshScreen()
                        elseif action == "adm_deposit" then state = "admin_deposit"; adminPage = 1; refreshScreen()
                        elseif action == "adm_name" then ed_data = {target = "casino_name", focus = "name", name = casino_name}; state = "editor"; refreshScreen()
                        elseif action == "adm_add" then
                            if state == "admin_cases" then
                                ed_data = {target = "add_case", focus = "name", name = "Новый кейс", price = "100"}
                                state = "editor"; refreshScreen()
                            end
                        elseif action == "adm_add_dep" then
                            state = "admin_wait_scan_dep"
                            gui.drawNotification("СКАНИРОВАНИЕ", "Положите предмет в сундук для скупки и нажмите ОК", false)
                        elseif action:match("adm_del_dep_") then
                            local key_to_del = action:gsub("adm_del_dep_", "")
                            if state == "admin_deposit" then
                                local prices = me.getDepositPrices()
                                prices[key_to_del] = nil
                                me.saveDepositPrices(prices)
                            end
                            refreshScreen()
                        elseif action:match("adm_del_") then
                            local idx = tonumber(action:match("%d+"))
                            if state == "admin_cases" then 
                                writeLog("КЕЙС УДАЛЕН", currentUser.name, casino_cases[idx].name); 
                                table.remove(casino_cases, idx) 
                            end
                            saveCasino(); refreshScreen()
                        end
                    end
                end
            end
        end
    end
end

-- =========================================================================
-- СТОРОЖЕВОЙ ПЕС С ВСТРОЕННЫМ ВЫХОДОМ
-- =========================================================================
while true do
    local ok, err = pcall(casinoTick)
    if not ok then
        -- ПРОПУСКАЕМ АДМИНА В КОНСОЛЬ:
        if tostring(err):match("ADMIN_EXIT") then
            break -- Разрываем бесконечный цикл и выходим в систему!
        end
        
        -- Шлём краш в Firebase /casino/logs (локально не сохраняем — экономим RAM/диск)
        pcall(function()
            network.post("/logs", json.encode({
                time = getRealTime(), action = "ОШИБКА КРАШ",
                user = "system", details = tostring(err):sub(1, 200)
            }))
        end)

        os.sleep(3)
        computer.shutdown(true)
    end
end
