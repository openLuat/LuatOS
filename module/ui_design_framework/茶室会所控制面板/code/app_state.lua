--[[
单一状态源：界面只读这里，写入只走本模块的函数
档位语义：0 = 关闭，1..MAX_LEVEL = 开启档位（不再单独存 on/off，少一半状态分支）
]]

local CFG = require "app_config"

local S = {}

local N = #CFG.DEVICES
local KEY = "tea_cfg"

S.levels = {}
S.last = {}
S.scene = 0        -- 0 = 自定义（与任何预设都不等）
S.theme = "night"
S.bright = 100     -- 固定满亮，不再作为可调项，也不落盘
S.dnd = false
S.bell = false
S.view = "wall"
S.device = 1

for i = 1, N do
    S.levels[i] = 3
    S.last[i] = 6
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function S.on(i)
    return (S.levels[i] or 0) > 0
end

function S.count_on()
    local n = 0
    for i = 1, N do
        if S.levels[i] > 0 then n = n + 1 end
    end
    return n
end

function S.set_level(i, v)
    v = clamp(math.floor(tonumber(v) or 0), 0, CFG.MAX_LEVEL)
    if S.levels[i] == v then return false end
    if v > 0 then S.last[i] = v end
    S.levels[i] = v
    S.scene = S.match_scene()
    return true
end

function S.toggle(i)
    if S.on(i) then
        S.last[i] = S.levels[i]
        S.set_level(i, 0)
    else
        S.set_level(i, S.last[i] or 5)
    end
    return S.on(i)
end

-- 当前档位组合与哪套预设完全一致；都不一致返回 0
function S.match_scene()
    for k = 1, #CFG.SCENES do
        local lv = CFG.SCENES[k].levels
        local same = true
        for i = 1, N do
            if (S.levels[i] or 0) ~= lv[i] then same = false break end
        end
        if same then return k end
    end
    return 0
end

-- 返回是否真的变了（用于决定要不要重绘场景条）
function S.apply_scene(k)
    local sc = CFG.SCENES[k]
    if not sc then return false end
    for i = 1, N do
        local v = sc.levels[i] or 0
        S.levels[i] = v
        if v > 0 then S.last[i] = v end
    end
    S.scene = k
    return true
end

--- 立即落盘
local save_timer
function S.save()
    if save_timer then
        pcall(sys.timerStop, save_timer)
        save_timer = nil
    end
    local d = { l = S.levels, t = S.theme, dnd = S.dnd, n = S.last }
    local ok = pcall(fskv.set, KEY, json.encode(d))
    return ok
end

--[[
合并落盘（P7）：
  调档 ± / 快捷档 / 亮度 ± 都是一两百毫秒连点一次的操作，
  每点一次就 json.encode + fskv.set 等于把 flash 写塞进点击回调里，
  真机上表现为"按下去要等一下才变色"。这里改成 600ms 合并：
  连点 10 次只落一次盘，界面即时响应，掉电最多丢 600ms 内的调整。
]]
function S.save_soon()
    if save_timer then return end
    save_timer = sys.timerStart(function()
        save_timer = nil
        S.save()
    end, 600)
end

function S.load()
    local ok, raw = pcall(fskv.get, KEY)
    if not ok or type(raw) ~= "string" then return end
    local ok2, d = pcall(json.decode, raw)
    if not ok2 or type(d) ~= "table" then return end
    if type(d.l) == "table" then
        for i = 1, N do
            S.levels[i] = clamp(math.floor(tonumber(d.l[i]) or S.levels[i]), 0, CFG.MAX_LEVEL)
        end
    end
    if type(d.n) == "table" then
        for i = 1, N do
            local v = math.floor(tonumber(d.n[i]) or 0)
            if v > 0 then S.last[i] = v end
        end
    end
    if d.t == "paper" or d.t == "night" then S.theme = d.t end
    -- 旧存档里的 b（亮度）直接忽略：亮度固定 100%
    S.dnd = d.dnd == true
    S.scene = S.match_scene()
end

return S
