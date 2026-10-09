--[[
@module  exd_ek79001_rgb
@summary EK73215+EK79001 显示IC初始化扩展库（RGB 接口）
@version 1.0
@date    2026.10.08
@author  江访
@usage
本文件为 EK73215+EK79001 显示IC组合（RGB 接口）的显示IC初始化扩展库，单文件独立，拷本文件一个即可在工程中使用。
板级参数 pin_rst 必传；屏幕参数不传时使用内置默认值，传入则覆盖默认值。

本文件的对外接口有3个：
1、exd_ek79001_rgb.setup(params)：显示初始化
2、exd_ek79001_rgb.info()：查询屏幕信息
3、exd_ek79001_rgb.version()：扩展库版本号查询

-- 版本更新说明
-- 版本号：202610091000
-- 1、更新时间：2026-10-09
-- 2、更新内容
--   - 扩展库更名为 exd_ek79001_rgb.lua（原 exd_ek73215&79001rgb.lua），require 名称同步变更
-- 版本号：202610081000（初版）
-- 1、更新时间：2026-10-08
-- 2、更新内容
--   - 初版：免初始化 IC 组合，复位 + RGB 时序配置 + 双后端适配
]]
local M = {}

-- 扩展库版本号，格式 yyyymmddhhmm
local VERSION = "202610091000"

-- 显示 IC 固有参数（分辨率、时序、总线时钟）
local ic_info = {
    ic = "EK73215+EK79001",
    w = 1024, h = 600,
    hbp = 140, hspw = 20, hfp = 160, vbp = 20, vspw = 3, vfp = 12,
    bus_speed = 50000000,
}

-- 默认显示参数（pin_rst 按板级必传）
M.defaults = {
    screen_size = 7.0,
}

-- 运行状态缓存
local state = {
    inited = false,
    backend = nil,
    params = nil,
    info = nil,
}

-- 探测可用的显示后端
local function pick_backend()
    local disp = rawget(_G, "display")
    if disp and disp.init then
        return "display", disp
    end
    local lcdx = rawget(_G, "lcd")
    if lcdx and lcdx.init then
        return "lcd", lcdx
    end
    return nil, nil
end

-- 旋转角度转换为 lcd 库的 direction 值
local function rot_to_direction(rotation)
    if rotation == 90 then return 1 end
    if rotation == 180 then return 2 end
    if rotation == 270 then return 3 end
    return 0
end

-- 显示初始化（复位 + RGB 时序配置，双后端选择）
local function do_init(params)
    local backend, lib = pick_backend()
    if not backend then
        log.error("exd_ek79001_rgb", "固件缺少 display 与 lcd 库，无法初始化屏幕")
        return false, "no display/lcd lib in firmware"
    end
    if rtos.bsp() == "PC" then
        log.info("exd_ek79001_rgb", "PC 模拟器，跳过显示初始化")
        return true, "display"
    end
    if backend == "display" then
        local cfg = {
            id = 0,
            interface = "rgb",
            w = params.w, h = params.h,
            hbp = params.hbp, hspw = params.hspw, hfp = params.hfp,
            vbp = params.vbp, vspw = params.vspw, vfp = params.vfp,
            pclk_hz = params.bus_speed,
            pin_rst = params.pin_rst,
        }
        local ok, err = lib.init("custom", cfg)
        if not ok then
            return false, "display.init 失败: " .. tostring(err)
        end
        return true, "display"
    end
    local cfg = {
        port = rawget(lib, "RGB") or 0x22,
        w = params.w, h = params.h,
        hbp = params.hbp, hspw = params.hspw, hfp = params.hfp,
        vbp = params.vbp, vspw = params.vspw, vfp = params.vfp,
        bus_speed = params.bus_speed,
        pin_rst = params.pin_rst,
        direction = rot_to_direction(params.rotation),
    }
    local ok = lib.init("custom", cfg)
    if not ok then
        return false, "lcd.init 失败"
    end
    if lib.setupBuff then
        lib.setupBuff(nil, true)
    end
    if lib.autoFlush then
        lib.autoFlush(false)
    end
    if lib.user_done then
        lib.user_done()
    end
    return true, "lcd"
end

-- 合并参数：IC 固有 → 参考面板默认 → 用户传入
local function resolve_params(opts)
    local p = {}
    local info = ic_info
    p.w, p.h = info.w, info.h
    p.hbp, p.hspw, p.hfp = info.hbp, info.hspw, info.hfp
    p.vbp, p.vspw, p.vfp = info.vbp, info.vspw, info.vfp
    p.bus_speed = info.bus_speed
    for k, v in pairs(M.defaults) do
        p[k] = v
    end
    if opts then
        for k, v in pairs(opts) do
            p[k] = v
        end
    end
    p.rotation = p.rotation or 0
    return p
end

--[[
显示初始化；
屏幕参数不传时使用内置默认值，传入则覆盖默认值；板级参数 pin_rst 必传；

@api exd_ek79001_rgb.setup(params)

@table
params
参数含义：用户参数表，屏幕参数可选（覆盖默认值），pin_rst 必传
数据类型：table
是否必选：否
注意事项：完整参数说明见本扩展库文档（exd_ek79001_rgb.md）
参数示例：{ pin_rst = 20 }

@return boolean, table or string
成功返回 true 与屏幕信息表 {ic, backend, w, h, screen_size, rotation}，失败返回 false 与错误信息字符串

@usage
-- 基础用法：只传板级复位脚
local ok, info = exd_ek79001_rgb.setup({ pin_rst = 20 })
]]
function M.setup(params)
    if state.inited then
        log.warn("exd_ek79001_rgb", "已初始化过，忽略重复 setup")
        return true, state.info
    end
    local merged = resolve_params(params)
    if not merged.pin_rst then
        log.error("exd_ek79001_rgb", "缺少 pin_rst 参数，板级 LCD 复位引脚必传")
        return false, "pin_rst 必传：请传入板级 LCD 复位引脚编号，例如 setup({ pin_rst = 20 })"
    end
    local ok, backend = do_init(merged)
    if not ok then
        return false, backend
    end
    state.inited = true
    state.backend = backend
    state.params = merged
    local info = {
        ic = ic_info.ic,
        backend = backend,
        w = merged.w, h = merged.h,
        screen_size = merged.screen_size,
        rotation = merged.rotation,
    }
    state.info = info
    log.info("exd_ek79001_rgb", "显示初始化完成", info.ic, info.w, info.h, info.backend)
    return true, info
end

--[[
查询屏幕信息；setup 前返回内置默认值，setup 后返回实际初始化值；

@api exd_ek79001_rgb.info()

@return table
含义说明：屏幕信息表
数据类型：table
取值范围：{ ic, backend, w, h, screen_size, rotation }
返回示例：{ ic = "EK73215+EK79001", backend = "display", w = 1024, h = 600, screen_size = 7.0, rotation = 0 }

@usage
local info = exd_ek79001_rgb.info()
log.info("exd_ek79001_rgb", info.w, info.h)
]]
function M.info()
    if state.inited then
        return state.info
    end
    local p = resolve_params(nil)
    return {
        ic = ic_info.ic,
        backend = nil,
        w = p.w, h = p.h,
        screen_size = p.screen_size,
        rotation = p.rotation,
    }
end

--[[
扩展库版本号查询；

@api exd_ek79001_rgb.version()

@return string
含义说明：扩展库版本号
数据类型：string
取值范围：格式为 yyyymmddhhmm 的版本号字符串
返回示例："202610081000"

@usage
local ver = exd_ek79001_rgb.version()
]]
function M.version()
    return VERSION
end

return M
