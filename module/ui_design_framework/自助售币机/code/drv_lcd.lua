--[[
  drv_lcd.lua  1024x600 RGB 屏显示初始化（Air8607 / Air1603 平台）

  对外接口：setup(params) / info() / version()
  RGB 时序由 main.lua 按 app_config.HW.screen 显式传入（与出厂固件一致）。
  固件若有 display 库走 display，否则退回 lcd。PC 模拟器直接跳过。
]]

local M = {}

local VERSION = "202611200000"

local ic_info = {
  ic = "RGB-1024x600",
  w = 1024, h = 600,
  hbp = 140, hspw = 20, hfp = 160,
  vbp = 20,  vspw = 3,  vfp = 12,
  bus_speed = 50000000,
}

M.defaults = { pin_rst = 15, rotation = 0 }

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
    log.error("drv_lcd", "固件缺少 display 与 lcd 库")
    return false, "no display/lcd lib in firmware"
  end
  if rtos.bsp() == "PC" then
    log.info("drv_lcd", "PC 模拟器，跳过显示初始化")
    return true, "display"
  end
  if backend == "display" then
    local cfg = {
      id = 0, interface = "rgb",
      w = params.w, h = params.h,
      hbp = params.hbp, hspw = params.hspw, hfp = params.hfp,
      vbp = params.vbp, vspw = params.vspw, vfp = params.vfp,
      pclk_hz = params.bus_speed,
      pin_rst = params.pin_rst,
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
    bus_speed = params.bus_speed,
    pin_rst = params.pin_rst,
    direction = rot_to_direction(params.rotation),
  }
  local ok = lib.init("custom", cfg)
  if not ok then return false, "lcd.init 失败" end
  if lib.setupBuff then lib.setupBuff(nil, true) end
  if lib.autoFlush then lib.autoFlush(false) end
  return true, "lcd"
end

local function resolve_params(opts)
  local p = { rotation = 0 }
  for k, v in pairs(ic_info) do p[k] = v end
  for k, v in pairs(M.defaults) do p[k] = v end
  if opts then for k, v in pairs(opts) do p[k] = v end end
  return p
end

function M.setup(params)
  if state.inited then return true, state.backend end
  local p = resolve_params(params)
  local ok, backend = do_init(p)
  if ok then
    state.inited, state.backend, state.params = true, backend, p
    log.info("drv_lcd", "显示初始化完成", p.w .. "x" .. p.h, backend)
  end
  return ok, backend
end

function M.info() return state.params end
function M.version() return VERSION end

return M
