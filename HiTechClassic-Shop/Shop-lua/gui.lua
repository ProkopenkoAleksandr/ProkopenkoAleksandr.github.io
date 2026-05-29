-- /lua/gui.lua
local component = require("component")
local term = require("term")
local unicode = require("unicode")
local config = require("config")
local gpu = component.gpu

local gui = {}
gui.buttons = {}
local CUR = config.currency_name or "ЭМ"

gui.COLORS = {
    bg = 0x111111, tileBg = 0x222222, tileHeader = 0x333333,
    text = 0xEEEEEE, label = 0x999999, good = 0x55FF55, warn = 0xFFAA00, bad = 0xFF5555,
    energy = 0x00AAFF, btn = 0x444444, btnActive = 0x006699, panel = 0x181818,
    modalGood = 0x004400, modalBad = 0x660000, inputBg = 0x000000, inputFocus = 0x444444
}

local W, H = gpu.getResolution()
local rightColX = math.floor(W * 0.75) + 1
local rightColW = W - rightColX + 1

local function rect(x, y, w, h, col) gpu.setBackground(col); gpu.fill(x, y, w, h, " ") end
local function text(x, y, str, fg, bg) if bg then gpu.setBackground(bg) end; gpu.setForeground(fg); gpu.set(x, y, str) end
local function center(x, y, w, str, fg, bg) 
    if bg then gpu.setBackground(bg) end; gpu.fill(x, y, w, 1, " ")
    local px = x + math.floor((w - unicode.len(str))/2)
    if fg then gpu.setForeground(fg) end; gpu.set(px, y, str) 
end

function gui.btn(id, x, y, w, h, str, bg, fg) 
    local actualFg = fg or gui.COLORS.text
    if bg == gui.COLORS.good then actualFg = gui.COLORS.bg end
    rect(x, y, w, h, bg); center(x, y + math.floor(h/2), w, str, actualFg, bg)
    gui.buttons[id] = {x=x, y=y, w=w, h=h} 
end

function gui.drawStatic(user, timer, cart_count, top3, shopName)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    rect(1, 1, rightColX - 1, 3, gui.COLORS.panel)
    center(1, 2, rightColX - 1, shopName or "МЭ МАГАЗИН", gui.COLORS.energy, gui.COLORS.panel)

    rect(rightColX, 1, rightColW, H, gui.COLORS.panel)
    
    local rY = 2
    if user then
        gui.btn("logout", rightColX + 2, rY, rightColW - 4, 3, "ВЫХОД", gui.COLORS.bad)
        rY = rY + 4
        center(rightColX, rY, rightColW, user.name, gui.COLORS.good, gui.COLORS.panel); rY = rY + 1
        center(rightColX, rY, rightColW, user.balance .. " " .. CUR, gui.COLORS.warn, gui.COLORS.panel); rY = rY + 2
        if timer then center(rightColX, rY, rightColW, "Выход через: " .. timer .. "с", gui.COLORS.label, gui.COLORS.panel) end
        rY = rY + 2
        gui.btn("open_cart", rightColX + 2, rY, rightColW - 4, 3, "КОРЗИНА (" .. (cart_count or 0) .. ")", gui.COLORS.btnActive)
        rY = rY + 4
        if user.isAdmin then gui.btn("admin_panel", rightColX + 2, rY, rightColW - 4, 1, "АДМИН ПАНЕЛЬ", gui.COLORS.energy); rY = rY + 2 end
    else
        gui.btn("login", rightColX + 2, rY, rightColW - 4, 3, "АВТОРИЗАЦИЯ", gui.COLORS.good)
        rY = rY + 4
        center(rightColX, rY, rightColW, "Войдите для покупок", gui.COLORS.label, gui.COLORS.panel)
        rY = rY + 3
    end

    rect(rightColX, rY, rightColW, 1, gui.COLORS.tileHeader)
    center(rightColX, rY, rightColW, "ТОП 3 БОГАЧЕЙ:", gui.COLORS.warn, gui.COLORS.tileHeader)
    rY = rY + 2
    if top3 and #top3 > 0 then
        for i, t in ipairs(top3) do
            text(rightColX + 2, rY, i .. ". " .. t.name, gui.COLORS.text, gui.COLORS.panel)
            text(rightColX + rightColW - string.len(tostring(t.balance)) - string.len(CUR) - 3, rY, t.balance .. " " .. CUR, gui.COLORS.good, gui.COLORS.panel)
            rY = rY + 1
        end
    else
        center(rightColX, rY, rightColW, "Нет данных", gui.COLORS.label, gui.COLORS.panel); rY = rY + 1
    end
    rY = rY + 1

    rect(rightColX, rY, rightColW, 1, gui.COLORS.tileHeader)
    center(rightColX, rY, rightColW, "МЫ СКУПАЕМ:", gui.COLORS.text, gui.COLORS.tileHeader)
    gui.buybackY = rY + 2
