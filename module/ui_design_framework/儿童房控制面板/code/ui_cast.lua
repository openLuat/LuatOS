--[[
@module  ui_cast
@summary 角色系统：每套主题各记一个当前角色（1..5），负责切换、弧形槽位与贴图名
@version 1.0.0
@note 与效果稿 S.cast[themeKey] 一致：切主题回到该主题上次选的角色，切回来不丢。
      弧形槽位 ARC 与效果稿一致：左二(-2) 左一(-1) 右一(+1) 右二(+2)，
      切角色后整条弧前移一格，所以同一个位置连点能依次切遍 5 个角色。
]]
local T = require "ui_theme"

local M = {}

local ARC = { -2, -1, 1, 2 }
M.ARC = ARC

--- 当前主题的当前角色下标（1..5）
function M.idx()
    return T.cast_idx[T.idx] or 1
end

--- 指定角色（自动取模），返回新下标
function M.select(i)
    i = ((math.floor(tonumber(i) or 1) - 1) % 5 + 5) % 5 + 1
    T.cast_idx[T.idx] = i
    T.save_cast()
    return i
end

--- 切下一个/上一个，返回新下标
function M.next(dir)
    return M.select(M.idx() + (dir or 1))
end

--- 当前角色名
function M.name()
    return T.cast[M.idx()] or "小星星"
end

--- 房间名 = 角色名 + 主题后缀（的小房间 / 的小屋 / 的基地）
function M.room_name()
    return M.name() .. T.suffix
end

--- 角色贴图名：big=true 大图（170），否则小图（56）
function M.img(big)
    return string.format("ch_%s_%d_%s", T.key, M.idx() - 1, big and "big" or "sm")
end

--- 第 k 个弧形槽位（1..4）当前应显示的角色下标（1..5）
function M.slot(k)
    return ((M.idx() - 1 + ARC[k]) % 5 + 5) % 5 + 1
end

--- 装饰贴纸名：st_<theme>_<k>
function M.sticker(k)
    return string.format("st_%s_%d", T.key, k)
end

--- 奖励贴纸名：按主题取对应格
function M.reward_sticker()
    return M.sticker(T.reward or 0)
end

return M
