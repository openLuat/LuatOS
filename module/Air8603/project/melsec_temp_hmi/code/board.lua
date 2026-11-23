--[[
@module  board
@summary 屏 / 触摸 / AirUI 框架初始化（Air8603W1 + 10 寸 1024×600 RGB）

@note
  1. 屏初始化走 display.init("custom", ...)，与出厂工程 drv/lcd/lcd_display_rgb.lua 一致；
     若你的固件版本较早、只有 lcd.init，请按固件实际接口替换 M.lcd() 内的调用。
  2. airui.init 之后必须 airui.font_load({type="hzfont"})，否则所有中文字不显示、
     所有 font_size 失效（详见 M.airui 内注释）。
  3. 触摸的驱动名是 "gt911"（不是 "tp_gt911"），且必须自己先 i2c.setup
     （详见 M.touch 内注释）。
]]

local cfg = require("config")

local M = {}

local IS_PC = (rtos and rtos.bsp and rtos.bsp() == "PC")

-- 只有在协程里才能 sys.wait；不在协程里就跳过延时，不阻塞
local function pause(ms)
    if coroutine and coroutine.isyieldable and coroutine.isyieldable() then
        pcall(sys.wait, ms)
    end
end

--[[ 板级上电时序
     必须在 display.init 和 uart.setup 之前跑完：
       · 屏和触摸都挂在这些电源域上；
       · 485 收发芯片由 GPIO64 单独供电，缺了它串口能开但总线上没波形。
     上电前先把背光压到 0 占空比，避免开机闪白。]]
function M.power_on()
    if IS_PC then return end
    if pwm and pwm.setup then
        pcall(pwm.setup, cfg.lcd.bl_pwm_ch, cfg.lcd.bl_freq, 0)
        pcall(pwm.start, cfg.lcd.bl_pwm_ch)
    end
    for _, step in ipairs(cfg.board.power_on) do
        pcall(gpio.setup, step[1], step[2])
        pcall(gpio.set, step[1], step[2])
        if step[3] then pause(step[3]) end
    end
end

function M.lcd()
    -- PC 模拟器：display.init 会另开一个名为 "custom" 的 SDL 窗口，
    -- 而 AirUI 自己也开窗，会出现两个窗口。与出厂驱动一致，PC 下跳过。
    if rtos and rtos.bsp and rtos.bsp() == "PC" then
        log.info("board", "PC 模拟器：跳过 display.init（窗口由 AirUI 创建）")
        return true
    end

    if not display or not display.init then
        log.error("board", "display 模块不存在，请烧带 LUAT_USE_DISPLAY 的固件")
        return false
    end

    local p = cfg.lcd
    local ok, err = display.init("custom", {
        id        = 0,
        interface = p.interface,
        w         = p.w,
        h         = p.h,
        hbp       = p.hbp,
        hspw      = p.hspw,
        hfp       = p.hfp,
        vbp       = p.vbp,
        vspw      = p.vspw,
        vfp       = p.vfp,
        pclk_hz   = p.pclk_hz,
        pin_rst   = p.pin_rst,
    })
    log.info("board", "display.init", ok, err)
    return ok and true or false
end

function M.backlight(on)
    if rtos and rtos.bsp and rtos.bsp() == "PC" then return true end
    if not pwm or not pwm.setup then
        log.warn("board", "无 pwm 库，跳过背光")
        return false
    end
    local p = cfg.lcd
    local duty = on and (p.bl_duty or 90) or 0
    local ok, err = pcall(function()
        pwm.setup(p.bl_pwm_ch, p.bl_freq, duty)
        pwm.start(p.bl_pwm_ch)
    end)
    if not ok then
        -- 常见原因：该通道在本固件未开放，或引脚复用未在 LuatIO 里配置。
        -- 不影响其它功能；若屏常暗，需按固件手册配置 PWM3 的引脚复用。
        log.warn("board", "背光 PWM 设置失败（通道 " .. p.bl_pwm_ch .. "）", err)
    else
        log.info("board", "backlight on", p.bl_pwm_ch, duty)
    end
    return ok
end

