--[[
@module  wallpaper
@summary 桌面壁纸加载：JPEG 文件头校验 + 候选查找 + 创建背景图层
@author  王世豪
@version 1.0
@date    2026.10.26

=== 只允许 JPEG ===
真机解码全屏大图的内存开销很大，只支持 baseline JPEG，尺寸建议正好 1024x600。
SD 卡上若有「把 PNG 改名成 .jpg」的伪文件，交给 airui 会解码失败，
所以加载前先自己校验文件头两个字节必须是 FF D8。

=== 图层顺序 ===
必须在建 UI 之前调用：LVGL 里后创建的对象在上层，晚于 UI 创建会盖住时钟文字。
任何失败都只是没有壁纸（退回渐变背景），不影响时钟使用。
]]
local conf = require "conf"
local sd_card = require "sd_card"

local M = {}

local SW, SH = conf.W, conf.H

--[[校验文件头是真的 JPEG（FF D8）]]
local function is_jpeg(path)
    local f = io.open(path, "rb")
    if not f then
        log.warn("wallpaper", "文件打不开", tostring(path))
        return false
    end
    local head = f:read(2)
    f:close()
    if not head or #head < 2 then
        log.warn("wallpaper", "文件为空/太短", tostring(path))
        return false
    end
    local ok = (head:byte(1) == 0xFF and head:byte(2) == 0xD8)
    if not ok then
        log.warn("wallpaper", "不是 JPEG（文件头不是 FF D8）", tostring(path),
            string.format("%02X %02X", head:byte(1), head:byte(2)))
    end
    return ok
end

--[[按候选顺序找壁纸，每一步都打印，方便定位「为什么没显示」]]
local function find_wallpaper()
    local cands = {}
    if conf.wallpaper.file then cands[#cands + 1] = conf.wallpaper.file end
    for _, p in ipairs(conf.wallpaper.fallback or {}) do cands[#cands + 1] = p end

    log.info("wallpaper", "候选列表", table.concat(cands, " | "))
    for _, p in ipairs(cands) do
        if not sd_card.exists(p) then
            log.info("wallpaper", "候选不存在", p)
        else
            local size = -1
            local f = io.open(p, "rb")
            if f then
                local ok_s, sz = pcall(function() return f:seek("end") end)
                if ok_s and type(sz) == "number" then size = sz end
                f:close()
            end
            log.info("wallpaper", "候选存在", p, "大小", size)
            if is_jpeg(p) then
                log.info("wallpaper", "命中", p)
                return p
            end
        end
    end
    log.warn("wallpaper", "没有任何候选是合法 JPEG 壁纸")
    return nil
end

--[[加载壁纸（同步）
@param parent 背景容器（根页面）
@return boolean ok
]]
function M.load(parent)
    if not conf.wallpaper.enabled then return false end

    if not sd_card.mount() then
        log.warn("wallpaper", "SD 卡不可用，跳过壁纸（用渐变背景）")
        return false
    end

    local path = find_wallpaper()
    if not path then
        log.warn("wallpaper", "没有可用壁纸，使用渐变背景")
        return false
    end

    local ok, ret = pcall(function()
        return airui.image({
            parent = parent, x = 0, y = 0, w = SW, h = SH,
            src = path, fit = "cover",
        })
    end)
    if ok and ret then
        log.info("wallpaper", "已加载", path)
        return true
    end
    log.warn("wallpaper", "控件创建失败", path, tostring(ret))
    return false
end

return M
