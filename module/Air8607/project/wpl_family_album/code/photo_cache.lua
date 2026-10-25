--[[
@module  photo_cache
@summary 两槽照片缓存（路径 + 尺寸 + 有效性），保证本地最多只留两张
@version 1.0
@date    2026.10.22

=== 这里缓存什么、不缓存什么 ===
缓存的是“照片的元信息 + 文件头校验结果”，不缓存像素：

  槽 A：当前正在看的照片（路径 / 宽高 / 是否可解码）
  槽 B：下一张照片（提前 open 一次文件、读 4KB 头，拿到 SOF 尺寸）

像素在 photo_view 里，同样只有两份：双槽 A/B 各一个 airui.video 控件，
每个控件内部固定两块 1024x600 RGB565 帧缓冲。所以任何时刻最多 2 张照片、
4 帧像素，不会像 LVGL 图片缓存那样越积越多。

为什么不在 Lua 层缓存像素：
  1024x600 一张照片解码后是 RGB565 1.2MB / RGB888 1.84MB。Lua 里再存一张，
  等于在解码器缓冲之外又加一份，正好会复现 hzjpeg “连续内存不足”
  （1024x600 需要 1843200 字节）的报错。

所以“缓存最多两张”由两处共同保证：
  1) 本模块：最多 2 条元信息（纯字符串/数字，几十字节）；
  2) photo_view：最多 2 个渲染槽，离开相册立即 destroy 释放全部像素。
]]
local sd = require "sd_card"

local M = {}

local MAX_SLOTS = 2

-- 槽位表：下标 1 是最近使用的，超过 MAX_SLOTS 直接淘汰尾部
local slots = {}
local stat = { hit = 0, miss = 0, evict = 0 }

local function find(path)
    for i = 1, #slots do
        if slots[i].path == path then return i end
    end
    return nil
end

local function touch(i)
    if i == 1 then return end
    local s = table.remove(slots, i)
    table.insert(slots, 1, s)
end

local function put(meta)
    local i = find(meta.path)
    if i then
        slots[i] = meta
        touch(i)
        return meta
    end

    table.insert(slots, 1, meta)
    while #slots > MAX_SLOTS do
        table.remove(slots)
        stat.evict = stat.evict + 1
    end
    return meta
end

--[[清空缓存（重新读卡 / 换目录时调用）]]
function M.reset()
    slots = {}
    stat = { hit = 0, miss = 0, evict = 0 }
end

function M.count()
    return #slots
end

function M.stats()
    return stat.hit, stat.miss, stat.evict, #slots
end

--[[读一个条目的元信息（带缓存）
@param table entry sd_card.list() 返回的条目 {name, path, size}
@return table meta {path, name, size, w, h, ok}
]]
function M.ensure(entry)
    if not entry then return nil end
    local path = entry.path

    local i = find(path)
    if i then
        touch(i)
        stat.hit = stat.hit + 1
        return slots[i]
    end

    stat.miss = stat.miss + 1
    local w, h = sd.jpeg_size(path)
    local meta = {
        path = path,
        name = entry.name,
        size = entry.size or 0,
        w = w, h = h,
        ok = (w ~= nil and h ~= nil),
    }
    if not meta.ok then
        log.warn("photo_cache", "不是可解码的 baseline JPEG 或文件损坏", path)
    end
    return put(meta)
end

return M
