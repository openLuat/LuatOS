-- app_util.lua  通用工具（纯函数，无副作用）

local M = {}

-- 数值夹取
function M.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- 补零两位
function M.pad2(n)
  n = math.floor(n)
  if n < 10 then return "0" .. n end
  return tostring(n)
end

-- 四舍五入取整字符串
function M.fmt(n)
  return tostring(math.floor(n + 0.5))
end

-- 一位小数字符串（不依赖 string.format("%.1f")，精简固件里格式化支持不齐全）
function M.one_dp(v)
  local n = math.floor((v or 0) * 10 + 0.5)
  return tostring(math.floor(n / 10)) .. "." .. tostring(n % 10)
end

-- 秒 → "MM:SS"（超过 1 小时给 "H:MM"）
function M.clock(sec)
  sec = math.floor(sec or 0)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then return tostring(h) .. ":" .. M.pad2(m) end
  return M.pad2(m) .. ":" .. M.pad2(s)
end

-- 随机 [0,1)
function M.rnd()
  return math.random(0, 999999) / 1000000
end

-- 字母加空格（"BATTERY" → "B A T T E R Y"），用于分区标题的字距感
-- 只能用于 ASCII：hzfont 没有字距设置，靠插入空格近似
function M.sp(text)
  local out = {}
  for i = 1, #text do
    if i > 1 then out[#out + 1] = " " end
    out[#out + 1] = text:sub(i, i)
  end
  return table.concat(out)
end

return M
