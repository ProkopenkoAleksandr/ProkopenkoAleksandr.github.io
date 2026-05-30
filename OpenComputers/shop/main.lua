-- /lua/main.lua
local component = require("component")
local event = require("event")
local os = require("os")
local io = require("io")
local fs = require("filesystem")
local unicode = require("unicode")
local gui = require("gui")
local computer = require("computer")
local config = require("config")
local me = require("me_logic")
local network = require("network")
local json = require("json")

-- === ОТКЛЮЧАЕМ БЕЗУСЛОВНОЕ ЗАКРЫТИЕ НА CTRL+ALT+C ===
event.shouldInterrupt = function() return false end

-- === БРОНЯ ОТ ГОНКИ ЗАГРУЗКИ (Ждем 5 секунд, пока сервер прогрузит МЭ сеть и чанки) ===
os.sleep(5)

local me_ok, me_msg = me.init()
local CUR = config.currency_name or "ЭМ"

local OWNER_NAME = "Администратор"
if config.admins then for k, v in pairs(config.admins) do OWNER_NAME = k; break end end

local shop_items = {}
local shop_buyback = {}
local categories = {"ВСЕ", "Ресурсы", "Механизмы", "Броня"}
local users_db = {} 
local shop_name = "МЭ МАГАЗИН"

local active_category = "ВСЕ"
local currentUser = nil
local idleTimer = 0
local msgTimer = 0
local syncTimer = 15

-- Heartbeat для дашборда (функция объявлена ниже, после getRealTime)
local heartbeatTimer = 0
local startedAt = nil
local sendHeartbeat  -- forward declaration
local state = "shop"
local selectedItem = nil
local selectedQty = 1
local isCartMode = false
local cart = {}
local ed_data = {}
local log_filter = ""
local search_query = ""
local search_focus = false

local currentPage = 1
local ITEMS_PER_PAGE = 20
local adminPage = 1
local ADMIN_ITEMS_PER_PAGE = 17

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
        file:write(""); file:close()
        local lastModifiedMs = fs.lastModified(tmp_file)
        fs.remove(tmp_file)
        if lastModifiedMs and lastModifiedMs > 0 then
            local current_unix = math.floor(lastModifiedMs / 1000)
            return formatUnixTime(current_unix + (tz * 3600))
        end
    end
    return os.date("%Y-%m-%d %H:%M:%S") .. " (Игр.)"
end

-- Возвращает unix-timestamp в миллисекундах (UTC) — реальное серверное время.
-- Браузер на дашборде сравнивает это с Date.now() напрямую, без timezone-плясок.
local function getRealTimeMs()
    local tmp = "/home/HostTime.tmp"
    local f = io.open(tmp, "w")
    if f then
        f:write(""); f:close()
        local lm = fs.lastModified(tmp)
        fs.remove(tmp)
        if lm and lm > 0 then return lm end
    end
    return nil
end

-- Heartbeat для дашборда. Шлёт компактный snapshot статуса в /heartbeats/shop.
sendHeartbeat = function(stopped)
    if not (config.use_database and component.isAvailable("internet")) then return end
    if not config.firebase_url or config.firebase_url == "" or config.firebase_url == "заменить" then return end
    if not startedAt then startedAt = getRealTime() end
    pcall(function()
        network.put("/heartbeats/shop", json.encode({
            name = "Магазин",
            type = "shop",
            last_seen = getRealTime(),
            last_seen_ms = getRealTimeMs(),
            started_at = startedAt,
            shop_name = shop_name or "?",
            items_count = #shop_items,
            buyback_count = #shop_buyback,
            online_user = (currentUser and currentUser.name) or nil,
            cart_size = (currentUser and cart) and #cart or 0,
            stopped = stopped or false,
        }))
    end)
end

-- Логирование ТОЛЬКО в Firebase /logs. На диске не сохраняем — экономим RAM/диск OC.
local function writeLog(action, user, details)
    if not (config.use_database and component.isAvailable("internet")) then return end
    pcall(function()
        network.request("POST", "/logs", json.encode({
            time = getRealTime(),
            action = action,
            user = user,
            details = details,
        }))
    end)
