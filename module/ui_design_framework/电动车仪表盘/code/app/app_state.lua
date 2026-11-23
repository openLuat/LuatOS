-- app_state.lua  持久化业务状态（主题 / 驾驶模式） + 运行时共享状态

local M = {}

local KEY = "evdash"     -- fskv 命名空间
M.theme = "dark"         -- "dark" / "light"
M.mode  = 2              -- 1 ECO / 2 NORMAL / 3 SPORT

-- 初始化：从 fskv 恢复主题与模式
function M.init()
  if fskv then
    local t = fskv.get(KEY, "theme")
    if t == "light" then M.theme = "light" elseif t == "dark" then M.theme = "dark" end
    local m = fskv.get(KEY, "mode")
    if type(m) == "number" and m >= 1 and m <= 3 then M.mode = m end
  end
end

-- 切换主题并持久化
function M.set_theme(name)
  M.theme = name
  if fskv then fskv.set(KEY, "theme", name) end
end

-- 切换驾驶模式并持久化
function M.set_mode(i)
  M.mode = i
  if fskv then fskv.set(KEY, "mode", i) end
end

return M
