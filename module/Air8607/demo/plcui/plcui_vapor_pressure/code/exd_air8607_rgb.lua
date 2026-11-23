--[[
@module  exd_air8607_rgb
@summary Air8607 10 寸 RGB 屏显示 IC 初始化扩展库（1024x600 免序列）
@version 1.1
@date    2026.11.10
@author  蒋骞
@usage
本文件为 Air8607 10 寸 RGB 接口屏（1024x600，免初始化 IC，无寄存器序列）的
显示 IC 初始化扩展库，参考 script/libs/display/exd_hx8282_rgb.lua 裁剪适配。
核心逻辑：复位 + RGB 时序配置 + 帧缓冲分配。
双后端自动适配：优先 display 核心库，固件不支持时降级 lcd 核心库。

本文件的对外接口有3个：
1、exd_air8607_rgb.setup：显示初始化，返回 ok, info
2、exd_air8607_rgb.info：查询屏幕信息
3、exd_air8607_rgb.version：扩展库版本号

注意：本扩展库只负责显示 IC 初始化，不操作供电/背光引脚，不负责触摸初始化。
]]
local exd_air8607_rgb = {}

local VERSION = "202611101000"

-- 显示 IC 固有参数（10 寸 1024x600 RGB 免序列面板）
local ic_info = {
    ic = "RGB-1024x600-10i",
    core_model = { display = nil, lcd = nil },  -- 无内置型号，走 custom 免序列路径
    w = 1024, h = 600,
    hbp = 140, hspw = 20, hfp = 160, vbp = 20, vspw = 3, vfp = 12,
    bus_speed = 50000000,
    spi_init = false,  -- 免序列：无 SPI 寄存器初始化
}

-- 板级默认参数（与 Air8607 10 寸出厂工程 config/eng_8607_10i_v0.lua 一致）
exd_air8607_rgb.defaults = {
    pin_rst = 15,        -- LCD 复位脚
    screen_size = 10.0,  -- 物理尺寸 10 英寸
    rotation = 0,
}

local state = { inited = false, backend = nil, params = nil }

-- 探测固件里可用的显示库，返回后端名与库表
-- 入参无；返回 backend（display 或 lcd）、lib（库表），都没有时两个都返回 nil
local function pick_backend()
    -- 部分固件的 _G 是 rotable，rawget 会报 bad argument，直接用下标安全取值
    local disp = _G["display"]
    if disp and disp.init then return "display", disp end
    local lcdx = _G["lcd"]
    if lcdx and lcdx.init then return "lcd", lcdx end
    return nil, nil
end

-- 把角度值换算成 lcd 后端的 direction 参数
-- 入参 rotation 为角度（0/90/180/270）；返回 direction（0~3）
local function rot_to_direction(rotation)
    if rotation == 90 then return 1 end
    if rotation == 180 then return 2 end
    if rotation == 270 then return 3 end
    return 0
end

-- 按后端初始化屏幕
-- 入参 params 为合并后的参数表；返回 ok（true/false）, backend 或错误描述
local function do_init(params)
    local backend, lib = pick_backend()
    if not backend then
        log.error("exd_air8607_rgb", "固件缺少 display 与 lcd 库，无法初始化屏幕")
        return false, "no display/lcd lib in firmware"
    end
    if rtos.bsp() == "PC" then
        log.info("exd_air8607_rgb", "PC 模拟器，跳过显示初始化")
        return true, "display"
    end
    if backend == "display" then
        local cfg = {
            id = 0,                       -- airui 固定挂 display id 0
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
    -- lcd 后端降级路径
    local cfg = {
        port = lib["RGB"] or 0x22,
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
    if lib.setupBuff then lib.setupBuff(nil, true) end
    if lib.autoFlush then lib.autoFlush(false) end
    return true, "lcd"
end

-- 合并初始化参数：ic_info 固有参数 -> exd_air8607_rgb.defaults 板级默认值 -> 入参覆盖
-- 入参 opts 为可空的覆盖表；返回合并后的参数表
local function resolve_params(opts)
    local p = {}
    local info = ic_info
    p.w, p.h = info.w, info.h
    p.hbp, p.hspw, p.hfp = info.hbp, info.hspw, info.hfp
    p.vbp, p.vspw, p.vfp = info.vbp, info.vspw, info.vfp
    p.bus_speed = info.bus_speed
    p.spi_init = info.spi_init
    p.screen_size = info.screen_size
    p.core_model = info.core_model
    for k, v in pairs(exd_air8607_rgb.defaults) do p[k] = v end
    if opts then for k, v in pairs(opts) do p[k] = v end end
    p.rotation = p.rotation or 0
    return p
end

--[[
显示初始化；

@api exd_air8607_rgb.setup(params)

@summary 先做参数合并（ic_info + exd_air8607_rgb.defaults + 入参），
再按"固件有 display 走 display、没有降级 lcd"的顺序初始化屏幕；
PC 模拟器上直接返回成功，不碰硬件；
已经初始化过时不再重复初始化，直接返回缓存的屏幕信息

@table or nil params 可覆盖的初始化参数，字段有 pin_rst、screen_size、rotation、bus_speed 等；
可以为空或者nil，为空时使用 exd_air8607_rgb.defaults 与 ic_info 的默认值；

@return boolean 初始化成功返回 true，失败返回 false
@return table or string 成功返回屏幕信息表，字段有 backend（display 或 lcd）、w、h、screen_size、ic；
失败返回错误描述文字

@usage
-- 默认参数初始化 10 寸 1024x600 RGB 屏
local ok, info = exd_air8607_rgb.setup()

-- 指定复位脚
local ok, info = exd_air8607_rgb.setup({pin_rst = 15})
]]
function exd_air8607_rgb.setup(params)
    if state.inited then
        log.warn("exd_air8607_rgb", "重复初始化，直接返回已缓存状态")
        return true, state.params
    end
    local p = resolve_params(params)
    local ok, backend = do_init(p)
    if not ok then return false, backend end
    state.inited = true
    state.backend = backend
    state.params = { backend = backend, w = p.w, h = p.h, screen_size = p.screen_size, ic = ic_info.ic }
    log.info("exd_air8607_rgb", string.format("显示初始化完成 backend=%s %dx%d", backend, p.w, p.h))
    return true, state.params
end

--[[
查询屏幕信息；

@api exd_air8607_rgb.info()

@summary 返回 exd_air8607_rgb.setup 成功时保存的屏幕信息表

@return table or nil 屏幕信息表，字段有 backend、w、h、screen_size、ic；
还没初始化过返回 nil

@usage
local info = exd_air8607_rgb.info()
]]
function exd_air8607_rgb.info()
    return state.params
end

--[[
查询扩展库版本号；

@api exd_air8607_rgb.version()

@summary 返回扩展库版本号，格式为 yyyyMMddHHmm

@return string 扩展库版本号

@usage
log.info("demo", exd_air8607_rgb.version())
]]
function exd_air8607_rgb.version()
    return VERSION
end

return exd_air8607_rgb
