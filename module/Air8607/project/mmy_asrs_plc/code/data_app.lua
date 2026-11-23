--[[
@module  data_app
@summary 业务数据：ASRS-2400 立体库的库位状态、出入库计数、任务队列与维护项
@version 1.0.0
@date    2026.11.22
@usage
1、720 个库位的初始状态由 cell_state.lua 提供（与 main.xml 里预置的颜色一一对应）；
2、每 3 秒做一次搬运：随机一个在库位出库、随机一个空位入库，两者成对，总数守恒；
3、两台堆垛机的作业位置由 data_app 算出格子坐标，ui_app 用它移动赭石标记。
对外接口 8 个：init / step / cell_state / cell_xy / get / pick_move / tasks / bright。
]]

local data_app = {}

local ROWS, COLS, LAYERS = 6, 12, 5
local TOTAL = ROWS * COLS * LAYERS
-- 与 main.xml 的网格几何一致：卡片 (12,104) + 起点 (56,50)，pitch (22,9)，格 20×8
local GX, GY = 12 + 56, 104 + 50
local PX, PY = 44, 10

local INIT = require "cell_state"

local S = {
    cells = {},          -- 0 空位 / 1 在库 / 2 锁定
    full = 0,
    lock = 0,
    tick = 0,
    clock_sec = 20 * 3600 + 28 * 60,
    day_in = 132,
    day_out = 118,
    avg_s = 48,
    use = 94.2,
    tasks = {},
    alarms = {},
}

local function jitter(a) return (math.random() - 0.5) * 2 * a end

local function now_clock()
    local t = S.clock_sec % 86400
    return string.format("%02d:%02d", math.floor(t / 3600), math.floor((t % 3600) / 60))
end

function data_app.init()
    S.cells = {}
    local i = 1
    for k = 1, TOTAL do
        S.cells[k] = tonumber(INIT:sub(k, k)) or 0
    end
    S.full, S.lock = 0, 0
    for k = 1, TOTAL do
        if S.cells[k] == 1 then S.full = S.full + 1
        elseif S.cells[k] == 2 then S.lock = S.lock + 1 end
    end
    S.tasks = {
        { no = "01", op = "出库", loc = "S3-14-3", st = "执行中" },
        { no = "02", op = "入库", loc = "S1-07-2", st = "执行中" },
        { no = "03", op = "移库", loc = "S5-19-1 → S2-03-4", st = "排队" },
        { no = "04", op = "出库", loc = "S6-02-5", st = "排队" },
        { no = "05", op = "入库", loc = "S4-11-1", st = "排队" },
    }
    S.alarms = {
        { t = "20:01", x = "SC2 取货到位信号延迟 0.3 s" },
        { t = "18:42", x = "输送线 2 段货物偏移，已复位" },
    }
    log.info("data", "立体库状态初始化", "在库", S.full, "锁定", S.lock, "空位", TOTAL - S.full - S.lock)
end

--[[ 每秒推进 ]]
function data_app.step()
    S.tick = S.tick + 1
    S.clock_sec = S.clock_sec + 1
    S.avg_s = 48 + jitter(1.2)
    S.use = 94.2 + jitter(0.3)
end

--[[ 下标换算：r/c/l 从 0 起 ]]
local function index(r, c, l) return (r * COLS + c) * LAYERS + l + 1 end

function data_app.cell_state(r, c, l) return S.cells[index(r, c, l)] end

--[[ 格子左上角坐标，供移动作业标记 ]]
function data_app.cell_xy(r, c, l)
    return GX + c * PX, GY + r * (LAYERS * PY + 10) + l * PY
end

--[[ 每 3 秒一次搬运：一个出库 + 一个入库，总数守恒 ]]
function data_app.pick_move()
    local out, into
    for _ = 1, 60 do
        local k = math.random(1, TOTAL)
        if not out and S.cells[k] == 1 then out = k end
    end
    for _ = 1, 60 do
        local k = math.random(1, TOTAL)
        if not into and S.cells[k] == 0 then into = k end
    end
    if not (out and into) then return nil end
    S.cells[out] = 0
    S.cells[into] = 1
    S.day_out = S.day_out + 1
    S.day_in = S.day_in + 1
    return { out = out, into = into }
end

--[[ 由下标还原 r/c/l ]]
function data_app.split(k)
    local i = k - 1
    local l = i % LAYERS
    local c = math.floor(i / LAYERS) % COLS
    local r = math.floor(i / (LAYERS * COLS))
    return r, c, l
end

function data_app.cell_id(r, c, l) return string.format("c%d_%d_%d", r, c, l) end

function data_app.tasks() return S.tasks end
function data_app.task_count() return 14 end

--[[ 界面快照 ]]
function data_app.get()
    local v = {}
    local occ = S.full / TOTAL * 100
    v.clock = now_clock()
    v.h_stock = string.format("在库 %d / %d · 占用 %.1f %%", S.full, TOTAL, occ)
    v.st_in = string.format("今日入库 %d 托", S.day_in)
    v.st_out = string.format("出库 %d 托", S.day_out)
    v.st_task = string.format("待执行任务 %d", 14)
    v.st_avg = string.format("平均作业 %d s / 托", math.floor(S.avg_s + 0.5))
    v.st_use = string.format("设备稼动 %.1f %%", S.use)
    v.t_cnt = string.format("%d 条待执行", 14)
    for i = 1, 5 do
        local tk = S.tasks[i]
        v["t_no" .. (i - 1)] = tk and tk.no or ""
        v["t_op" .. (i - 1)] = tk and tk.op or ""
        v["t_lo" .. (i - 1)] = tk and tk.loc or ""
        v["t_st" .. (i - 1)] = tk and tk.st or ""
    end
    return v
end

function data_app.set_bright() end
function data_app.bright() return 82 end

return data_app
