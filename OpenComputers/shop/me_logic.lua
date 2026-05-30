-- /lua/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}
me.t = nil      

me.config = { chest_side = sides.up, me_side = sides.down }

function me.init()
    if component.isAvailable("transposer") then me.t = component.transposer end
    if not me.t then return false, "Транспоузер скупки не найден!" end
    if not component.isAvailable("me_interface") then return false, "МЭ Интерфейс не найден!" end
    return true, "МЭ компоненты готовы."
end

function me.updateStock(shop_items)
    local lookup = {}
    for addr in component.list("me_interface") do
        local ok, net_items = pcall(component.proxy(addr).getItemsInNetwork)
        if ok and net_items then
            for _, n_item in ipairs(net_items) do
                local dmg = math.floor(n_item.damage or 0)
                local key = (n_item.name or "unknown") .. ":" .. dmg
                lookup[key] = (lookup[key] or 0) + n_item.size
            end
            break 
        end
    end

    for _, s_item in ipairs(shop_items) do
        local dmg = math.floor(s_item.damage or 0)
        local key = (s_item.id or "unknown") .. ":" .. dmg
        s_item.stock = lookup[key] or 0
    end
end

function me.sellAll(buyback_list)
    if not me.t then return false, "Транспоузер не подключен!", 0 end
    local inv_size = me.t.getInventorySize(me.config.chest_side)
    if not inv_size or inv_size == 0 then return false, "Сундук не найден!", 0 end

    local total_earned = 0; local sold_stats = {}; local err_msg = nil

    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then
            local matched_item = nil
            for _, b_item in ipairs(buyback_list) do
                if stack.name == b_item.id and math.floor(stack.damage or 0) == math.floor(b_item.damage or 0) then
                    matched_item = b_item; break
                end
            end

            if matched_item then
                local moved, reason = me.t.transferItem(me.config.chest_side, me.config.me_side, stack.size, slot)
                local actual_moved = 0
                if type(moved) == "number" then actual_moved = moved
                elseif type(moved) == "boolean" and moved == true then actual_moved = stack.size
                elseif type(moved) == "boolean" and moved == false then err_msg = reason end

                if actual_moved > 0 then
                    total_earned = total_earned + (actual_moved * matched_item.price)
                    sold_stats[matched_item.name] = (sold_stats[matched_item.name] or 0) + actual_moved
                end
            end
        end
    end

    if total_earned > 0 then
        local receipt = ""
        for name, qty in pairs(sold_stats) do receipt = receipt .. name .. "(x" .. qty .. ") " end
        return true, "Сдано: " .. receipt, total_earned
    else return false, "Не продано. Причина: " .. tostring(err_msg or "Нет подходящих предметов"), 0 end
end

function me.peekInput()
    if not me.t then return nil, nil, "Транспоузер не подключен!" end
    local inv_size = me.t.getInventorySize(me.config.chest_side)
    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then return stack, slot end
    end
    return nil, nil, "Положите предмет в сундук!"
end

function me.storeToDB(chest_slot, db_slot) return true end

-- === ВЫДАЧА С ЦИКЛОМ (Обходит лимит в 64 штуки) ===
function me.buyItem(item, qty)
    local perfect_fingerprint = {
        id = item.id,
        dmg = math.floor(item.damage or 0)
    }
    
    local total_moved = 0
    local last_err = "Сундук выдачи не найден ни над одним интерфейсом!"

    for addr in component.list("me_interface") do
        local me_proxy = component.proxy(addr)
        for side = 0, 5 do
            -- Первая попытка: находим правильную сторону
            local ok, result = pcall(me_proxy.exportItem, perfect_fingerprint, side, qty)
            local moved_now = 0
            
            if ok and type(result) == "table" and result.size then moved_now = result.size
            elseif ok and type(result) == "number" then moved_now = result end
            
            if moved_now > 0 then
                total_moved = total_moved + moved_now
                
                -- Сторона найдена! Начинаем цикл-насос для остатка
                local attempts = 0
                while total_moved < qty and attempts < 150 do
                    local batch = qty - total_moved
                    local ok2, res2 = pcall(me_proxy.exportItem, perfect_fingerprint, side, batch)
                    local m2 = 0
                    
                    if ok2 and type(res2) == "table" and res2.size then m2 = res2.size
                    elseif ok2 and type(res2) == "number" then m2 = res2 end
                    
                    if m2 > 0 then
                        total_moved = total_moved + m2
                    else
                        break -- Остановка: сундук полон или ресурсы в МЭ кончились
                    end
                    attempts = attempts + 1
                end
                
                return true, "Успешно", total_moved
            elseif not ok then
                last_err = tostring(result)
            end
        end
        if total_moved > 0 then break end
    end
    
    if total_moved > 0 then 
        return true, "Частично", total_moved
    else 
        return false, "Ошибка мода: " .. last_err, 0 
    end
end

return me
