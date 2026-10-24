--[[
@module  thumb
@summary 目录页缩略图：把 SD 上的 JPEG 解成 RGB565，按 N 倍采样后写成 LVGL .bin 小图
@version 1.0
@date    2026.10.22

=== 为什么绕这么大一圈 ===
LVGL 解 JPEG 是按**原图尺寸**解的（1024x600 = 1.84MB），控件做多小都一样，
解完还要进 4MB 的图片缓存（能塞两张）。一页 4 张预览 = 4×1.84MB，
后面全屏查看要的 4.19MB 就分配不出来了 —— 这就是之前 OOM 的根。

所以预览图改成“离线小图”：
  1. videoplayer.read_frame() 拿一帧 RGB565 原始像素（1024x600x2 = 1.23MB，用完即释放）；
  2. 每 5x5 像素块取 3x3 个点做面积平均（不是点采样，点采样会拉丝）→ 204x120；
  3. 加上 LVGL 的 12 字节图片头，写成 /sd/.athumb_<hash>.bin（约 49KB）；
  4. airui.image 直接加载这个 .bin，解码峰值就 49KB，缓存也只占 49KB。

于是：一张照片最多只“大”一次（首次生成），之后翻页、重启都是秒开。
缓存放在 SD 根目录（点开头命名，相册里看不到，约 50KB/张），不占内存；
删掉 /.athumb_*.bin 就全部重建。

=== .bin 文件格式（LVGL 9 lv_bin_decoder）===
  offset 0  : magic = 0x19
  offset 1  : cf    = 0x12 (LV_COLOR_FORMAT_RGB565)
  offset 2  : flags (u16, 0 = 不压缩)
  offset 4  : w     (u16)
  offset 6  : h     (u16)
  offset 8  : stride(u16, = w*2)
  offset 10 : reserved (u16, 0)
  offset 12 : 像素数据，逐行，RGB565 小端
]]
local conf = require "conf"

local M = {}

-- 缩略图直接放在 SD 根目录，用点开头命名：
-- 固件没有 io.mkdir（建不了子目录），而 sd.list 会跳过点开头的条目，相册里看不到。
local PREFIX = conf.photo.thumb_prefix or "/.at3_"
local ALGO = "avg3"      -- 缩小算法版本，改算法时一并改掉，旧的缩略图自动重建

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
        log.warn("thumb", "删除损坏的缩略图缓存", path)
        return false
    end
    local w = hdr:byte(5) + hdr:byte(6) * 256
    local h = hdr:byte(7) + hdr:byte(8) * 256
    if w < 8 or h < 8 or (sz >= 0 and sz < 12 + w * h * 2) then
        pcall(os.remove, path)
        log.warn("thumb", "删除不完整的缩略图缓存", path, sz)
        return false
    end
    return true
end
local ready = {}          -- key -> true，本进程已确认文件可用

-- djb2：路径+大小+缩放倍数 一起哈希，换图/换尺寸会自动重建
local function hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) & 0x7FFFFFFF
    end
    return string.format("%08x", h)
end

local function low_mem()
    local ok, total, used = pcall(rtos.meminfo, "psram")
    if not ok or type(total) ~= "number" or type(used) ~= "number" then
        return false
    end
    return (total - used) < (3 * 1024 * 1024)
end

