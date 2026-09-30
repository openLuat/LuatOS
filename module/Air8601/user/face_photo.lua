--[[
@module  face_photo
@summary 刷脸拍照留底模块（抓帧 JPEG 存 SD 卡）
@version 1.0
@date    2026.09.18
@author  王城钧
@usage
配合 face_preview.capture() 使用：
local face_preview = require "face_preview"
local ok, data = face_preview.capture(2000)   -- 预览推流中抓一帧 JPEG
if ok then
    require "face_photo".save(data, "deposit") -- → /sd/photo/deposit_20260918_101530_01.jpg
end
说明：
1. SD 卡（/sd）由 main.lua 开机通过 sd_card.init() 挂载（SPI1/CS=GPIO8/SD_EN=GPIO65）；
   未插卡或挂载失败时回退保存到 /ram/photo。
2. 照片写入在预览停止之后进行（此时 CPU 已释放）。
3. 目录可在 config.face.photo 中配置。
]]

local config = require "config"
local sd_card = require "sd_card"

local M = {}

local photo_seq = 0 -- 同一秒内的序号，防文件名重复

-- 生成不重复的文件名：前缀_日期_时间_序号.jpg
local function make_name(dir, prefix)
    photo_seq = (photo_seq % 99) + 1
    local path = string.format("%s/%s_%s_%02d.jpg",
        dir, prefix or "photo", os.date("%Y%m%d_%H%M%S"), photo_seq)
    -- 同名兜底
    local n = 0
    while io.exists(path) and n < 10 do
        n = n + 1
        path = string.format("%s/%s_%s_%02d_%d.jpg",
            dir, prefix or "photo", os.date("%Y%m%d_%H%M%S"), photo_seq, n)
    end
    return path
end

-- 保存 JPEG 照片到存储卡
-- @param data JPEG 字符串（来自 face_preview.capture）
-- @param mode 业务模式："deposit"/"receive"，用作文件名前缀
-- @return ok, path_or_err
function M.save(data, mode)
    if type(data) ~= "string" or #data == 0 then
        return false, "照片数据为空"
    end
    local cfg = config.get("face.photo", {}) or {}
    local dir = cfg.sd_path or "/sd/photo"
    -- SD 卡由 main 开机 sd_card.init() 挂载；此处依据真实挂载状态判断
    if dir:sub(1, 3) == "/sd" and not sd_card.is_mounted() then
        -- 兜底：开机挂载失败时在此再试挂一次（save 由 ecface 任务调用）
        pcall(sd_card.init)
    end
    if dir:sub(1, 3) == "/sd" and not sd_card.is_mounted() then
        log.warn("face_photo", "SD卡未挂载，照片回退保存到 /ram/photo")
        dir = "/ram/photo"
    end
    if not io.exists(dir) then
        pcall(io.mkdir, dir)
    end
    local path = make_name(dir, mode)
    local file = io.open(path, "wb")
    if not file then
        log.error("face_photo", "照片文件创建失败", path)
        return false, "文件创建失败"
    end
    file:write(data)
    file:close()
    log.info("face_photo", "照片已保存", path, #data .. "字节")
    return true, path
end

--[[
清理本地留底照片（策略见 config.face.photo.keep_days / max_count）
· keep_days > 0：删除文件名日期早于"今天 - keep_days"的照片
· max_count > 0：按日期保留最新的 N 张，多余的删掉
文件名形如 deposit_20260927_005053_01.jpg（前缀_日期_时间_序号），日期从文件名解析
由 event_reporter 开机后调用一次（SD 拔出/目录不存在时直接返回，不报错）
@return 删除的张数
]]
function M.cleanup()
    local cfg = config.get("face.photo", {}) or {}
    local keep_days = cfg.keep_days or 0
    local max_count = cfg.max_count or 0
    if keep_days <= 0 and max_count <= 0 then return 0 end

    local dir = cfg.sd_path or "/sd/photo"
    if not io.exists(dir) then return 0 end

    -- 列出目录（io.lsdir 不同固件返回字符串或 {name=} 表，两种都兼容）
    local pok, list = pcall(io.lsdir, dir, 300, 0)
    if not pok or type(list) ~= "table" then return 0 end

    local files = {}   -- { name=, date=YYYYMMDD(数值，0=文件名无法解析) }
    for _, item in ipairs(list) do
        local name = (type(item) == "table" and item.name) or item
        if type(name) == "string" and name:sub(-4):lower() == ".jpg" then
            local d = name:match("_(%d%d%d%d%d%d%d%d)_")
            table.insert(files, { name = name, date = (d and tonumber(d)) or 0 })
        end
    end
    if #files == 0 then return 0 end

    -- 按日期升序（旧的在前）
    table.sort(files, function(a, b) return a.date < b.date end)

    local removed = 0
    local deadline = 0
    if keep_days > 0 then
        local t = os.date("*t", os.time() - keep_days * 86400)
        deadline = t.year * 10000 + t.month * 100 + t.day   -- 形如 20260828
    end

    -- 1) 按时间清理
    local remain = {}
    for _, f in ipairs(files) do
        if deadline > 0 and f.date > 0 and f.date < deadline then
            if pcall(os.remove, dir .. "/" .. f.name) then
                removed = removed + 1
            end
        else
            table.insert(remain, f)
        end
    end

    -- 2) 按张数清理（保留最新的 max_count 张）
    if max_count > 0 and #remain > max_count then
        for i = 1, (#remain - max_count) do
            if pcall(os.remove, dir .. "/" .. remain[i].name) then
                removed = removed + 1
            end
        end
    end

    if removed > 0 then
        log.info("face_photo", "已清理过期留底照片", removed, "张")
    end
    return removed
end

return M
