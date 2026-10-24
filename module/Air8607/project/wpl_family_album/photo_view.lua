--[[
@module  photo_view
@summary 全屏照片渲染层：JPEG 解成 RGB565 后写成 LVGL .bin，显示阶段不占大块内存
@version 2.0
@date    2026.10.22

=== 为什么要这么绕（V1028 真机日志结论）===
1. airui.video：建第一个控件后空闲 4.23MB，第二个 create 连 1.23MB 都分不出来
   （`videoplayer decode failed: -2` = NOMEM）；即便先删后建，也只能撑两三张 ——
   这个堆 free 出来的 2.46MB 不会和邻居合并，几轮之后就没有连续块了。
2. airui.image 直接放 JPEG：hzjpeg 要 1.84MB，还要进 4MB 图片缓存，
   两三张之后同样 `alloc fail`。

=== 现在的做法 ===
  1. videoplayer.open(照片) + read_frame() 取一帧 RGB565（1024x600x2 = 1.23MB，用完即还）；
  2. 加 12 字节 LVGL 图片头，原样写成 /.afull_<hash>.bin（1.23MB）；
  3. airui.image 加载这个 .bin：固件里 LV_BIN_DECODER_RAM_LOAD=0，
     解码器是**按行从文件读**的，所以显示一张照片的运行期内存只有几 KB，
     而且完全不进 LVGL 图片缓存。

结果：翻页/显示阶段不再申请任何大块，只有“第一次看这张照片”时才解一帧；
生成过就留在 SD 上，下次（含重启）直接秒开。
]]
local conf = require "conf"

local M = {}

local SW, SH = conf.W, conf.H
local layer = nil
local widget = nil
local cur_path, cur_w, cur_h = nil, 0, 0
local prefetching = false

local BIN_PREFIX = "/.af1_"     -- 带版本号，换格式时改这里，旧前缀的残留会被启动清理删掉

--[[文件大小（拿不到返回 -1）]]
local function file_size(path)
    local f = io.open(path, "rb")
    if not f then return -1 end
    local ok, sz = pcall(function() return f:seek("end") end)
    f:close()
    if ok and type(sz) == "number" then return sz end
    return -1
end

--[[缓存是否可用：读 12 字节头算出应有大小，0 字节 / 写一半的直接删掉重做]]
local function cache_ok(path)
    if not io.exists(path) then return false end
    local f = io.open(path, "rb")
    if not f then return false end
    local hdr = f:read(12)
    local sz = -1
    pcall(function() sz = f:seek("end") end)
    f:close()

    if type(hdr) ~= "string" or #hdr < 12 or hdr:byte(1) ~= 0x19 then
        pcall(os.remove, path)
        log.warn("photo_view", "删除损坏的大图缓存", path)
        return false
    end
    local w = hdr:byte(5) + hdr:byte(6) * 256
    local h = hdr:byte(7) + hdr:byte(8) * 256
    if w < 8 or h < 8 or (sz >= 0 and sz < 12 + w * h * 2) then
        pcall(os.remove, path)
        log.warn("photo_view", "删除不完整的大图缓存", path, sz)
        return false
    end
    return true
end

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

local function low_mem()
    local free = free_bytes()
    return free ~= nil and free < (3 * 1024 * 1024)
end

-- ==================== 缓存文件 ====================
-- djb2：路径+大小+尺寸 一起哈希，换图/换尺寸会自动重建
local function hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) & 0x7FFFFFFF
    end
    return string.format("%08x", h)
end

local function bin_path(entry, w, h)
    local key = hash(entry.path .. "|" .. tostring(entry.size or 0) .. "|" .. w .. "x" .. h)
    return conf.sd.mount .. BIN_PREFIX .. key .. ".bin"
end

--[[把一帧 RGB565 原样写成 LVGL .bin
文件头 12 字节：magic 0x19 / cf 0x12(RGB565) / flags 0 / w / h / stride / reserved
]]
local function write_bin_file(path, data, w, h)
    local stride = w * 2
    local need = w * h * 2

    local f = io.open(path, "wb")
    if not f then return false end

    f:write(string.char(
        0x19, 0x12, 0, 0,
        w % 256, math.floor(w / 256) % 256,
        h % 256, math.floor(h / 256) % 256,
        stride % 256, math.floor(stride / 256) % 256,
        0, 0))

    -- 分块写：一边写一边让出 CPU，界面不至于卡住两秒
    local pos, len, CH = 1, need, 32768
    while pos <= len do
        local stop = pos + CH - 1
        if stop > len then stop = len end
        local ok = f:write(data:sub(pos, stop))
        if not ok then
            f:close()
            pcall(os.remove, path)
            return false
        end
        pos = stop + 1
        sys.wait(2)
    end
    f:close()

    -- 写一半（卡满/掉卡）就删掉，避免下次误当成有效缓存
    local sz = file_size(path)
    if sz >= 0 and sz < need then
        pcall(os.remove, path)
        return false
    end
    return true