end

function gui.drawCategories(categories, active_cat, search_query)
    local x = 2; local y = 5
    for i, cat in ipairs(categories) do
        local catW = unicode.len(cat) + 4
        local bg = (cat == active_cat) and gui.COLORS.btnActive or gui.COLORS.btn
        gui.btn("cat_"..cat, x, y, catW, 1, cat, bg)
        x = x + catW + 1
    end
    -- Кнопка поиска: рядом с категориями. Показывает текущий запрос, если задан.
    local sq = search_query or ""
    local label = (sq == "") and "ПОИСК" or ("ПОИСК: " .. unicode.sub(sq, 1, 14))
    local sw = unicode.len(label) + 4
    local searchBg = (sq == "") and gui.COLORS.btn or gui.COLORS.btnActive
    gui.btn("search", x, y, sw, 1, label, searchBg)
    x = x + sw + 1
    if sq ~= "" then
        gui.btn("clear_search", x, y, 5, 1, " X ", gui.COLORS.bad)
    end
end

function gui.drawItems(pageItems, page, maxPage)
    rect(1, 7, rightColX - 1, H - 6, gui.COLORS.bg)
    local margin = 2; local cols = 4;
    local tileW = math.floor((rightColX - (cols + 1) * margin) / cols); local tileH = 6
    local row, col = 0, 0
    
    for _, pItem in ipairs(pageItems) do
        local item = pItem.item
        local id = pItem.origIdx
        local x = margin + col * (tileW + margin); local y = 7 + row * (tileH + 1)
        
        rect(x, y, tileW, tileH, gui.COLORS.tileBg)
        center(x, y, tileW, item.name, gui.COLORS.text, gui.COLORS.tileHeader)
        text(x + 2, y + 2, "Цена: " .. item.price .. " " .. CUR, gui.COLORS.warn, gui.COLORS.tileBg)
        
        local stockCol = (item.stock and item.stock > 0) and gui.COLORS.label or gui.COLORS.bad
        text(x + 2, y + 3, "В МЭ: " .. (item.stock or 0), stockCol, gui.COLORS.tileBg)
        
        local halfW = math.floor(tileW/2)
        gui.btn("buy_"..id, x, y + 5, halfW - 1, 1, "КУПИТЬ", gui.COLORS.good)
        gui.btn("cart_"..id, x + halfW, y + 5, tileW - halfW, 1, "В КОРЗИНУ", gui.COLORS.energy)
        
        col = col + 1; if col >= cols then col = 0; row = row + 1 end
    end

    local py = H - 3
    if page > 1 then gui.btn("page_prev", 2, py, 14, 3, "<- НАЗАД", gui.COLORS.btnActive) end
    center(1, py + 1, rightColX - 1, "Страница " .. page .. " из " .. maxPage, gui.COLORS.text, gui.COLORS.bg)
    if page < maxPage then gui.btn("page_next", rightColX - 16, py, 14, 3, "ВПЕРЕД ->", gui.COLORS.btnActive) end
end

function gui.drawTick(user, timer)
    if user and timer then center(rightColX, 9, rightColW, "Выход через: " .. timer .. "с   ", gui.COLORS.label, gui.COLORS.panel) end
end

function gui.drawBuybackItems(buyback_items)
    local startY = gui.buybackY or 20
    local x = rightColX + 2; local w = rightColW - 4
    for i, item in ipairs(buyback_items) do
        if startY < H - 4 then
            text(x, startY, "- " .. item.name .. " (" .. item.price .. " " .. CUR .. ")", gui.COLORS.warn, gui.COLORS.panel)
            startY = startY + 1
        end
    end
    gui.btn("sell_all", x, H - 3, w, 3, "ПРОДАТЬ ВСЁ", gui.COLORS.good)
end

