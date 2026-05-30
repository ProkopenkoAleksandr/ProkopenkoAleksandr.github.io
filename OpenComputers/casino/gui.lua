-- /home/casino_gui.lua
local component = require("component")
local term = require("term")
local unicode = require("unicode")
local config = require("casino_config")
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

local function rect(x, y, w, h, col) 
    local dx, dy = math.max(1, x), math.max(1, y)
    local dw, dh = w - (dx - x), h - (dy - y)
    if dx + dw - 1 > W then dw = W - dx + 1 end
    if dy + dh - 1 > H then dh = H - dy + 1 end
    if dw > 0 and dh > 0 then
        gpu.setBackground(col); gpu.fill(dx, dy, dw, dh, " ") 
    end
end

local function text(x, y, str, fg, bg) 
    if y < 1 or y > H or x > W then return end
    if bg then gpu.setBackground(bg) end; gpu.setForeground(fg); gpu.set(x, y, str) 
end

local function center(x, y, w, str, fg, bg) 
    if bg then rect(x, y, w, 1, bg) end
    local px = x + math.floor((w - unicode.len(str))/2)
    if fg then gpu.setForeground(fg) end; gpu.set(px, y, str) 
end

function gui.btn(id, x, y, w, h, str, bg, fg) 
    local actualFg = fg or gui.COLORS.text
    if bg == gui.COLORS.good then actualFg = gui.COLORS.bg end
    rect(x, y, w, h, bg); center(x, y + math.floor(h/2), w, str, actualFg, bg)
    gui.buttons[id] = {x=x, y=y, w=w, h=h} 
end

-- === НОВОЕ: БЕГУЩАЯ СТРОКА ===
function gui.drawMarquee(wins_str, offset)
    local w = rightColX - 1
    if w <= 0 then return end
    
    rect(1, 5, w, 3, gui.COLORS.panel)
    rect(1, 5, w, 1, gui.COLORS.tileHeader)
    rect(1, 7, w, 1, gui.COLORS.tileHeader)
    
    if not wins_str or wins_str == "" then
        center(1, 6, w, "НЕТ ИНФОРМАЦИИ О ВЫИГРЫШАХ", gui.COLORS.label, gui.COLORS.panel)
        return
    end
    
    local len = unicode.len(wins_str)
    local display_str = ""
    
    if len <= w then
        display_str = wins_str .. string.rep(" ", w - len)
    else
        local safe_offset = (offset % len) + 1
        display_str = unicode.sub(wins_str, safe_offset, safe_offset + w - 1)
        if unicode.len(display_str) < w then
            display_str = display_str .. " " .. unicode.sub(wins_str, 1, w - unicode.len(display_str) - 1)
        end
    end
    
    gpu.setBackground(gui.COLORS.panel)
    gpu.setForeground(gui.COLORS.warn)
    gpu.set(1, 6, display_str)
end