--[[把一帧 RGB565 等比例缩小并写成 .bin
缩小用**面积平均**（每个目标像素取 3x3 个采样点做平均），不是“每 5 个点抓 1 个”。
后者是点采样，缩风景照会有明显锯齿/拉丝（之前用户看到的“糊、拉丝”就是它）。

@param string data  原始像素（RGB565，小端）
@param number sw, sh 原图尺寸
@param number factor 缩小倍数（1024x600 / 5 = 204x120）
@param string path   输出文件
@return boolean ok, number ow, number oh
]]
local function write_bin(data, sw, sh, factor, path)
    local ow = math.floor(sw / factor)
    local oh = math.floor(sh / factor)
    if ow < 8 or oh < 8 then return false end

    local row_bytes = sw * 2
    local stride = ow * 2
    local half = math.floor(factor / 2)
    local rows = {}
    local rb = { 0, 0, 0 }        -- 3 个源行偏移，每个输出行复用

    for y = 0, oh - 1 do
        local y0 = y * factor
        local ym = y0 + half
        local y1 = y0 + factor - 1
        if y1 > sh - 1 then y1 = sh - 1 end
        rb[1] = y0 * row_bytes
        rb[2] = ym * row_bytes
        rb[3] = y1 * row_bytes

        local out = {}
        for x = 0, ow - 1 do
            local x0 = x * factor
            local xm = x0 + half
            local x1 = x0 + factor - 1
            if x1 > sw - 1 then x1 = sw - 1 end
            local p0 = x0 * 2 + 1
            local pm = xm * 2 + 1
            local p1 = x1 * 2 + 1

            local r, g, b = 0, 0, 0
            for i = 1, 3 do
                local base = rb[i]
                local l1, h1 = data:byte(base + p0, base + p0 + 1)
                local l2, h2 = data:byte(base + pm, base + pm + 1)
                local l3, h3 = data:byte(base + p1, base + p1 + 1)
                local v1 = l1 + h1 * 256
                local v2 = l2 + h2 * 256
                local v3 = l3 + h3 * 256
                r = r + (v1 >> 11) + (v2 >> 11) + (v3 >> 11)
                g = g + ((v1 >> 5) & 63) + ((v2 >> 5) & 63) + ((v3 >> 5) & 63)
                b = b + (v1 & 31) + (v2 & 31) + (v3 & 31)
            end

            local v = ((r // 9) << 11) | (((g // 9) << 5)) | (b // 9)
            out[x + 1] = string.char(v & 0xFF, (v >> 8) & 0xFF)
        end
        rows[y + 1] = table.concat(out)
        if (y & 7) == 7 then sys.wait(1) end   -- 每 8 行让一次 CPU，界面不至于僵住
    end

    local f = io.open(path, "wb")
    if not f then return false end
    f:write(string.char(
        0x19, 0x12, 0, 0,
        ow % 256, math.floor(ow / 256) % 256,
        oh % 256, math.floor(oh / 256) % 256,
        stride % 256, math.floor(stride / 256) % 256,
        0, 0))
    f:write(table.concat(rows))
    f:close()

    -- 写一半（卡满/掉卡）就删掉，避免下次误当成有效缓存
    local sz = file_size(path)
    if sz >= 0 and sz < 12 + ow * oh * 2 then
        pcall(os.remove, path)
        return false
    end
    return true, ow, oh
end

--[[生成缩略图（会阻塞，约 0.5~1s；调用方应放在 task 里逐张做）
@param table entry {name, path, size}
@param number|nil factor 采样倍数，默认 conf.photo.thumb_factor
@return string|nil bin 路径, number ow, number oh, string|nil err
]]
local function do_build(entry, factor)
    if not entry or not entry.path then return nil, 0, 0, "no entry" end
    factor = factor or conf.photo.thumb_factor or 5

    -- ALGO 变了就整体重建：旧的点采样缩略图会拉丝，不能复用
    local key = hash(entry.path .. "|" .. tostring(entry.size or 0) .. "|" .. factor .. "|" .. ALGO)
    local path = conf.sd.mount .. PREFIX .. key .. ".bin"

    if ready[key] then return path end
    if cache_ok(path) then
        ready[key] = true
        return path
    end

    -- videoplayer 是 userdata（不是 table），必须按方法判断
    if not videoplayer or not videoplayer.open then return nil, 0, 0, "no videoplayer" end
    if low_mem() then return nil, 0, 0, "low mem" end

    local vp = videoplayer.open(entry.path)
    if not vp then return nil, 0, 0, "open fail" end

    local frame, err = videoplayer.read_frame(vp)
    videoplayer.close(vp)              -- 帧数据已拷贝成 Lua 字符串，这里可以放心关
    if not frame then return nil, 0, 0, tostring(err or "read fail") end

    local sw, sh = frame.width or 0, frame.height or 0
    local data = frame.data
    frame = nil                        -- 放出 frame 表，只剩 data 这个字符串
    if not data or sw < 8 or sh < 8 then return nil, 0, 0, "bad frame" end

    local ok, ow, oh = write_bin(data, sw, sh, factor, path)
    data = nil
    collectgarbage("collect")          -- 1.23MB 的像素串尽快还给堆

    if not ok then return nil, 0, 0, "write fail" end
    ready[key] = true
    log.info("thumb", "生成缩略图", entry.name, string.format("%dx%d", ow, oh))
    return path, ow, oh
end

--[[对外入口：失败时打一条日志，方便真机定位
@return string|nil bin 路径, number ow, number oh, string|nil err
]]
function M.build(entry, factor)
    local path, ow, oh, err = do_build(entry, factor)
    if not path then
        log.warn("thumb", "缩略图失败", entry and entry.name or "?", tostring(err))
    end
    return path, ow, oh, err
end

return M