end

local pending = {}        -- path -> true，正在写（避免预生成和立即打开同时写同一个文件）

--[[真正干活：解一帧 → 写 .bin]]
local function do_generate(entry, path, w, h)
    local vp = videoplayer.open(entry.path)
    if not vp then return nil, "open fail" end

    local frame, err = videoplayer.read_frame(vp)
    videoplayer.close(vp)
    if not frame then return nil, tostring(err or "read fail") end

    local fw, fh = frame.width or 0, frame.height or 0
    local data = frame.data
    frame = nil
    if fw < 8 or fh < 8 or type(data) ~= "string" or #data < fw * fh * 2 then
        return nil, "bad frame"
    end

    local ok = write_bin_file(path, data, fw, fh)
    data = nil
    collectgarbage("collect")        -- 1.23MB 像素串尽快还给堆
    if not ok then return nil, "write fail" end

    log.info("photo_view", "生成大图", entry.name, string.format("%dx%d", fw, fh))
    return path, nil, false
end

--[[生成（或命中）一张全屏 .bin
@return string|nil path, string|nil err, boolean cached
]]
local function generate(entry, w, h)
    local path = bin_path(entry, w, h)
    if cache_ok(path) then return path, nil, true end

    if not videoplayer or not videoplayer.open then return nil, "no videoplayer" end
    if low_mem() then return nil, "low mem" end

    pending[path] = true
    local out, err2, cached2 = do_generate(entry, path, w, h)
    pending[path] = nil
    return out, err2, cached2
end

-- ==================== 对外 ====================
function M.attach(parent)
    layer = parent
end

function M.engine()
    return widget and "bin" or nil
end

function M.path()
    return cur_path
end

function M.has(path)
    return widget ~= nil and cur_path == path
end

--[[这张照片的 .bin 是否已经生成好了（调用方用来决定要不要显示“正在打开照片”）]]
function M.cached(entry, w, h)
    if not entry or not entry.path then return false end
    return cache_ok(bin_path(entry, w or SW, h or SH))
end

--[[显示一张照片
@param table entry {name, path, size}
@param table|nil meta  {w, h}
@return string|nil engine, string|nil err, boolean cached
]]
function M.show(entry, meta, sw, sh)
    if not layer then return nil, "no layer" end
    if not entry or not entry.path then return nil, "no entry" end

    SW = sw or SW
    SH = sh or SH
    local w = (meta and meta.w) or SW
    local h = (meta and meta.h) or SH

    -- 已经是这张：什么都不用做
    if widget and cur_path == entry.path then
        memlog("show(same)")
        return "bin", nil, true
    end

    memlog("before show")
    -- 后台正在生成这张时，等它写完再显示，避免两边同时写同一个文件
    local ready = bin_path(entry, w, h)
    while pending[ready] and not io.exists(ready) do
        sys.wait(50)
    end

    local path, err, cached = generate(entry, w, h)
    if not path then return nil, err end

    -- 一个 image 控件全程复用，只换 src（不会申请任何大块）
    if widget then
        local ok = pcall(function() widget:set_src(path) end)
        if not ok then
            pcall(function() widget:destroy() end)
            widget = nil
        end
    end
    if not widget then
        widget = airui.image({
            parent = layer, x = 0, y = 0, w = SW, h = SH,
            src = path, fit = "cover",
        })
        if not widget then return nil, "no mem" end
    end

    cur_path, cur_w, cur_h = entry.path, w, h
    memlog("after show")
    return "bin", nil, cached
end

--[[预生成下一张（后台做，用户翻过去时就是秒开）
注意：解码那 0.6s 是 C 里阻塞的，写完会立刻让出。
]]
function M.prefetch(entry, delay_ms)
    if conf.photo.prefetch == false then return end
    if prefetching or not entry or not entry.path then return end
    if widget and cur_path == entry.path then return end

    local w, h = SW, SH
    if cache_ok(bin_path(entry, w, h)) then return end

    prefetching = true
    sys.taskInit(function()
        -- 轮播时给很短的延时（否则下一张赶不上 3 秒的节拍）；手动浏览时多等一会
        sys.wait(delay_ms or 1500)
        local path, err = generate(entry, w, h)
        prefetching = false
        if path then
            log.info("photo_view", "预生成完成", entry.name)
        else
            log.warn("photo_view", "预生成失败", entry.name, tostring(err))
        end
    end)
end

function M.destroy()
    if widget then
        pcall(function() widget:destroy() end)
    end
    widget, cur_path = nil, nil
    cur_w, cur_h = 0, 0
end

return M