function gui.drawStatic(user, timer, topPlayers, casinoName, depositPrices)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    rect(1, 1, rightColX - 1, 3, gui.COLORS.panel)
    center(1, 2, rightColX - 1, casinoName or "КАЗИНО", gui.COLORS.energy, gui.COLORS.panel)

    rect(rightColX, 1, rightColW, H, gui.COLORS.panel)
    
    local rY = 2
    if user then
        gui.btn("logout", rightColX + 2, rY, rightColW - 4, 3, "ВЫХОД", gui.COLORS.bad)
        rY = rY + 4
        center(rightColX, rY, rightColW, user.name, gui.COLORS.good, gui.COLORS.panel); rY = rY + 1
        center(rightColX, rY, rightColW, user.balance .. " " .. CUR, gui.COLORS.warn, gui.COLORS.panel); rY = rY + 2
        if timer then center(rightColX, rY, rightColW, "Выход через: " .. timer .. "с", gui.COLORS.label, gui.COLORS.panel) end
        rY = rY + 2
        gui.btn("deposit", rightColX + 2, rY, rightColW - 4, 3, "ПОПОЛНИТЬ СЧЕТ", gui.COLORS.good)
        rY = rY + 4
        if user.isAdmin then gui.btn("admin_panel", rightColX + 2, rY, rightColW - 4, 1, "АДМИН ПАНЕЛЬ", gui.COLORS.energy); rY = rY + 2 end
    else
        gui.btn("login", rightColX + 2, rY, rightColW - 4, 3, "АВТОРИЗАЦИЯ", gui.COLORS.good)
        rY = rY + 4
        center(rightColX, rY, rightColW, "Войдите для игры", gui.COLORS.label, gui.COLORS.panel)
        rY = rY + 3
    end

    local dep_texts = {}
    for k, v in pairs(depositPrices or {}) do
        local name = type(v) == "table" and v.name or k
        local price = type(v) == "table" and v.price or v
        table.insert(dep_texts, name .. " - " .. price .. " " .. CUR)
    end
    
    if #dep_texts > 0 then
        rect(rightColX, rY, rightColW, 1, gui.COLORS.tileHeader)
        center(rightColX, rY, rightColW, "СКУПКА ПРЕДМЕТОВ:", gui.COLORS.energy, gui.COLORS.tileHeader)
        rY = rY + 2
        for i, txt in ipairs(dep_texts) do
            -- Оставляем больше места под Топ-15
            if rY > H - 18 then break end 
            if unicode.len(txt) > rightColW - 4 then
                txt = unicode.sub(txt, 1, rightColW - 7) .. "..."
            end
            text(rightColX + 2, rY, txt, gui.COLORS.text, gui.COLORS.panel)
            rY = rY + 1
        end
        rY = rY + 1
    end

    -- === ОБНОВЛЕННЫЙ ТОП 15 ===
    rect(rightColX, rY, rightColW, 1, gui.COLORS.tileHeader)
    center(rightColX, rY, rightColW, "ТОП 15 ИГРОКОВ:", gui.COLORS.warn, gui.COLORS.tileHeader)
    rY = rY + 2
    if topPlayers and #topPlayers > 0 then
        for i, t in ipairs(topPlayers) do
            if rY > H - 1 then break end -- Защита от вылезания за экран
            
            -- Обрезаем слишком длинные ники
            local safeName = unicode.sub(t.name, 1, rightColW - 13)
            text(rightColX + 2, rY, i .. ". " .. safeName, gui.COLORS.text, gui.COLORS.panel)
            
            local valStr = tostring(t.spent)
            if t.spent >= 1000000 then valStr = string.format("%.1fM", t.spent/1000000)
            elseif t.spent >= 1000 then valStr = string.format("%.1fk", t.spent/1000) end
            
            local spentStr = valStr .. " " .. CUR
            text(rightColX + rightColW - unicode.len(spentStr) - 2, rY, spentStr, gui.COLORS.warn, gui.COLORS.panel)
            rY = rY + 1
        end
    else
        center(rightColX, rY, rightColW, "Нет данных", gui.COLORS.label, gui.COLORS.panel); rY = rY + 1
    end
end

function gui.drawCases(pageItems, page, maxPage)
    -- Опускаем кейсы ниже, чтобы влезла бегущая строка (с 5 на 8)
    rect(1, 8, rightColX - 1, H - 7, gui.COLORS.bg)
    local margin = 2; local cols = 3;
    local tileW = math.floor((rightColX - (cols + 1) * margin) / cols); local tileH = 8
    local row, col = 0, 0
    
    for _, pItem in ipairs(pageItems) do
        local case = pItem.item
        local id = pItem.origIdx
        -- Координата Y теперь начинается с 8
        local x = margin + col * (tileW + margin); local y = 8 + row * (tileH + 1)
        
        rect(x, y, tileW, tileH, gui.COLORS.tileBg)
        center(x, y, tileW, case.name, gui.COLORS.text, gui.COLORS.tileHeader)
        center(x, y + 2, tileW, "Цена:", gui.COLORS.label, gui.COLORS.tileBg)
        center(x, y + 3, tileW, case.price .. " " .. CUR, gui.COLORS.warn, gui.COLORS.tileBg)
        
        gui.btn("view_case_"..id, x + 2, y + 5, tileW - 4, 1, "ОСМОТРЕТЬ", gui.COLORS.btn)
        gui.btn("open_case_"..id, x + 2, y + 7, tileW - 4, 1, "ОТКРЫТЬ", gui.COLORS.good)
        
        col = col + 1; if col >= cols then col = 0; row = row + 1 end
    end

    local py = H - 3
    if page > 1 then gui.btn("page_prev", 2, py, 14, 3, "<- НАЗАД", gui.COLORS.btnActive) end
    center(1, py + 1, rightColX - 1, "Страница " .. page .. " из " .. maxPage, gui.COLORS.text, gui.COLORS.bg)
    if page < maxPage then gui.btn("page_next", rightColX - 16, py, 14, 3, "ВПЕРЕД ->", gui.COLORS.btnActive) end