end

-- Старый локальный лог-файл больше не нужен — если остался от прошлых версий, удаляем
pcall(function() if fs.exists("/home/shop_logs.txt") then fs.remove("/home/shop_logs.txt") end end)

local function loadLogsLocal(filter)
    -- больше не используется — оставлена-заглушка для совместимости старого UI.
    -- Возвращает пояснительное сообщение вместо логов.
    local logs = {}
    if false then
        for line in (function() end) do end
        if filter then end
    end
    -- логи теперь только в админке сайта
    return {
        "Логи теперь только в админке (Firebase).",
        "Открой /HiTechClassic-Shop.html на сервере → вкладка \"Логи\".",
        "На компьютере локальные логи отключены для экономии памяти.",
    }
end

local function loadUsersLocal()
    local f = io.open("/home/users.json", "r")
    if f then
        local data = f:read("*a")
        if data and data ~= "" then users_db = json.decode(data) or {} end
        f:close()
    end
end

local function loadShopLocal()
    local f = io.open("/home/shop_data.json", "r")
    if f then
        local data = f:read("*a")
        f:close()
        if data and data ~= "" then
            local parsed = json.decode(data)
            if parsed then
                if parsed.categories then categories = parsed.categories end
                if parsed.items then shop_items = parsed.items end
                if parsed.buyback then shop_buyback = parsed.buyback end
                if parsed.shop_name then shop_name = parsed.shop_name end
            end
        end
    end
end

local function saveUser()
    if not currentUser then return end
    if not users_db[currentUser.name] then users_db[currentUser.name] = {} end
    users_db[currentUser.name].balance = currentUser.balance
    local f = io.open("/home/users.json", "w")
    if f then f:write(json.encode(users_db)); f:close() end
    if config.use_database and component.isAvailable("internet") then
        pcall(function() network.put("/users/" .. currentUser.name, json.encode({ balance = currentUser.balance })) end)
    end
end

local function saveShop()
    local data = { categories = categories, items = shop_items, buyback = shop_buyback, shop_name = shop_name }
    local encoded = json.encode(data)
    local f = io.open("/home/shop_data.json", "w")
    if f then f:write(encoded); f:close() end
    if config.use_database and component.isAvailable("internet") then
        pcall(function() network.put("/shop", encoded) end)
    end
end

local function loadDB()
    if config.use_database and component.isAvailable("internet") then
        local succ_shop, res_shop = network.get("/shop")
        if succ_shop and res_shop and res_shop ~= "null" then
            local parsed = json.decode(res_shop)
            if parsed then
                if parsed.categories then categories = parsed.categories end
                if parsed.items then shop_items = parsed.items end
                if parsed.buyback then shop_buyback = parsed.buyback end
                if parsed.shop_name then shop_name = parsed.shop_name end
            end
        else loadShopLocal() end
        local succ_u, res_u = network.get("/users")
        if succ_u and res_u and res_u ~= "null" then
            local parsed_u = json.decode(res_u)
            if parsed_u then users_db = parsed_u end
        else loadUsersLocal() end
    else
        loadShopLocal()
        loadUsersLocal()
    end
end

