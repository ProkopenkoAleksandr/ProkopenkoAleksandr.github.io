local config = {}

-- ССЫЛКА НА БАЗУ ДАННЫХ (без слеша / на конце)
-- В ГИТХАБЕ ОСТАВЛЯЕМ ПУСТЫМ! Заполняем только на компьютере в игре.
config.firebase_url = ""

-- Секретный ключ базы данных Firebase
-- В ГИТХАБЕ ОСТАВЛЯЕМ ПУСТЫМ! Заполняем только на компьютере в игре.
config.db_secret = ""

-- Название валюты
config.currency_name = "ЭМ"

-- Часовой пояс (смещение от UTC в часах). Например: 2 (Киев), 3 (Мск)
config.timezone = 2

-- РУБИЛЬНИК БАЗЫ ДАННЫХ
-- true = работает с Firebase и веб-панелью
-- false = работает полностью оффлайн (только жесткий диск)
config.use_database = true

-- Администраторы (кому доступна скрытая панель)
config.admins = {
    ["DesOope"] = true,
    ["NickName"] = true
}

-- === НАСТРОЙКИ КАЗИНО ===
config.main_db_path = "casino" -- Главный путь для данных казино в Firebase

-- Цвета для редкости предметов в рулетке
config.rarity_colors = {
    super_rare = 0xFFFF55, -- Желтый (< 5%)
    rare = 0xAA00AA,       -- Фиолетовый (< 20%)
    uncommon = 0x5555FF,    -- Синий (< 60%)
    common = 0x55FF55,      -- Зеленый (< 80%)
    trash = 0xAAAAAA        -- Серый (>= 80%)
}

return config