end

-- Остальные функции без изменений (drawCaseView, drawTick, drawNotification, drawAdmin, drawEditorModal, drawCaseEditor, drawItemEditor, drawRoulette, checkClick)
-- Чтобы не занимать место, я не дублирую их тут. Просто ВСТАВЬ их ниже, они не менялись!

function gui.drawCaseView(case)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    local w = W - 4; local h = H - 6
    local x = 3; local y = 4

    rect(x, y, w, h, gui.COLORS.panel)
    rect(x, y, w, 2, gui.COLORS.energy)
    center(x, y, w, "СОДЕРЖИМОЕ КЕЙСА: " .. case.name, gui.COLORS.text, gui.COLORS.energy)

    if case.items and #case.items > 0 then
        local max_rows = h - 6
        local use_two_cols = #case.items > max_rows
        
        local col1_x = x
        local col1_w = use_two_cols and math.floor(w / 2) or w
        local col2_x = x + col1_w
        local col2_w = w - col1_w

        local current_row = 0
        local current_col = 1

        for i, item in ipairs(case.items) do
            local chanceColor = gui.COLORS.text
            local qtyStr = (item.qty and item.qty > 1) and (" (x" .. item.qty .. ")") or ""
            local baseName = item.name .. qtyStr
            local displayName = baseName
            
            if item.chance < 5 then 
                chanceColor = config.rarity_colors.super_rare
                displayName = "[ *** " .. unicode.upper(baseName) .. " *** ]"
            elseif item.chance < 20 then 
                chanceColor = config.rarity_colors.rare
                displayName = "-= * " .. unicode.upper(baseName) .. " * =-"
            elseif item.chance < 60 then 
                chanceColor = config.rarity_colors.uncommon
                displayName = "~ " .. baseName .. " ~"
            else 
                chanceColor = config.rarity_colors.common
            end
            
            local draw_y = y + 3 + current_row
            if draw_y > y + h - 4 then break end 
            
            local draw_x = current_col == 1 and col1_x or col2_x
            local draw_w = current_col == 1 and col1_w or col2_w
            
            center(draw_x, draw_y, draw_w, displayName, chanceColor, gui.COLORS.panel)
            
            current_row = current_row + 1
            if current_row >= max_rows and use_two_cols and current_col == 1 then
                current_col = 2
                current_row = 0
            end
        end
    else
        center(x, y + 5, w, "В этом кейсе пока нет предметов", gui.COLORS.label, gui.COLORS.panel)
    end
    
    gui.btn("close_view", x + math.floor(w/2) - 10, y + h - 3, 20, 1, "НАЗАД", gui.COLORS.btnActive)
end

function gui.drawTick(user, timer)
    if user and timer then center(rightColX, 9, rightColW, "Выход через: " .. timer .. "с   ", gui.COLORS.label, gui.COLORS.panel) end
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

