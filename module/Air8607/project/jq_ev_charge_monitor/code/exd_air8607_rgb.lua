--[[
@module  exd_air8607_rgb
@summary Air8607 10寸 RGB 屏显示IC初始化扩展库（1024x600 免序列）
@version 1.0
@date    2026.10.21
@usage
本文件为 Air8607 10寸 RGB 接口屏（1024x600，免初始化 IC，无寄存器序列）的
显示IC初始化扩展库，参考 script/libs/display/exd_hx8282_rgb.lua 裁剪适配。
核心逻辑：复位 + RGB 时序配置 + 帧缓冲分配。
双后端自动适配：优先 display 核心库，固件不支持时降级 lcd 核心库。

对外接口 3 个：
1、exd_air8607_rgb.setup(params)：显示初始化，返回 ok, info
2、exd_air8607_rgb.info()：查询屏幕信息
3、exd_air8607_rgb.version()：扩展库版本号

注意：本扩展库只负责显示 IC 初始化，不操作供电/背光引脚，不负责触摸初始化。
]]
local M = {}

local VERSION = "202610211000"

-- 显示 IC 固有参数（10寸 1024x600 RGB 免序列面板）
local ic_info = {
    ic = "RGB-1024x600-10i",
    core_model = { display = nil, lcd = nil },  -- 无内置型号，走 custom 免序列路径
    w = 1024, h = 600,
    hbp = 140, hspw = 20, hfp = 160, vbp = 20, vspw = 3, vfp = 12,
    bus_speed = 50000000,
    spi_init = false,  -- 免序列：无 SPI 寄存器初始化
}

-- 板级默认参数（Air8607 10寸工程 config/eng_8607_10i_v0.lua 一致）
M.defaults = {
    pin_rst = 15,        -- LCD 复位脚
    screen_size = 10.0,  -- 物理尺寸 10 英寸
    rotation = 0,
}

local state = { inited = false, backend = nil, params = nil }

local function pick_backend()
    local disp = rawget(_G, "display")
    if disp and disp.init then return "display", disp end
    local lcdx = rawget(_G, "lcd")
    if lcdx and lcdx.init then return "lcd", lcdx end
    return nil, nil
end

local function rot_to_direction(rotation)
    if rotation == 90 then return 1 end
    if rotation == 180 then return 2 end
    if rotation == 270 then return 3 end
    return 0
end

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
    if lib.setupBuff then lib.setupBuff(nil, true) end
    if lib.autoFlush then lib.autoFlush(false) end
    return true, "lcd"
end

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
    for k, v in pairs(M.defaults) do p[k] = v end
    if opts then for k, v in pairs(opts) do p[k] = v end end
    p.rotation = p.rotation or 0
    return p
end

--[[
显示初始化
@param table|nil params 可覆盖 pin_rst/screen_size/rotation/bus_speed 等
@return boolean ok, table|string info 成功返回 {backend,w,h,...}，失败返回错误描述
]]
function M.setup(params)
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

function M.info()
    return state.params
end

function M.version()
    return VERSION
end

return M