function M.airui()
    if not airui then
        log.error("board", "airui 模块不存在，请确认固件含 AirUI")
        return false
    end
    local ok, err = airui.init(cfg.screen.w, cfg.screen.h, airui.COLOR_FORMAT_RGB565)
    if ok == false then
        log.error("board", "airui.init 失败", err)
        return false
    end

    --[[中文字库：这一步不能省。
    label 的 font_size 走 airui_text_font_apply_hzfont()，该函数第一句就是
      if (luat_hzfont_get_state() != LUAT_HZFONT_STATE_READY) { 只打一条 warning; return NOT_SUPPORTED; }
    也就是说没有 font_load 时：
      · font_size 全部被拒绝，所有文字都是 14 号默认字体
      · 默认字体没有中文字形，所有汉字显示为空白
    这是上一版界面"看起来很差"的头号原因。hzfont 的 path 传 nil 用内置字库，
    各字号在首次使用时按需实例化（见 airui_font_hzfont_get_size）。]]
    if airui.font_load then
        local okf, errf = pcall(airui.font_load, {
            type       = "hzfont",
            size       = 16,      -- 默认字号
            -- cache_size 只接受 {128, 256, 512, 1024, 2048}（luat_hzfont.c 的
            -- HZFONT_CACHE_ALLOWED 白名单），写别的值会被静默换成 256 并打一条 warning。
            -- 本界面有 11 档字号、几百个汉字，256 会不断淘汰重建，取 1024。
            cache_size = 1024,
            antialias  = 1,       -- 2x2 抗锯齿
            global     = true,
        })
        log.info("board", "font_load(hzfont)", okf, errf)
    else
        log.error("board", "固件无 airui.font_load，中文无法显示")
    end

    if airui.set_rotation then pcall(airui.set_rotation, 0) end
    log.info("board", "airui.init ok", airui.version and airui.version() or "")
    return true
end

--[[ GT911 电容触摸：I2C 初始化 → tp.init → 绑定到 airui
     三个必须对齐的点（都是实测踩出来的）：
       1. 驱动名是 "gt911"，不是 "tp_gt911"。写错会得到
          E/tp tp_name:tp_gt911 not found!!! 然后 tp.init 返回 nil，
          界面照常显示但点不动，很容易误判成硬件坏。
       2. i2c 必须由脚本自己 setup，tp.init 不会帮你开总线。
          第三参 true = 轮询模式：触摸坐标在 TP 中断里突发读，
          中断驱动的 I2C 与嵌套中断打架时会"只有触摸时"报 I2C 错误。
       3. w/h 必须给真值。缺了会被 input 适配器以 EINVAL 静默拒绝，
          现象是"能读到 product id 但初始化失败"。
     另外：不要自己在脚本里拉 RST。内核 tp 驱动的 tp_gt9xx_gpio_init 会做
     RST 低 → INT 低锁地址 → RST 高 → 55ms 的完整复位，脚本再拉一次
     是双复位，会让地址识别失败。]]
local tp_dev = nil

function M.touch()
    if tp_dev then return tp_dev end          -- 内核 tp 库一次上电只接受一次 init
    if IS_PC then
        log.info("board", "PC 模拟器：跳过触摸（用鼠标替代）")
        return true
    end
    if not tp or not tp.init then
        log.error("board", "固件没有 tp 库")
        return false
    end

    local p = cfg.tp
    local ok_i2c = pcall(i2c.setup, p.port, 0, true)      -- 0 = 默认速率，true = 轮询
    if not ok_i2c then
        ok_i2c = pcall(i2c.setup, p.port, i2c.SLOW)        -- 老固件不认第三参
    end
    if not ok_i2c then
        log.error("board", "i2c.setup 失败, port", p.port)
        return false
    end

    local ok_tp, dev = pcall(tp.init, p.model, {
        port     = p.port,
        pin_rst  = p.pin_rst,
        pin_int  = p.pin_int,
        int_type = tp.FALLING,
        w        = p.w,
        h        = p.h,
    })
    if not ok_tp or not dev then
        -- 失败时扫一遍 I2C 总线：GT911 在 0x5D 或 0x14。
        -- 一个地址都扫不到 = 供电/排线问题；扫到但 tp.init 失败 = 驱动名或 w/h 问题。
        local addrs = {}
        if i2c.scan then
            local ok_s, r = pcall(i2c.scan, p.port)
            if ok_s and type(r) == "table" then
                for _, a in ipairs(r) do addrs[#addrs + 1] = string.format("0x%02X", a) end
            end
        end
        log.error("board", "tp.init 失败，检查 config.tp：model=", p.model,
            "rst=", p.pin_rst, "int=", p.pin_int, "w/h=", p.w, p.h,
            "I2C 扫描:", (#addrs > 0) and table.concat(addrs, ",") or "无设备", dev)
        return false
    end

    tp_dev = dev
    if airui and airui.device_bind_touch then
        local okb, errb = pcall(airui.device_bind_touch, dev)
        log.info("board", "触摸已绑定 airui", okb, errb)
    else
        log.warn("board", "airui 未就绪，触摸没有绑定，界面会点不动")
    end
    return dev
end

-- 返回 true 表示屏可用
function M.init()
    M.power_on()                 -- 电源域先起来，屏和 485 都依赖它
    local ok = M.lcd()
    if not ok then return false end
    if not M.airui() then return false end
    M.touch()
    M.backlight(true)
    return true
end

return M
