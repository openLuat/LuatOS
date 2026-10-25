--[[
@module  photo_view
@summary 全屏照片渲染层：不再写 SD 缓存，打开照片直接用 airui.image 显示原始 JPEG
@version 3.0
@date    2026.10.24

=== 本版做了什么改动（相对 2.0）===
  旧版：videoplayer 把 JPEG 解成 RGB565，写成一个 1.23MB 的 .bin 到 SD，
        显示阶段按行从 .bin 读（LV_BIN_DECODER_RAM_LOAD=0），翻页不占大块内存，
        但代价是 SD 上会积累大量 .bin 缓存文件（用户不希望写 SD）。
  新版：直接 airui.image(src=原 JPEG 路径) 显示原图，SD 上不再生成任何文件。

=== 对外接口保持不变 ===
  attach / engine / path / has / cached / show / prefetch / destroy
  （ui_viewer.lua 只依赖这些名字，未改调用面）
]]
local conf = require "conf"

local M = {}

local SW, SH = conf.W, conf.H
local layer = nil
local widget = nil
local cur_path = nil

-- ==================== 内存观察 ====================
local function free_bytes()
    local ok, total, used = pcall(rtos.meminfo, "psram")
    if ok and type(total) == "number" and type(used) == "number" then
        return total - used, total
    end
    return nil
end

local function memlog(tag)
    local free, total = free_bytes()
    if free then
        log.info("photo_view", tag, "psram free", free, "/", total)
    end
end

-- ==================== 对外 ====================
function M.attach(parent)
    layer = parent
end

-- 引擎标识：本版直接显示 JPEG 原图，不再生成 .bin
function M.engine()
    return widget and "img" or nil
end

function M.path()
    return cur_path
end

function M.has(path)
    return widget ~= nil and cur_path == path
end

-- 缓存状态：直接显示 JPEG 方案下无法从 Lua 侧知道 LVGL 图片缓存是否命中，
-- 也不再依赖盘上 .bin。固定返回 false，避免误标"命中"误导诊断。
-- （实测：即使标"复用/命中"，同一张图仍可能 hzjpeg alloc fail）
function M.cached(entry, w, h)
    return false
end

--[[显示一张照片：直接用 airui.image 显示 JPEG 原图
@param table entry {name, path, size}
@param table|nil meta  {w, h}
@return string|nil engine, string|nil err, boolean cached
]]
function M.show(entry, meta, sw, sh)
    if not layer then return nil, "no layer" end
    if not entry or not entry.path then return nil, "no entry" end

    SW = sw or SW
    SH = sh or SH

    -- 已经是这张：什么都不用做
    if widget and cur_path == entry.path then
        memlog("show(same)")
        return "img", nil, true
    end

    memlog("before show")

    -- 复用一个 image 控件，只换 src（避免每次重建控件/申请大块）
    if widget then
        local ok = pcall(function() widget:set_src(entry.path) end)
        if not ok then
            pcall(function() widget:destroy() end)
            widget = nil
        end
    end
    if not widget then
        widget = airui.image({
            parent = layer, x = 0, y = 0, w = SW, h = SH,
            src = entry.path, fit = "cover",
        })
        if not widget then return nil, "no mem" end
    end

    cur_path = entry.path
    memlog("after show")
    return "img", nil, false
end

--[[预加载下一张：直接显示 JPEG，解码发生在 set_src 时，这里没有可提前做的
后台工作，保持空操作以兼容 ui_viewer 的调用。
]]
function M.prefetch(entry, delay_ms)
    return
end

function M.destroy()
    if widget then
        pcall(function() widget:destroy() end)
    end
    widget, cur_path = nil, nil
end

return M