local function getTop3Players()
    local sorted = {}
    for name, data in pairs(users_db) do table.insert(sorted, {name = name, balance = data.balance}) end
    table.sort(sorted, function(a, b) return a.balance > b.balance end)
    local top3 = {}
    for i = 1, math.min(3, #sorted) do table.insert(top3, sorted[i]) end
    return top3
end

local function getPageItems()
    local filtered = {}
    local q = (search_query ~= "") and unicode.lower(search_query) or nil
    for i, item in ipairs(shop_items) do
        local catOk = (active_category == "ВСЕ") or (item.category == active_category)
        local searchOk = true
        if q then
            local name_l = unicode.lower(item.name or "")
            searchOk = string.find(name_l, q, 1, true) ~= nil
        end
        if catOk and searchOk then table.insert(filtered, {item = item, origIdx = i}) end
    end
    -- Алфавитная сортировка по названию (case-insensitive).
    -- Для UTF-8 кириллицы порядок байтов совпадает с алфавитным, для латиницы тоже.
    table.sort(filtered, function(a, b)
        return unicode.lower(a.item.name or "") < unicode.lower(b.item.name or "")
    end)
    local maxPage = math.ceil(#filtered / ITEMS_PER_PAGE)
    if maxPage < 1 then maxPage = 1 end
    if currentPage > maxPage then currentPage = maxPage end
    local pageData = {}
    local startIdx = (currentPage - 1) * ITEMS_PER_PAGE + 1
    local endIdx = math.min(startIdx + ITEMS_PER_PAGE - 1, #filtered)
    for i = startIdx, endIdx do table.insert(pageData, filtered[i]) end
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

local function refreshScreen()
    if state == "shop" then
        me.updateStock(shop_items)
        gui.drawStatic(currentUser, currentUser and idleTimer or nil, #cart, getTop3Players(), shop_name)
        gui.drawSearch(search_query, search_focus)
        gui.drawCategories(categories, active_category)
        local pItems, maxPage = getPageItems()
        gui.drawItems(pItems, currentPage, maxPage)
        gui.drawBuybackItems(shop_buyback)
        if not me_ok then component.gpu.set(2, component.gpu.getResolution(), "СИСТЕМНАЯ ОШИБКА: " .. me_msg) end
    elseif state == "modal_qty" then
        gui.drawStatic(currentUser, idleTimer, #cart, getTop3Players(), shop_name)
        gui.drawQuantitySelector(selectedItem, selectedQty, isCartMode)
    elseif state == "cart" then
        gui.drawStatic(currentUser, idleTimer, #cart, getTop3Players(), shop_name)
        gui.drawCart(cart)
    elseif string.match(state, "admin") and state ~= "admin_wait_scan" then
        local listToPass = {}
        local perPage = ADMIN_ITEMS_PER_PAGE
        if state == "admin_cat" then listToPass = categories
        elseif state == "admin_item" then listToPass = shop_items
        elseif state == "admin_buy" then listToPass = shop_buyback
        elseif state == "admin_logs" then 
            listToPass = loadLogsLocal(log_filter)
            perPage = 30
        end
        local pItems, maxP = getAdminPageItems(listToPass, perPage)
        gui.drawAdmin(state:gsub("admin_", ""), pItems, adminPage, maxP, log_filter)
    elseif state == "editor" then
        gui.drawStatic(currentUser, idleTimer, #cart, getTop3Players(), shop_name)
        gui.drawEditorModal(ed_data, categories)
    end
end

local function showMsg(title, text, isError, timeout)
    state = "modal_msg"
    msgTimer = timeout or 0
    gui.drawNotification(title, text, isError)
end

loadDB()
refreshScreen()

-- =========================================================================
-- ТЕЛО МАГАЗИНА, ВЫНЕСЕННОЕ В ОТДЕЛЬНУЮ ФУНКЦИЮ (ДЛЯ WATCHDOG)
-- =========================================================================
local function shopTick()
    local ev, _, arg1, arg2, arg3, arg4, arg5 = event.pull(1)

    -- Heartbeat для дашборда: раз в ~30 секунд
    heartbeatTimer = heartbeatTimer + 1
    if heartbeatTimer >= 30 then
        heartbeatTimer = 0
        sendHeartbeat()
    end

    if not ev then
        local shouldRefreshFull = false
        if state == "modal_msg" and msgTimer > 0 then
            msgTimer = msgTimer - 1
            if msgTimer <= 0 then state = "shop"; shouldRefreshFull = true end
        end
        if currentUser and state ~= "modal_msg" and state ~= "admin_wait_scan" and state ~= "editor" and not string.match(state, "admin") then
            idleTimer = idleTimer - 1
            if idleTimer <= 0 then 
                currentUser = nil; cart = {}; state = "shop"; active_category = "ВСЕ"; currentPage = 1
                shouldRefreshFull = true
            else
                if state == "shop" or state == "modal_qty" or state == "cart" then gui.drawTick(currentUser, idleTimer) end
            end
        end
        if state == "shop" and not shouldRefreshFull then
            if config.use_database and component.isAvailable("internet") then
                syncTimer = syncTimer - 1
                if syncTimer <= 0 then
                    syncTimer = 15
                    local s, r = network.get("/shop")
                    if s and r and r ~= "null" then
                        local p = json.decode(r)
                        if p then
                            if p.categories then categories = p.categories end
                            if p.items then shop_items = p.items end
                            if p.buyback then shop_buyback = p.buyback end
                            if p.shop_name then shop_name = p.shop_name end
                        end
                    end
                    local su, ru = network.get("/users")
                    if su and ru and ru ~= "null" then
                        local pu = json.decode(ru)
                        if pu then users_db = pu end
                        if currentUser and users_db[currentUser.name] then
                            currentUser.balance = users_db[currentUser.name].balance
                        end
                    end
                    shouldRefreshFull = true
                end
            end
        end
        if shouldRefreshFull then refreshScreen() end
    else
        if currentUser then idleTimer = 30 end

        -- === ПЕРЕХВАТЧИК ЗАКРЫТИЯ ПРИЛОЖЕНИЯ ===
        if ev == "interrupted" then
            if currentUser and currentUser.isAdmin then
                component.gpu.setBackground(0x000000)
                component.gpu.setForeground(0xFFFFFF)
                require("term").clear()
                print("Программа завершена администратором: " .. currentUser.name)
                error("ADMIN_EXIT") -- Генерируем кодовое слово для выхода
            else
                showMsg("ОТКАЗАНО В ДОСТУПЕ", "Только администратор может закрыть программу!", true, 3)
            end
            
        elseif ev == "key_down" and state == "shop" and search_focus then
            local char = arg1; local code = arg2
            if currentUser then idleTimer = 30 end
            if code == 28 or code == 1 then
                -- enter / esc — снимаем фокус
                search_focus = false
            elseif code == 14 then
                -- backspace
                if unicode.len(search_query) > 0 then
                    search_query = unicode.sub(search_query, 1, -2)
                    currentPage = 1
                end
            elseif char and char >= 32 then
                search_query = search_query .. unicode.char(char)
                currentPage = 1
            end
            refreshScreen()

        elseif ev == "clipboard" and state == "shop" and search_focus then
            if currentUser then idleTimer = 30 end
            search_query = search_query .. tostring(arg1 or "")
            currentPage = 1
            refreshScreen()

        elseif ev == "key_down" and state == "editor" then
            local char = arg1; local code = arg2
            local val = (ed_data.focus == "name") and ed_data.name or tostring(ed_data.price)
            if code == 14 then
                if unicode.len(val) > 0 then val = unicode.sub(val, 1, -2) end
            elseif char >= 32 then val = val .. unicode.char(char) end
            if ed_data.focus == "name" then ed_data.name = val else ed_data.price = val end
            refreshScreen()
            
        elseif ev == "clipboard" and state == "editor" then
            local text = arg1
            if ed_data.focus == "name" then ed_data.name = ed_data.name .. text
            else ed_data.price = tostring(ed_data.price) .. text end
            refreshScreen()

        elseif ev == "scroll" then
            local dir = arg4
            local player_name = arg5
            if currentUser and currentUser.name ~= player_name then computer.beep(400, 0.1)
            else
                if state == "shop" then
                    if dir > 0 and currentPage > 1 then currentPage = currentPage - 1; refreshScreen()
                    elseif dir < 0 then currentPage = currentPage + 1; refreshScreen() end
                elseif string.match(state, "admin") then
                    if dir > 0 and adminPage > 1 then adminPage = adminPage - 1; refreshScreen()
                    elseif dir < 0 then adminPage = adminPage + 1; refreshScreen() end
                end
            end

        elseif ev == "touch" then
            local x = arg1; local y = arg2; local player_name = arg4

            if currentUser and currentUser.name ~= player_name then computer.beep(400, 0.1)
            else
                local action = gui.checkClick(x, y)
                if action then
                    computer.beep(1000, 0.05)
                    -- любой клик кроме самого инпута поиска снимает фокус
                    if action ~= "search" and action ~= "clear_search" then search_focus = false end
                    
                    if action == "page_prev" then currentPage = currentPage - 1; refreshScreen()
                    elseif action == "page_next" then currentPage = currentPage + 1; refreshScreen()
                    elseif action == "adm_prev" then adminPage = adminPage - 1; refreshScreen()
                    elseif action == "adm_next" then adminPage = adminPage + 1; refreshScreen()
                    elseif action == "close_admin" then state = "shop"; refreshScreen()
                    elseif action == "open_cart" then state = "cart"; refreshScreen()
                    
                    elseif action == "filter_logs" then
                        ed_data = {target = "log_filter", focus = "name", name = log_filter, isItem = false}
                        state = "editor"; refreshScreen()
                    elseif action == "clear_filter" then
                        log_filter = ""; adminPage = 1; refreshScreen()

                    elseif action == "adm_name" then
                        ed_data = {target = "shop_name", focus = "name", name = shop_name, isItem = false}
                        state = "editor"; refreshScreen()
                        
                    elseif action:match("adm_edit_") then
                        local origIdx = tonumber(action:match("%d+"))
                        if state == "admin_cat" then
                            ed_data = {target = "edit_cat", focus = "name", name = categories[origIdx], orig_idx = origIdx}
                            state = "editor"; refreshScreen()
                        elseif state == "admin_item" then
                            local it = shop_items[origIdx]
                            ed_data = {target = "edit_item", focus = "price", name = it.name, price = tostring(it.price), cat = it.category, orig_id = it.id, damage = it.damage, orig_name = it.orig_label, orig_idx = origIdx, isItem = true}
                            state = "editor"; refreshScreen()
                        elseif state == "admin_buy" then
                            local it = shop_buyback[origIdx]
                            ed_data = {target = "edit_buyback", focus = "price", name = it.name, price = tostring(it.price), orig_id = it.id, damage = it.damage, orig_name = it.orig_label, orig_idx = origIdx, isItem = false}
                            state = "editor"; refreshScreen()
                        end
                    
                    elseif action == "close_modal" then
                        if state == "admin_wait_scan" then
                            local stack, slot = me.peekInput()
                            if not stack then
                                state = (ed_data.target == "item") and "admin_item" or "admin_buy"
                                showMsg("ОШИБКА СКАНЕРА", slot, true)
                            else
                                ed_data.isItem = (ed_data.target == "item")
                                ed_data.orig_name = stack.label
                                ed_data.orig_id = stack.name
                                ed_data.damage = stack.damage or 0
                                ed_data.name = stack.label
                                ed_data.price = ""
                                ed_data.cat = categories[2] or "ВСЕ"
                                ed_data.focus = "name"
                                ed_data.slot = slot
                                state = "editor"; refreshScreen()
                            end
                        else state = "shop"; msgTimer = 0; refreshScreen() end
                    
                    elseif state == "editor" then
                        if action == "focus_name" then ed_data.focus = "name"; refreshScreen()
                        elseif action == "focus_price" then ed_data.focus = "price"; refreshScreen()
                        elseif action:match("setcat_") then ed_data.cat = action:gsub("setcat_", ""); refreshScreen()
                        elseif action == "ed_cancel" then
                            if ed_data.target == "shop_name" or ed_data.target == "edit_cat" then state = "admin_cat"
                            elseif ed_data.target == "edit_item" then state = "admin_item"
                            elseif ed_data.target == "edit_buyback" then state = "admin_buy"
                            elseif ed_data.target == "log_filter" then state = "admin_logs"
                            elseif ed_data.target == "search" then state = "shop"
                            else state = (ed_data.target == "item") and "admin_item" or "admin_buy" end
                            refreshScreen()
                        elseif action == "ed_save" then
                            if ed_data.target == "log_filter" then
                                log_filter = ed_data.name; state = "admin_logs"; adminPage = 1; refreshScreen()
                            elseif ed_data.target == "search" then
                                search_query = ed_data.name; currentPage = 1; state = "shop"; refreshScreen()
                            elseif ed_data.target == "shop_name" then
                                shop_name = ed_data.name; saveShop(); state = "admin_cat"; refreshScreen()
                            elseif ed_data.target == "edit_cat" then
                                local old_name = categories[ed_data.orig_idx]
                                categories[ed_data.orig_idx] = ed_data.name
                                for _, it in ipairs(shop_items) do if it.category == old_name then it.category = ed_data.name end end
                                saveShop(); state = "admin_cat"; refreshScreen()
                            elseif ed_data.target == "edit_item" then
                                local p_str = tostring(ed_data.price):gsub(",", ".")
                                if p_str == "" or not tonumber(p_str) then showMsg("ОШИБКА", "Введите цену (число)!", true); return end
                                local it = shop_items[ed_data.orig_idx]
                                it.name = ed_data.name; it.price = tonumber(p_str); it.category = ed_data.cat
                                saveShop(); state = "admin_item"; refreshScreen()
                            elseif ed_data.target == "edit_buyback" then
                                local p_str = tostring(ed_data.price):gsub(",", ".")
                                if p_str == "" or not tonumber(p_str) then showMsg("ОШИБКА", "Введите цену (число)!", true); return end
                                local it = shop_buyback[ed_data.orig_idx]
                                it.name = ed_data.name; it.price = tonumber(p_str)
                                saveShop(); state = "admin_buy"; refreshScreen()
                            else
                                local p_str = tostring(ed_data.price):gsub(",", ".")
                                if p_str == "" or not tonumber(p_str) then
                                    showMsg("ОШИБКА", "Введите корректную цену (число)!", true)
                                else
                                    if ed_data.isItem then
                                        table.insert(shop_items, { name = ed_data.name, price = tonumber(p_str), category = ed_data.cat, stock = 0, id = ed_data.orig_id, damage = ed_data.damage, orig_label = ed_data.orig_name })
                                        writeLog("ДОБАВЛЕН ТОВАР", currentUser.name, ed_data.name .. " за " .. p_str .. " " .. CUR)
                                    else
                                        table.insert(shop_buyback, { name = ed_data.name, price = tonumber(p_str), id = ed_data.orig_id, damage = ed_data.damage, orig_label = ed_data.orig_name })
                                        writeLog("ДОБАВЛЕНА СКУПКА", currentUser.name, ed_data.name .. " по " .. p_str .. " " .. CUR)
                                    end
                                    saveShop(); state = (ed_data.target == "item") and "admin_item" or "admin_buy"; refreshScreen()
                                end
                            end
                        end
                    
                    elseif state == "shop" then
                        if action == "login" then
                            local is_adm = false; if config.admins and config.admins[player_name] then is_adm = true end
                            local bal = 0
                            if users_db[player_name] then bal = users_db[player_name].balance
                            else
                                if config.use_database and component.isAvailable("internet") then
                                    local succ, res = network.get("/users/" .. player_name)
                                    if succ and res and res ~= "null" then
                                        local udata = json.decode(res)
                                        if udata and udata.balance then bal = udata.balance end
                                    end
                                end
                            end
                            currentUser = { name = player_name, balance = bal, isAdmin = is_adm }; idleTimer = 30; refreshScreen()
                        
                        elseif action == "logout" then currentUser = nil; cart = {}; currentPage = 1; refreshScreen()
                        elseif action == "admin_panel" then state = "admin_item"; adminPage = 1; refreshScreen()
                        elseif action == "search" then
                            -- клик по инпуту: ставим/снимаем фокус, дальше ввод идёт прямо в строку
                            search_focus = not search_focus; refreshScreen()
                        elseif action == "clear_search" then
                            search_query = ""; currentPage = 1; search_focus = true; refreshScreen()
                        elseif action:match("cat_") then
                            active_category = action:gsub("cat_", ""); currentPage = 1; search_focus = false; refreshScreen()
                        elseif action == "sell_all" then
                            if not currentUser then showMsg("ОШИБКА", "Авторизуйтесь!", true)
                            else
                                local success, msg, earned = me.sellAll(shop_buyback)
                                if success then 
                                    currentUser.balance = currentUser.balance + earned; saveUser()
                                    writeLog("ПРОДАЖА", currentUser.name, msg .. " Начислено: " .. earned .. " " .. CUR)
                                    showMsg("УСПЕШНАЯ СДАЧА", msg .. " Зачислено: " .. earned .. " " .. CUR, false, 3)
                                else showMsg("ОШИБКА", msg, true) end
                            end
                            
                        elseif action:match("buy_") or action:match("cart_") then
                            if not currentUser then showMsg("ОШИБКА", "Авторизуйтесь!", true)
                            else
                                local origIdx = tonumber(action:match("%d+"))
                                selectedItem = shop_items[origIdx]
                                selectedQty = 1; isCartMode = (action:match("cart_") ~= nil)
                                state = "modal_qty"; refreshScreen()
                            end
                        end
                    
                    elseif state == "modal_qty" then
                        if action == "qty_add1" then selectedQty = selectedQty + 1
                        elseif action == "qty_sub1" then selectedQty = selectedQty - 1
                        elseif action == "qty_add10" then selectedQty = selectedQty + 10
                        elseif action == "qty_sub10" then selectedQty = selectedQty - 10
                        elseif action == "qty_add100" then selectedQty = selectedQty + 100
                        elseif action == "qty_sub100" then selectedQty = selectedQty - 100
                        elseif action == "qty_add1000" then selectedQty = selectedQty + 1000
                        elseif action == "qty_sub1000" then selectedQty = selectedQty - 1000
                        elseif action == "confirm_cart" then 
                            if selectedItem.stock < selectedQty then
                                showMsg("ОШИБКА", "В наличии только " .. (selectedItem.stock or 0) .. " шт!", true)
                            else
                                table.insert(cart, {item = selectedItem, qty = selectedQty}); state = "shop"; refreshScreen()
                            end
                        elseif action == "confirm_buy" then
                            local cost = selectedItem.price * selectedQty
                            if selectedItem.stock < selectedQty then showMsg("ОШИБКА", "Не хватает товара в МЭ!", true)
                            elseif currentUser.balance < cost then showMsg("ОШИБКА", "Мало " .. CUR .. "!", true)
                            else
                                local ok, msg, actual_moved = me.buyItem(selectedItem, selectedQty)
                                if ok and actual_moved and actual_moved > 0 then
                                    local actual_cost = selectedItem.price * actual_moved
                                    currentUser.balance = currentUser.balance - actual_cost; saveUser(); saveShop()
                                    writeLog("ПОКУПКА", currentUser.name, "Куплено: " .. selectedItem.name .. " x" .. actual_moved .. " за " .. actual_cost .. " " .. CUR)
                                    if actual_moved < selectedQty then showMsg("ВНИМАНИЕ", "Сундук полон! Выдано " .. actual_moved .. " шт. Списано: " .. actual_cost .. " " .. CUR, true, 6)
                                    else showMsg("УСПЕХ", "Выдано " .. actual_moved .. " шт. за " .. actual_cost .. " " .. CUR, false, 3) end
                                else showMsg("ОШИБКА ВЫДАЧИ", msg, true) end
                            end
                        end
                        if selectedQty < 1 then selectedQty = 1 end
                        if selectedQty > 64000 then selectedQty = 64000 end
                        if state == "modal_qty" then refreshScreen() end
                    
                    elseif state == "cart" then
                        if action:match("cart_del_") then table.remove(cart, tonumber(action:match("%d+"))); refreshScreen()
                        elseif action == "checkout" then
                            if #cart == 0 then showMsg("ОШИБКА", "Корзина пуста!", true)
                            else
                                local totalCost = 0
                                for _, ci in ipairs(cart) do totalCost = totalCost + (ci.item.price * ci.qty) end
                                if currentUser.balance < totalCost then showMsg("ОШИБКА", "Недостаточно средств!", true)
                                else
                                    local all_ok, actual_total = true, 0
                                    local receipt_str = ""
                                    for _, ci in ipairs(cart) do
                                        local ok, msg, actual_moved = me.buyItem(ci.item, ci.qty)
                                        if ok and actual_moved and actual_moved > 0 then
                                            actual_total = actual_total + (ci.item.price * actual_moved)
                                            receipt_str = receipt_str .. ci.item.name .. "(x" .. actual_moved .. ") "
                                            if actual_moved < ci.qty then all_ok = false end
                                        else all_ok = false end
                                    end
                                    currentUser.balance = currentUser.balance - actual_total; cart = {}; saveUser(); saveShop()
                                    if receipt_str == "" then receipt_str = "ОШИБКА ВЫДАЧИ " end
                                    writeLog("ПОКУПКА (КОРЗИНА)", currentUser.name, receipt_str .. "на сумму " .. actual_total .. " " .. CUR)
                                    
                                    if all_ok then showMsg("ОПЛАТА", "Покупки успешно выданы!", false, 3)
                                    else showMsg("ВНИМАНИЕ", "Места не хватило. Выдано частично! Списано: " .. actual_total .. " " .. CUR, true, 6) end
                                end
                            end
                        end
                    elseif string.match(state, "admin") then
                        if action == "adm_cat" then state = "admin_cat"; adminPage = 1; refreshScreen()
                        elseif action == "adm_item" then state = "admin_item"; adminPage = 1; refreshScreen()
                        elseif action == "adm_buy" then state = "admin_buy"; adminPage = 1; refreshScreen()
                        elseif action == "adm_logs" then state = "admin_logs"; adminPage = 1; refreshScreen()
                        elseif action == "adm_name" then ed_data = {target = "shop_name", focus = "name", name = shop_name, isItem = false}; state = "editor"; refreshScreen()
                        elseif action == "adm_add" then
                            if state == "admin_cat" then
                                ed_data = {target = "edit_cat", focus = "name", name = "Новая категория", orig_idx = #categories + 1}
                                table.insert(categories, "Новая категория"); state = "editor"; refreshScreen()
                            else
                                ed_data.target = (state == "admin_item") and "item" or "buyback"; state = "admin_wait_scan"
                                gui.drawNotification("СКАНИРОВАНИЕ", "Положите 1 предмет в левый сундук и нажмите ОК", false)
                            end
                        elseif action:match("adm_del_") then
                            local idx = tonumber(action:match("%d+"))
                            if state == "admin_cat" then table.remove(categories, idx)
                            elseif state == "admin_item" then writeLog("УДАЛЕН ТОВАР", currentUser.name, shop_items[idx].name); table.remove(shop_items, idx)
                            elseif state == "admin_buy" then writeLog("УДАЛЕНА СКУПКА", currentUser.name, shop_buyback[idx].name); table.remove(shop_buyback, idx) end
                            saveShop(); refreshScreen()
                        end
                    end
                end
            end
        end
    end
end

-- =========================================================================
-- СТОРОЖЕВОЙ ПЕС (WATCHDOG) С ВОЗМОЖНОСТЬЮ ВЫХОДА ДЛЯ АДМИНА
-- =========================================================================
while true do
    local ok, err = pcall(shopTick)
    if not ok then
        -- ПРОПУСКАЕМ АДМИНА В КОНСОЛЬ:
        if tostring(err):match("ADMIN_EXIT") then break end
        
        local f = io.open("/home/shop_crash.log", "a")
        if f then 
            f:write(os.date("%Y-%m-%d %H:%M:%S") .. " | FATAL CRASH: " .. tostring(err) .. "\n")
            f:close() 
        end
        
        os.sleep(3)
        computer.shutdown(true) 
    end
end