function gui.drawAdmin(substate, pageItems, page, maxPage, logFilter)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    rect(1, 1, W, 3, gui.COLORS.panel); center(1, 2, W, "ПАНЕЛЬ УПРАВЛЕНИЯ КАЗИНО", gui.COLORS.energy, gui.COLORS.panel)
    
    gui.btn("adm_cases", 2, 5, 14, 3, "КЕЙСЫ", substate == "cases" and gui.COLORS.btnActive or gui.COLORS.btn)
    gui.btn("adm_name", 17, 5, 18, 3, "ИМЯ КАЗИНО", gui.COLORS.btn)
    gui.btn("adm_logs", 36, 5, 14, 3, "ЛОГИ", substate == "logs" and gui.COLORS.btnActive or gui.COLORS.btn)
    gui.btn("adm_deposit", 51, 5, 14, 3, "СКУПКА", substate == "deposit" and gui.COLORS.btnActive or gui.COLORS.btn)
    
    gui.btn("close_admin", W - 16, 5, 14, 3, "ВЫЙТИ", gui.COLORS.bad)

    rect(2, 9, W - 4, H - 14, gui.COLORS.panel)
    local y = 10
    
    if pageItems then
        for _, pItem in ipairs(pageItems) do
            if y >= H - 5 then break end 
            
            local el = pItem.item
            local id = pItem.origIdx
            
            if substate == "logs" then
                local str = tostring(el)
                local actionCol = gui.COLORS.text
                if str:match("ВЫИГРЫШ") then actionCol = gui.COLORS.good
                elseif str:match("ПОПОЛНЕНИЕ") then actionCol = gui.COLORS.warn
                elseif str:match("УДАЛЕН") or str:match("ОШИБКА") then actionCol = gui.COLORS.bad end
                
                local time_part, rest = str:match("(%[%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d%]) (.*)")
                if time_part and rest then
                    text(4, y, time_part, gui.COLORS.label, gui.COLORS.panel)
                    local startX = 4 + unicode.len(time_part) + 1
                    local maxW = W - startX - 4
                    
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
            elseif substate == "deposit" then
                text(4, y, el.name .. " (" .. el.price .. " " .. CUR .. ")", gui.COLORS.text, gui.COLORS.panel)
                gui.btn("adm_edit_dep_"..id, W - 28, y, 12, 1, "РЕДАКТ", gui.COLORS.warn)
                gui.btn("adm_del_dep_"..id, W - 14, y, 12, 1, "УДАЛИТЬ", gui.COLORS.bad)
                y = y + 2
            else
                local name = type(el) == "table" and el.name or el
                local extra = type(el) == "table" and (" (" .. el.price .. " " .. CUR .. ")") or ""

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
    elseif substate == "deposit" then
        gui.btn("adm_add_dep", 2, py, 24, 3, "ДОБАВИТЬ ПРЕДМЕТ", gui.COLORS.good)
    else
        gui.btn("adm_add", 2, py, 24, 3, "ДОБАВИТЬ КЕЙС", gui.COLORS.good)
    end
    
    if maxPage > 1 then
        local centerP = math.floor(W / 2)
        if page > 1 then gui.btn("adm_prev", centerP - 18, py, 12, 3, "<- НАЗАД", gui.COLORS.btnActive) end
        center(centerP - 4, py + 1, 8, "Стр " .. page .. " из " .. maxPage, gui.COLORS.text, gui.COLORS.bg)
        if page < maxPage then gui.btn("adm_next", centerP + 6, py, 12, 3, "ВПЕРЕД ->", gui.COLORS.btnActive) end
    end
end

function gui.drawEditorModal(data)
    gui.buttons = {}
    local w = 70; local h = 15 
    local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    
    rect(x-1, y-1, w+2, h+2, gui.COLORS.tileHeader)
    rect(x, y, w, h, gui.COLORS.tileBg); rect(x, y, w, 2, gui.COLORS.energy)
    center(x, y, w, "РЕДАКТОР КЕЙСА", gui.COLORS.text, gui.COLORS.energy)
    
    if data.target == "log_filter" then
        text(x+4, y+4, "Поиск по логам (ник, действие):", gui.COLORS.label, gui.COLORS.tileBg)
        local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_name", x+4, y+6, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
    elseif data.target == "casino_name" then
        text(x+4, y+4, "Новое название казино:", gui.COLORS.label, gui.COLORS.tileBg)
        local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_name", x+4, y+6, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
    elseif data.target == "edit_case" or data.target == "add_case" then
        text(x+4, y+4, "Название кейса:", gui.COLORS.label, gui.COLORS.tileBg)
        local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_name", x+4, y+5, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
        
        text(x+4, y+7, "Цена (число):", gui.COLORS.label, gui.COLORS.tileBg)
        local bgPrice = (data.focus == "price") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_price", x+4, y+8, w-8, 1, data.price .. ((data.focus == "price") and "_" or ""), bgPrice, gui.COLORS.warn)
    end
    
    local btnText = (data.target == "log_filter") and "ИСКАТЬ" or "СОХРАНИТЬ"
    gui.btn("ed_save", x + 4, y + h - 4, math.floor(w/2) - 6, 3, btnText, gui.COLORS.good)
    gui.btn("ed_cancel", x + math.floor(w/2) + 2, y + h - 4, math.floor(w/2) - 6, 3, "ОТМЕНА", gui.COLORS.bad)
end

