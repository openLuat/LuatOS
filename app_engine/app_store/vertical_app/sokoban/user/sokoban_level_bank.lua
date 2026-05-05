--[[
@module  sokoban_level_bank
@summary 启动时批量预生成并验证关卡，游戏内只做加载
]]

local level_gen = require "sokoban_level"

local M = {}

-- 嵌入式内存受限：首批预生成不要过大，后续可按需扩展
local PREGEN_LEVEL_COUNT = 16
local RETRY_PER_LEVEL = 6

local cache = {}
local built = false

local function make_fallback_level(level)
    local w = math.min(12, 7 + math.floor((level - 1) / 3))
    local h = math.min(12, 7 + math.floor((level - 1) / 4))
    local box_n = math.min(4, 1 + math.floor((level - 1) / 4))
    local walls = {}
    local goals = {}
    local boxes = {}
    for y = 1, h do
        walls[y] = {}
        goals[y] = {}
        boxes[y] = {}
        for x = 1, w do
            walls[y][x] = (x == 1 or y == 1 or x == w or y == h)
            goals[y][x] = false
            boxes[y][x] = false
        end
    end
    local start_x = math.max(2, math.floor((w - box_n) / 2))
    for i = 0, box_n - 1 do
        local x = start_x + i
        if x > w - 1 then
            x = w - 1
        end
        goals[2][x] = true
        boxes[3][x] = true
    end
    return {
        level = level,
        w = w,
        h = h,
        walls = walls,
        goals = goals,
        boxes = boxes,
        player = { x = math.floor(w / 2), y = h - 2 },
        target_pushes = box_n,
    }
end

function M.ensure()
    if built then
        return true
    end
    cache = {}
    for lv = 1, PREGEN_LEVEL_COUNT do
        local ok_level = nil
        for _ = 1, RETRY_PER_LEVEL do
            local map = level_gen.generate(lv)
            if map then
                ok_level = map
                break
            end
            if collectgarbage then
                collectgarbage("collect")
            end
        end
        if not ok_level then
            -- 保底：即使随机生成失败，也提供固定可解模板，避免黑屏/无法进入
            ok_level = make_fallback_level(lv)
        end
        cache[lv] = ok_level
        if collectgarbage then
            collectgarbage("collect")
        end
    end
    built = true
    if collectgarbage then
        collectgarbage("collect")
    end
    return true
end

function M.get(level)
    if not built then
        if not M.ensure() then
            return nil
        end
    end
    return cache[level]
end

function M.count()
    if not built then
        return 0
    end
    return #cache
end

return M
