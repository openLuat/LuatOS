--[[
@module  sd_card
@summary TF/SD 卡挂载、目录枚举与 JPEG 头解析
@version 1.0
@date    2026.10.22

=== 硬件（Air8607）===
SD 卡走 SPI1：SPI1_CS = GPIO8，SD_EN = GPIO74（高电平供电）。
初始化顺序必须是：SD_EN 上电 -> 等电压稳定 -> spi.setup(400k) -> CS 拉高 -> fatfs.mount。

=== 为什么不自动格式化 ===
fatfs.mount 第 8 个参数 auto_format 传 false。默认 true 时挂载失败会直接格式化
用户的卡，相册工程绝不能这么干。挂载失败只报错并重试一次低速（10MHz）。

=== 目录枚举 ===
io.lsdir 单次最多 100 条，这里按 offset 分页累加；单目录最多扫 scan_max 条，
避免超大目录（几千张照片）把 Lua 内存吃光。列表只保留 name/size/type，
不读文件内容，也不做缩略图。
]]
local conf = require "conf"

local M = {}

local SD = conf.sd
local mounted = false
local last_err = nil

-- ==================== 挂载 ====================
local function do_mount(speed)
    spi.setup(SD.spi_id, nil, 0, 0, 8, 400000)   -- 先用保守时钟建总线
    gpio.setup(SD.pin_cs, 1)                      -- 同总线从设备初始化前必须拉高 CS
    return fatfs.mount(fatfs.SPI, SD.mount, SD.spi_id, SD.pin_cs,
        speed, nil, 10, false)                   -- auto_format = false
end

--[[挂载 SD 卡（幂等）
@return boolean ok, string|nil err
]]
function M.mount()
    if mounted then return true end

    if not fatfs or not fatfs.mount then
        last_err = "固件缺少 fatfs 库"
        log.error("sd", last_err)
        return false, last_err
    end

    -- 已经挂过（比如热复位前挂载点还在）
    if io.dexist(SD.mount) then
        mounted = true
        log.info("sd", "挂载点已存在", SD.mount)
        return true
    end

    -- SD 卡供电使能
    if SD.pin_en then
        gpio.setup(SD.pin_en, 1)
        sys.wait(30)
    end

    local ok, err = do_mount(SD.speed)
    if not ok then
        log.warn("sd", "首次挂载失败，降速重试", tostring(err))
        sys.wait(80)
        ok, err = do_mount(10 * 1000 * 1000)
    end

    if ok then
        mounted = true
        last_err = nil
        log.info("sd", "挂载成功", SD.mount, "spi=" .. SD.spi_id, "cs=" .. SD.pin_cs)
        return true
    end

    last_err = tostring(err)
    log.error("sd", "挂载失败（未格式化卡）", last_err)
    return false, last_err
end

--[[卸载（一般不用，仅“重新读取SD卡”时可选）]]
function M.unmount()
    if not mounted then return true end
    pcall(fatfs.unmount, SD.mount)
    mounted = false
    return true
end

--[[重新挂载：用于拔插卡后手动刷新]]
function M.remount()
    M.unmount()
    sys.wait(100)
    return M.mount()
end

function M.is_mounted()
    return mounted
end

function M.last_error()
    return last_err
end

-- ==================== 路径与文件名 ====================
--[[拼路径，自动处理结尾斜杠]]
function M.join(dir, name)
    if not dir or dir == "" then return name end
    if dir:sub(-1) == "/" then return dir .. name end
    return dir .. "/" .. name
end

--[[取目录名（用于面包屑）]]
function M.basename(path)
    local name = path and path:match("([^/]+)/*$")
    return name or path or ""
end

