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
   未插卡或挂载失败时回退保存到 /ram/photo，避免留底直接丢失。
2. 照片写入放在预览停止之后进行（CPU 已释放），不与 UART2 人脸识别抢 CPU。
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
    -- 同名兜底（正常不会出现，1秒内连拍100张才会回绕）
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
        -- 兜底：开机挂载失败时在任务上下文再试挂一次（save 由 ecface 任务调用，sys.wait 安全）
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

return M
