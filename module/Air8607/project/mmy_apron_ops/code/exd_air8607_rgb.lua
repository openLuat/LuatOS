--[[
@module  exd_air8607_rgb
@summary Air8607 10寸 RGB 屏显示IC初始化扩展库（1024x600 免序列）
@version 1.0
@date    2026.10.24

与 factory 及 agri_greenhouse 的 exd_air8607_rgb.lua 保持一致。
只负责显示 IC 初始化，不操作供电/背光/触摸。
]]
local M = {}

local VERSION = "202610240300"

local ic_info = {
    ic = "RGB-1024x600-10i",
    core_model = { display = nil, lcd = nil },
    w = 1024, h = 600,
    hbp = 140, hspw = 20, hfp = 160, vbp = 20, vspw = 3, vfp = 12,
    bus_speed = 50000000,
    spi_init = false,
}

M.defaults = { pin_rst = 15, screen_size = 10.0, rotation = 0 }

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
            id = 0, interface = "rgb",
            w = params.w, h = params.h,
            hbp = params.hbp, hspw = params.hspw, hfp = params.hfp,
            vbp = params.vbp, vspw = params.vspw, vfp = params.vfp,
            pclk_hz = params.bus_speed, pin_rst = params.pin_rst,
        }
        local ok, err = lib.init("custom", cfg)
        if not ok then return false, "display.init 失败: " .. tostring(err) end
        return true, "display"
    end

    local cfg = {
        port = rawget(lib, "RGB") or 0x22,
        w = params.w, h = params.h,
        hbp = params.hbp, hspw = params.hspw, hfp = params.hfp,
        vbp = params.vbp, vspw = params.vspw, vfp = params.vfp,
        bus_speed = params.bus_speed, pin_rst = params.pin_rst,
        direction = rot_to_direction(params.rotation),
    }
    local ok = lib.init("custom", cfg)
    if not ok then return false, "lcd.init 失败" end
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

function M.setup(params)
    if state.inited then return true, state.params end
    local p = resolve_params(params)
    local ok, backend = do_init(p)
    if not ok then return false, backend end
    state.inited = true
    state.backend = backend
    state.params = { backend = backend, w = p.w, h = p.h, screen_size = p.screen_size, ic = ic_info.ic }
    log.info("exd_air8607_rgb", string.format("显示初始化完成 backend=%s %dx%d", backend, p.w, p.h))
    return true, state.params
end

function M.info() return state.params end
function M.version() return VERSION end

return M