function gui.drawNotification(title, message, isError)
    gui.buttons = {}; local w = 60
    
    local lines = {}
    local currentLine = ""
    for word in string.gmatch(message, "%S+") do
        if unicode.len(currentLine) + unicode.len(word) + 1 > w - 4 then
            table.insert(lines, currentLine)
            currentLine = word
        else
            currentLine = currentLine == "" and word or (currentLine .. " " .. word)
        end
    end
    if currentLine ~= "" then table.insert(lines, currentLine) end

    local h = math.max(10, 7 + #lines)
    local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    local titleCol = isError and gui.COLORS.modalBad or gui.COLORS.modalGood
    
    rect(x, y, w, h, gui.COLORS.tileBg); rect(x, y, w, 2, titleCol)
    center(x, y, w, title, gui.COLORS.text, titleCol)
    
    for i, l in ipairs(lines) do center(x, y + 2 + i, w, l, gui.COLORS.text, gui.COLORS.tileBg) end
    
    gui.btn("close_modal", x + 20, y + h - 3, 20, 1, "ОК", gui.COLORS.btn)
end

function gui.drawQuantitySelector(item, qty, isCartMode)
    gui.buttons = {}; local w = 48; local h = 14; local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    rect(x, y, w, h, gui.COLORS.tileBg); rect(x, y, w, 2, gui.COLORS.tileHeader)
    center(x, y, w, "ВЫБОР: " .. item.name, gui.COLORS.text, gui.COLORS.tileHeader)
    center(x, y + 3, w, "В наличии: " .. (item.stock or 0) .. " шт", gui.COLORS.label, gui.COLORS.tileBg)
    center(x, y + 5, w, "Количество: " .. qty, gui.COLORS.text, gui.COLORS.tileBg)
    
    gui.btn("qty_sub10", x + 8, y + 7, 6, 1, "-10", gui.COLORS.bad)
    gui.btn("qty_sub1", x + 15, y + 7, 6, 1, "-1", gui.COLORS.bad)
    gui.btn("qty_add1", x + 27, y + 7, 6, 1, "+1", gui.COLORS.good)
    gui.btn("qty_add10", x + 34, y + 7, 6, 1, "+10", gui.COLORS.good)
    
    gui.btn("qty_sub1000", x + 2, y + 9, 7, 1, "-1000", gui.COLORS.bad)
    gui.btn("qty_sub100", x + 10, y + 9, 6, 1, "-100", gui.COLORS.bad)
    gui.btn("qty_add100", x + 32, y + 9, 6, 1, "+100", gui.COLORS.good)
    gui.btn("qty_add1000", x + 39, y + 9, 7, 1, "+1000", gui.COLORS.good)
    
    center(x, y + 11, w, "Сумма: " .. (item.price * qty) .. " " .. CUR, gui.COLORS.warn, gui.COLORS.tileBg)
    
    local btnAction = isCartMode and "confirm_cart" or "confirm_buy"
    local btnText = isCartMode and "ДОБАВИТЬ В КОРЗИНУ" or "ПОДТВЕРДИТЬ ПОКУПКУ"
    gui.btn(btnAction, x + 2, y + 12, 24, 1, btnText, gui.COLORS.good)
    gui.btn("close_modal", x + 28, y + 12, 18, 1, "ОТМЕНА", gui.COLORS.bad)
end

function gui.drawCart(cart_items)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    local w = 60; local h = 20; local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    rect(x, y, w, h, gui.COLORS.panel); rect(x, y, w, 2, gui.COLORS.energy)
    center(x, y, w, "КОРЗИНА", gui.COLORS.text, gui.COLORS.energy)
    
    local totalCost = 0; local curY = y + 3
    if #cart_items == 0 then
        center(x, y + 8, w, "Корзина пуста", gui.COLORS.label, gui.COLORS.panel)
    else
        for i, ci in ipairs(cart_items) do
            if curY < y + h - 5 then
                local cost = ci.item.price * ci.qty; totalCost = totalCost + cost
                text(x + 2, curY, ci.item.name .. " x" .. ci.qty, gui.COLORS.text, gui.COLORS.panel)
                text(x + w - string.len(tostring(cost)) - string.len(CUR) - 9, curY, cost .. " " .. CUR, gui.COLORS.warn, gui.COLORS.panel)
                gui.btn("cart_del_"..i, x + w - 6, curY, 4, 1, "X", gui.COLORS.bad)
                curY = curY + 2
            end
        end
    end
    rect(x, y + h - 4, w, 1, gui.COLORS.tileHeader)
    
    gui.btn("close_modal", x + 2, y + h - 3, 12, 3, "НАЗАД", gui.COLORS.btn)
    text(x + 16, y + h - 2, "ИТОГО: " .. totalCost .. " " .. CUR, gui.COLORS.warn, gui.COLORS.panel)
    gui.btn("checkout", x + w - 20, y + h - 3, 18, 3, "ОПЛАТИТЬ", gui.COLORS.good)
end

function gui.drawAdmin(substate, pageItems, page, maxPage, logFilter)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    rect(1, 1, W, 3, gui.COLORS.panel); center(1, 2, W, "ПАНЕЛЬ УПРАВЛЕНИЯ МАГАЗИНОМ", gui.COLORS.energy, gui.COLORS.panel)
    
    gui.btn("adm_cat", 2, 5, 14, 3, "КАТЕГОРИИ", substate == "cat" and gui.COLORS.btnActive or gui.COLORS.btn)
    gui.btn("adm_item", 17, 5, 14, 3, "ТОВАРЫ", substate == "item" and gui.COLORS.btnActive or gui.COLORS.btn)
    gui.btn("adm_buy", 32, 5, 14, 3, "СКУПКА", substate == "buy" and gui.COLORS.btnActive or gui.COLORS.btn)
    gui.btn("adm_name", 47, 5, 18, 3, "ИМЯ МАГАЗИНА", gui.COLORS.btn)
    gui.btn("adm_logs", 66, 5, 14, 3, "ЛОГИ", substate == "logs" and gui.COLORS.btnActive or gui.COLORS.btn)
    gui.btn("close_admin", W - 16, 5, 14, 3, "ВЫЙТИ", gui.COLORS.bad)

    rect(2, 9, W - 4, H - 14, gui.COLORS.panel)
    local y = 10
    
    if pageItems then
        for _, pItem in ipairs(pageItems) do
            if y >= H - 5 then break end -- Защита: не рисуем, если уперлись в кнопки
            
            local el = pItem.item
            local id = pItem.origIdx
            
            if substate == "logs" then
                local str = tostring(el)
                local actionCol = gui.COLORS.text
                if str:match("ПОКУПКА") then actionCol = gui.COLORS.good
                elseif str:match("ПРОДАЖА") or str:match("СКУПКА") then actionCol = gui.COLORS.warn
                elseif str:match("УДАЛЕН") or str:match("ОШИБКА") then actionCol = gui.COLORS.bad end
                
                local time_part, rest = str:match("(%[%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d%]) (.*)")
                if time_part and rest then
                    text(4, y, time_part, gui.COLORS.label, gui.COLORS.panel)
                    local startX = 4 + unicode.len(time_part) + 1
                    local maxW = W - startX - 4
                    
                    -- Умный перенос строк по словам
                    local currentLine = ""
                    for word in string.gmatch(rest, "%S+") do
                        if unicode.len(currentLine) + unicode.len(word) + 1 > maxW then
                            text(startX, y, currentLine, actionCol, gui.COLORS.panel)
                            y = y + 1
                            currentLine = word
                            if y >= H - 5 then break end
                        else
                            currentLine = currentLine == "" and word or (currentLine .. " " .. word)
                        end
                    end
                    if currentLine ~= "" and y < H - 5 then
                        text(startX, y, currentLine, actionCol, gui.COLORS.panel)
                        y = y + 1
                    end
                else
                    text(4, y, unicode.sub(str, 1, W - 8), actionCol, gui.COLORS.panel)
                    y = y + 1
                end
            else
                local name = type(el) == "table" and el.name or el
                local extra = type(el) == "table" and (" (" .. el.price .. " " .. CUR .. ")") or ""
                if type(el) == "table" and el.category then extra = " ["..el.category.."]" .. extra end

                text(4, y, name .. extra, gui.COLORS.text, gui.COLORS.panel)
                gui.btn("adm_edit_"..id, W - 28, y, 12, 1, "РЕДАКТ", gui.COLORS.warn)
                gui.btn("adm_del_"..id, W - 14, y, 12, 1, "УДАЛИТЬ", gui.COLORS.bad)
                y = y + 2
            end
        end
    end
    
    local py = H - 4
    if substate == "logs" then
        local filterText = (logFilter == nil or logFilter == "") and "ВСЕ" or unicode.sub(logFilter, 1, 12)
        gui.btn("filter_logs", 2, py, 24, 3, "ФИЛЬТР: " .. filterText, gui.COLORS.energy)
        if logFilter ~= nil and logFilter ~= "" then
            gui.btn("clear_filter", 28, py, 14, 3, "СБРОСИТЬ", gui.COLORS.bad)
        end
    else
        gui.btn("adm_add", 2, py, 24, 3, "ДОБАВИТЬ ЗАПИСЬ", gui.COLORS.good)
    end
    
    if maxPage > 1 then
        local centerP = math.floor(W / 2)
        if page > 1 then gui.btn("adm_prev", centerP - 18, py, 12, 3, "<- НАЗАД", gui.COLORS.btnActive) end
        center(centerP - 4, py + 1, 8, "Стр " .. page .. " из " .. maxPage, gui.COLORS.text, gui.COLORS.bg)
        if page < maxPage then gui.btn("adm_next", centerP + 6, py, 12, 3, "ВПЕРЕД ->", gui.COLORS.btnActive) end
    end
end

function gui.drawEditorModal(data, categories)
    gui.buttons = {}
    local w = 70; local h = 20
    if data.target == "shop_name" or data.target == "edit_cat" or data.target == "log_filter" or data.target == "search" then h = 12 end
    local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    
    rect(x-1, y-1, w+2, h+2, gui.COLORS.tileHeader)
    rect(x, y, w, h, gui.COLORS.tileBg); rect(x, y, w, 2, gui.COLORS.energy)
    center(x, y, w, "РЕДАКТИРОВАНИЕ", gui.COLORS.text, gui.COLORS.energy)
    
    if data.target == "log_filter" then
        text(x+4, y+4, "Поиск по логам (ник, действие или товар):", gui.COLORS.label, gui.COLORS.tileBg)
        local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_name", x+4, y+6, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
    elseif data.target == "search" then
        text(x+4, y+4, "Поиск товаров по названию:", gui.COLORS.label, gui.COLORS.tileBg)
        local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_name", x+4, y+6, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
    elseif data.target == "shop_name" then
        text(x+4, y+4, "Новое название магазина:", gui.COLORS.label, gui.COLORS.tileBg)
        local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_name", x+4, y+6, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
    elseif data.target == "edit_cat" then
        text(x+4, y+4, "Название категории:", gui.COLORS.label, gui.COLORS.tileBg)
        local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_name", x+4, y+6, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
    else
        if data.orig_id then text(x+4, y+3, "Системное имя: " .. data.orig_id .. ":" .. (data.damage or 0), gui.COLORS.label, gui.COLORS.tileBg) end
        
        text(x+4, y+5, "Отображаемое имя (на витрине):", gui.COLORS.text, gui.COLORS.tileBg)
        local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_name", x+4, y+6, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
        
        text(x+4, y+8, "Цена за 1 шт (число):", gui.COLORS.text, gui.COLORS.tileBg)
        local bgPrice = (data.focus == "price") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_price", x+4, y+9, w-8, 1, data.price .. ((data.focus == "price") and "_" or ""), bgPrice, gui.COLORS.warn)
        
        if data.isItem then
            text(x+4, y+12, "Категория товара:", gui.COLORS.text, gui.COLORS.tileBg)
            local cx = x+4; local cy = y+13
            for _, cat in ipairs(categories) do
                if cat ~= "ВСЕ" then
                    local cw = unicode.len(cat) + 4
                    if cx + cw > x + w - 4 then cx = x+4; cy = cy + 2 end
                    local cBg = (data.cat == cat) and gui.COLORS.btnActive or gui.COLORS.btn
                    gui.btn("setcat_"..cat, cx, cy, cw, 1, cat, cBg)
                    cx = cx + cw + 1
                end
            end
        end
    end
    
    local btnText = (data.target == "log_filter" or data.target == "search") and "ИСКАТЬ" or "СОХРАНИТЬ"
    gui.btn("ed_save", x + 4, y + h - 4, math.floor(w/2) - 6, 3, btnText, gui.COLORS.good)
    gui.btn("ed_cancel", x + math.floor(w/2) + 2, y + h - 4, math.floor(w/2) - 6, 3, "ОТМЕНА", gui.COLORS.bad)
end

function gui.checkClick(x, y)
    for id, b in pairs(gui.buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return id end
    end
    return nil
end

return gui