function gui.drawCaseEditor(case, items)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    local w = W - 4; local h = H - 6
    local x = 3; local y = 4

    rect(x, y, w, h, gui.COLORS.panel)
    rect(x, y, w, 2, gui.COLORS.energy)
    center(x, y, w, "РЕДАКТОР СОДЕРЖИМОГО: " .. case.name, gui.COLORS.text, gui.COLORS.energy)

    local currentY = y + 3
    if #items > 0 then
        for i, item in ipairs(items) do
            if currentY > y + h - 5 then break end
            local chanceColor = gui.COLORS.text
            if item.chance < 5 then chanceColor = config.rarity_colors.super_rare
            elseif item.chance < 20 then chanceColor = config.rarity_colors.rare
            elseif item.chance < 60 then chanceColor = config.rarity_colors.uncommon
            end
            
            local qtyStr = (item.qty and item.qty > 1) and (" (x" .. item.qty .. ")") or ""
            text(x + 2, currentY, item.name .. qtyStr, gui.COLORS.text, gui.COLORS.panel)
            text(x + 45, currentY, "Цена: " .. item.price, gui.COLORS.warn, gui.COLORS.panel)
            text(x + 60, currentY, "Шанс: " .. item.chance .. "%", chanceColor, gui.COLORS.panel)
            
            gui.btn("case_edit_item_"..i, x + w - 26, currentY, 12, 1, "ИЗМЕНИТЬ", gui.COLORS.warn)
            gui.btn("case_del_item_"..i, x + w - 12, currentY, 10, 1, "X", gui.COLORS.bad)
            currentY = currentY + 2
        end
    else
        center(x, y + 5, w, "В этом кейсе пока нет предметов", gui.COLORS.label, gui.COLORS.panel)
    end
    
    gui.btn("case_add_item", x + 2, y + h - 3, 20, 1, "ДОБАВИТЬ ПРЕДМЕТ", gui.COLORS.good)
    gui.btn("back_to_admin", x + w - 22, y + h - 3, 20, 1, "НАЗАД", gui.COLORS.btn)
end