--[[SD 路径转显示文案：/sd/家庭/2026 -> SD卡 / 家庭 / 2026]]
function M.pretty_path(path)
    if not path then return "" end
    local p = path
    local prefix = SD.mount
    if p:sub(1, #prefix) == prefix then
        p = p:sub(#prefix + 1)
    end
    if p == "" or p == "/" then return "SD卡" end
    p = p:gsub("^/+", ""):gsub("/+$", "")
    p = p:gsub("/", " / ")
    return "SD卡 / " .. p
end

--[[扩展名（小写，不含点）]]
function M.ext(name)
    local e = name and name:match("%.([^%.]+)$")
    return e and e:lower() or ""
end

function M.is_photo(name)
    return conf.photo.exts[M.ext(name)] == true
end

--[[过滤系统垃圾条目]]
local function skip_name(name)
    if not name or name == "" then return true end
    if name:sub(1, 1) == "." then return true end
    local low = name:lower()
    if low == "system volume information" then return true end
    if low == "$recycle.bin" or low == "recycler" then return true end
    return false
end

-- ==================== 目录枚举 ====================
--[[列目录（只读元信息，不读文件内容）
@param string dir 绝对路径，例如 "/sd/家庭"
@return table { dirs = {...}, photos = {...}, total = n, truncated = bool }
每一项：{ name = "a.jpg", path = "/sd/a.jpg", size = 12345, dir = false }
]]
function M.list(dir)
    local res = { dirs = {}, photos = {}, total = 0, truncated = false }
    if not mounted then return res end

    local offset = 0
    local scanned = 0

    local visited = 0

    while true do
        local ok, data = io.lsdir(dir, SD.page_size, offset)
        if not ok or type(data) ~= "table" or #data == 0 then
            if not ok then
                log.warn("sd", "lsdir 失败", dir, tostring(data))
            end
            break
        end
        visited = visited + #data

        for _, it in ipairs(data) do
            local name = it.name
            if not skip_name(name) then
                local is_dir = (it.type == 1)
                local item = {
                    name = name,
                    path = M.join(dir, name),
                    size = it.size or 0,
                    dir = is_dir,
                }
                if is_dir then
                    res.dirs[#res.dirs + 1] = item
                    scanned = scanned + 1
                elseif M.is_photo(name) then
                    res.photos[#res.photos + 1] = item
                    scanned = scanned + 1
                end
            end
            if scanned >= SD.scan_max then
                res.truncated = true
                break
            end
        end

        if res.truncated or #data < SD.page_size then break end
        -- 目录里混了大量非照片文件时也要有个上限，别一页页翻到底
        if visited >= SD.scan_max * 4 then
            res.truncated = true
            break
        end
        offset = offset + #data
    end

    local function sorter(a, b)
        return a.name:lower() < b.name:lower()
    end
    table.sort(res.dirs, sorter)
    table.sort(res.photos, sorter)

    res.total = #res.dirs + #res.photos
    log.info("sd", "列目录", dir, "文件夹", #res.dirs, "照片", #res.photos, res.truncated and "(已截断)" or "")
    return res
end

--[[根目录概览：给首页显示“几个文件夹 / 几张照片”]]
function M.overview()
    local r = M.list(SD.mount)
    return #r.dirs, #r.photos
end

-- ==================== JPEG 头解析 ====================
--[[读 JPEG 尺寸（只读文件头 4KB，不解码）
@return number|nil w, number|nil h
]]
function M.jpeg_size(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read(4096)
    f:close()
    if not data or #data < 4 then return nil end
    if data:byte(1) ~= 0xFF or data:byte(2) ~= 0xD8 then return nil end

    local i = 3
    local n = #data
    while i <= n - 1 do
        if data:byte(i) ~= 0xFF then
            i = i + 1
        else
            local marker = data:byte(i + 1)
            -- 无长度的标记
            if marker == 0xD8 or marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7) then
                i = i + 2
            elseif marker == 0xD9 or marker == 0xDA then
                break                                   -- 图像数据开始，后面不会再有 SOF
            else
                if i + 3 > n then break end
                local seg_len = data:byte(i + 2) * 256 + data:byte(i + 3)
                if seg_len < 2 then break end
                local is_sof = (marker >= 0xC0 and marker <= 0xC3)
                    or (marker >= 0xC5 and marker <= 0xC7)
                    or (marker >= 0xC9 and marker <= 0xCB)
                    or (marker >= 0xCD and marker <= 0xCF)
                if is_sof then
                    if i + 8 > n then break end
                    local h = data:byte(i + 5) * 256 + data:byte(i + 6)
                    local w = data:byte(i + 7) * 256 + data:byte(i + 8)
                    if w > 0 and h > 0 then return w, h end
                    return nil
                end
                i = i + 2 + seg_len
            end
        end
    end
    return nil
end

return M
