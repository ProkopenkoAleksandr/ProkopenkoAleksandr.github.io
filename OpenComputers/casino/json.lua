-- /home/casino_json.lua
local json = {}

local function escape_str(s)
  return s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
end

function json.encode(v)
  local vtype = type(v)
  if vtype == "string" then
    return '"' .. escape_str(v) .. '"'
  elseif vtype == "number" or vtype == "boolean" then
    return tostring(v)
  elseif vtype == "table" then
    local is_array = true
    local max = 0
    for k, _ in pairs(v) do
      if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
        is_array = false
        break
      end
      if k > max then max = k end
    end
    
    if is_array then
      local parts = {}
      for i = 1, max do
        parts[i] = json.encode(v[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, val in pairs(v) do
        table.insert(parts, '"' .. escape_str(tostring(k)) .. '":' .. json.encode(val))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  else
    return "null"
  end
end

local function create_set(...)
  local res = {}
  for i = 1, select("#", ...) do res[select(i, ...)] = true end
  return res
end

local space_chars = create_set(" ", "\t", "\r", "\n")
local delim_chars = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_char_map = { ["\\"] = "\\", ["\""] = "\"", ["b"] = "\b", ["f"] = "\f", ["n"] = "\n", ["r"] = "\r", ["t"] = "\t" }

local function parse(str, pos)
  while space_chars[str:sub(pos, pos)] do pos = pos + 1 end
  local c = str:sub(pos, pos)
  
  if c == '"' then
    local res = ""
    local i = pos + 1
    while i <= #str do
      local char = str:sub(i, i)
      if char == '"' then return res, i + 1 end
      if char == "\\" then
        local next_char = str:sub(i + 1, i + 1)
        res = res .. (escape_char_map[next_char] or next_char)
        i = i + 2
      else
        res = res .. char
        i = i + 1
      end
    end
    error("Незакрытая строка на позиции " .. pos)
  elseif c == "[" then
    local res = {}
    pos = pos + 1
    while space_chars[str:sub(pos, pos)] do pos = pos + 1 end
    if str:sub(pos, pos) == "]" then return res, pos + 1 end
    while true do
      local val
      val, pos = parse(str, pos)
      table.insert(res, val)
      while space_chars[str:sub(pos, pos)] do pos = pos + 1 end
      local next_char = str:sub(pos, pos)
      if next_char == "]" then return res, pos + 1 end
      if next_char ~= "," then error("Ожидалась ',' или ']' на позиции " .. pos) end
      pos = pos + 1
    end
  elseif c == "{" then
    local res = {}
    pos = pos + 1
    while space_chars[str:sub(pos, pos)] do pos = pos + 1 end
    if str:sub(pos, pos) == "}" then return res, pos + 1 end
    while true do
      local key
      key, pos = parse(str, pos)
      if type(key) ~= "string" then error("Ожидался строковый ключ на позиции " .. pos) end
      while space_chars[str:sub(pos, pos)] do pos = pos + 1 end
      if str:sub(pos, pos) ~= ":" then error("Ожидалось ':' на позиции " .. pos) end
      pos = pos + 1
      local val
      val, pos = parse(str, pos)
      res[key] = val
      while space_chars[str:sub(pos, pos)] do pos = pos + 1 end
      local next_char = str:sub(pos, pos)
      if next_char == "}" then return res, pos + 1 end
      if next_char ~= "," then error("Ожидалась ',' или '}' на позиции " .. pos) end
      pos = pos + 1
    end
  else
    local start_pos = pos
    while pos <= #str and not delim_chars[str:sub(pos, pos)] do pos = pos + 1 end
    local val_str = str:sub(start_pos, pos - 1)
    if val_str == "true" then return true, pos
    elseif val_str == "false" then return false, pos
    elseif val_str == "null" then return nil, pos
    else
      local num = tonumber(val_str)
      if num then return num, pos else error("Неверное значение '" .. val_str .. "' на позиции " .. start_pos) end
    end
  end
end

function json.decode(str)
  if type(str) ~= "string" or str == "" then return nil end
  local ok, res = pcall(parse, str, 1)
  if ok then return res else return nil, res end
end

return json