function gui.drawItemEditor(data, isDeposit)
    gui.buttons = {}
    local w = 70; local h = isDeposit and 14 or 21 
    local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    
    rect(x-1, y-1, w+2, h+2, gui.COLORS.tileHeader)
    rect(x, y, w, h, gui.COLORS.tileBg); rect(x, y, w, 2, gui.COLORS.energy)
    center(x, y, w, data.is_new and "ДОБАВЛЕНИЕ ПРЕДМЕТА" or "РЕДАКТИРОВАНИЕ ПРЕДМЕТА", gui.COLORS.text, gui.COLORS.energy)

    text(x+4, y+3, "Системное имя: " .. data.orig_id .. ":" .. (data.damage or 0), gui.COLORS.label, gui.COLORS.tileBg)

    text(x+4, y+5, isDeposit and "Имя (отображается только здесь):" or "Отображаемое имя (можно изменить):", gui.COLORS.text, gui.COLORS.tileBg)
    local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
    gui.btn("focus_name", x+4, y+6, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
    
    text(x+4, y+8, isDeposit and "Цена скупки за 1 штуку:" or "Цена (для симулятора и аналитики):", gui.COLORS.text, gui.COLORS.tileBg)
    local bgPrice = (data.focus == "price") and gui.COLORS.inputFocus or gui.COLORS.inputBg
    gui.btn("focus_price", x+4, y+9, w-8, 1, data.price .. ((data.focus == "price") and "_" or ""), bgPrice, gui.COLORS.warn)

    if not isDeposit then
        text(x+4, y+11, "Шанс выпадения, % (число, можно дробное):", gui.COLORS.text, gui.COLORS.tileBg)
        local bgChance = (data.focus == "chance") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_chance", x+4, y+12, w-8, 1, data.chance .. ((data.focus == "chance") and "_" or ""), bgChance, gui.COLORS.good)

        text(x+4, y+14, "Количество предметов (шт):", gui.COLORS.text, gui.COLORS.tileBg)
        local bgQty = (data.focus == "qty") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_qty", x+4, y+15, w-8, 1, data.qty .. ((data.focus == "qty") and "_" or ""), bgQty, gui.COLORS.energy)
    end

    gui.btn("item_ed_save", x + 4, y + h - 4, math.floor(w/2) - 6, 3, "СОХРАНИТЬ", gui.COLORS.good)
    gui.btn("item_ed_cancel", x + math.floor(w/2) + 2, y + h - 4, math.floor(w/2) - 6, 3, "ОТМЕНА", gui.COLORS.bad)
end

function gui.drawRoulette(strip, strip_pos)
    gui.buttons = {} 
    local w, h = gpu.getResolution()

    local base_w, base_h = 20, 7
    local center_w, center_h = 28, 11
    local step = 24
    local pointer_x = math.floor(w / 2)
    
    local track_y = math.floor((h - center_h) / 2) - 2
    local track_h = center_h + 4
    
    rect(1, track_y, w, track_h, gui.COLORS.panel)
    rect(1, track_y, w, 1, gui.COLORS.energy) 
    rect(1, track_y + track_h - 1, w, 1, gui.COLORS.energy) 
    
    local render_list = {}
    for i, item in ipairs(strip) do
        local offset = i - strip_pos
        if math.abs(offset) < (w / step) / 2 + 1.5 then
            table.insert(render_list, {item = item, offset = offset})
        end
    end
    
    table.sort(render_list, function(a, b) return math.abs(a.offset) > math.abs(b.offset) end)

    for _, ri in ipairs(render_list) do
        local item = ri.item
        local offset = ri.offset
        local dist = math.abs(offset)
        
        local item_center_x = math.floor(pointer_x + offset * step)
        
        local scale = 0
        if dist < 1.0 then scale = 1 - dist end
        
        local cur_w = math.floor(base_w + (center_w - base_w) * scale)
        local cur_h = math.floor(base_h + (center_h - base_h) * scale)
        if cur_w % 2 ~= 0 then cur_w = cur_w + 1 end
        if cur_h % 2 == 0 then cur_h = cur_h + 1 end
        
        local item_start_x = item_center_x - math.floor(cur_w / 2)
        local item_y = math.floor((h - cur_h) / 2)

        local rarity_color = gui.COLORS.label
        local rarity_text = "ОБЫЧНЫЙ"
        
        if item.chance < 5 then rarity_color = config.rarity_colors.super_rare; rarity_text = "***СУПЕР***"
        elseif item.chance < 20 then rarity_color = config.rarity_colors.rare; rarity_text = "**РЕДКИЙ**"
        elseif item.chance < 60 then rarity_color = config.rarity_colors.uncommon; rarity_text = "*НЕОБЫЧНЫЙ*"
        elseif item.chance < 80 then rarity_color = config.rarity_colors.common; rarity_text = "ОБЫЧНЫЙ"
        else rarity_color = config.rarity_colors.trash; rarity_text = "ШИРПОТРЕБ" end

        rect(item_start_x, item_y, cur_w, cur_h, gui.COLORS.bg)
        
        if dist < 0.3 then
            rect(item_start_x, item_y, cur_w, cur_h, rarity_color)
            rect(item_start_x + 1, item_y + 1, cur_w - 2, cur_h - 2, gui.COLORS.tileBg)
            center(item_start_x, item_y + 1, cur_w, rarity_text, rarity_color, gui.COLORS.tileBg)
        else
            rect(item_start_x, item_y, cur_w, 2, rarity_color)
            rect(item_start_x, item_y + 2, cur_w, cur_h - 2, gui.COLORS.tileBg)
            center(item_start_x, item_y + 1, cur_w, rarity_text, gui.COLORS.tileBg, rarity_color)
        end

        local itemNameWithQty = item.name .. ((item.qty and item.qty > 1) and (" x" .. item.qty) or "")

        local lines = {}
        local curr = ""
        for word in string.gmatch(itemNameWithQty, "%S+") do
            if unicode.len(curr) + unicode.len(word) + 1 > cur_w - 4 then
                if curr ~= "" then table.insert(lines, curr) end
                curr = word
            else
                curr = curr == "" and word or (curr .. " " .. word)
            end
        end
        if curr ~= "" then table.insert(lines, curr) end
        
        local text_y = item_y + 3
        for _, line in ipairs(lines) do
            if text_y < item_y + cur_h - 2 then
                center(item_start_x, text_y, cur_w, line, gui.COLORS.text, gui.COLORS.tileBg)
                text_y = text_y + 1
            end
        end

        local price_str = tostring(item.price) .. " " .. CUR
        center(item_start_x, item_y + cur_h - 2, cur_w, price_str, gui.COLORS.warn, gui.COLORS.tileBg)
    end
    
    gpu.setBackground(gui.COLORS.panel)
    gpu.setForeground(gui.COLORS.warn)
    center(pointer_x - 1, track_y, 3, "▼", gui.COLORS.good, gui.COLORS.panel)
    center(pointer_x - 1, track_y + track_h - 1, 3, "▲", gui.COLORS.good, gui.COLORS.panel)
end

function gui.checkClick(x, y)
    for id, b in pairs(gui.buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return id end
    end
    return nil
end

return gui
