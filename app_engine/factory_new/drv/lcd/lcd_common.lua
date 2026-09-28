--[[
@module  lcd_common
@summary LCD/TP 驱动加载 + AirUI 初始化 + 密度缩放 + 背光控制（所有平台共用）
@version 1.0
@date    2026.05.22
@author  江访

=== 执行流程 ===

require 即执行，以下按顺序发生：

  1. 读 _G.project_config.hw.lcd / hw.tp → 获取驱动 model 名和 params 参数
  2. require(lcd_model) / require(tp_model) → 动态加载对应的 LCD/TP 驱动模块
  3. 构建全局接口：
     _G.lcd_drv.init()           → lcd_model.init(params) → M.airui_init(cfg)  [LCD硬件→AirUI初始化]
     _G.lcd_drv.backlight_on()   → M.backlight_on(cfg)                         [背光PWM开启]
     _G.tp_drv.init()            → tp_model.init(params)                        [触摸芯片初始化]

=== 关键设计决策 ===

1. 驱动去平台化：不硬编码 LCD/TP 型号，根据 project_config.hw.lcd.model 动态 require。
   同款 GT911 触摸芯片在 Air8000W 用 I2C0，在 Air1602 用 I2C1，仅 params 不同

2. AirUI 初始化嵌入 lcd_drv.init()：LCD 硬件初始化成功后立即调 AirUI 初始化 + 字体加载 +
   密度缩放计算，保证 ui_main 拿到 lcd_drv 时 AirUI 已就绪

3. 密度缩放基于 PPI 比值：基准 5寸 480×800 ≈ 187 PPI，实际 PPI = sqrt(w²+h²) / screen_size，
   density_scale = 实际PPI / 基准PPI，最小 1.0（低分辨率屏不做缩小）

4. 双字体路径：有 font.path → 从文件系统加载 .ttf（Air8101），无 path → 使用固件内置字库（其余平台）

5. RGB 帧缓冲：统一走 display.init 分配 FrameBuffer（need_buffer 仅作配置语义保留），
   不再需要 lcd.setupBuff / autoFlush 手动管理
]]

local M = {}

--[[
初始化 AirUI + 字体加载 + 旋转/分辨率计算 + 密度缩放
@param table cfg  config.hw.lcd 配置（含 need_buffer, font, rotation, screen_size, backlight）
@return boolean  true=成功, false(或nil)=airui.init 失败
]]
local function screen_get_size(cfg)
    if display and display.getSize then
        local dw, dh = display.getSize()
        if dw and dw > 0 then
            return dw, dh
        end
    end
    local p = cfg and cfg.params
    return (p and p.w) or 800, (p and p.h) or 480
end

function M.airui_init(cfg)
    -- 获取物理分辨率并初始化 AirUI。真机 AirUI(LUATOS) 依赖 display.init 已注册的 FB。
    local w, h = screen_get_size(cfg)
    local r = airui.init(w, h)
    -- 开启调试模式
    airui.debug(true)
    if not r then
        log.error("lcd_common", "airui.init 失败")
        return r
    end

    -- 字体加载：文件系统 .ttf（Air8101）vs 固件内置字库（其余平台）
    local font_cfg = cfg.font or {}
    if font_cfg.path then
        -- 从文件系统加载 TTF 字体（如 "/MiSans_gb2312.ttf"）
        airui.font_load({
            type       = font_cfg.type or "hzfont",
            path       = font_cfg.path,
            size       = font_cfg.size or 20,
            cache_size = font_cfg.cache_size or 1024,
            antialias  = font_cfg.antialias or 1,
            global     = font_cfg.global,
        })
    else
        -- 使用固件编译时内置的汉字字库（更快，不占文件系统空间）
        airui.font_load({
            type       = font_cfg.type or "hzfont",
            size       = font_cfg.size or 16,
            cache_size = font_cfg.cache_size or 1024,
            antialias  = font_cfg.antialias or 1,
        })
    end

    -- 屏幕旋转（0=正常, 90/180/270 度旋转）
    local rotation = cfg.rotation or 0
    airui.set_rotation(rotation)
    log.info("lcd_common", "airui version: " .. airui.version())

    -- 计算逻辑分辨率（考虑旋转后的宽高交换）
    local rot = airui.get_rotation()
    local pw, ph = screen_get_size(cfg)
    if rot == 0 or rot == 180 then
        _G.screen_w, _G.screen_h = pw, ph -- 正常方向
    else
        _G.screen_h, _G.screen_w = pw, ph -- 90/270度旋转后宽高互换
    end
    _G.is_landscape = (_G.screen_w > _G.screen_h)

    -- 像素密度缩放（基准: 5寸 480×800 ≈ 187 PPI）
    -- 公式: density_scale = 实际PPI / 基准PPI = (sqrt(w²+h²) / screen_size) / 186.6
    -- 结果 ≥1.0，高分辨率屏放大 UI，低分辨率屏保持原始大小
    _G.screen_size = cfg.screen_size or 5.0
    local dp = math.sqrt(_G.screen_w * _G.screen_w + _G.screen_h * _G.screen_h)
    local bp = 186.6                                   -- 基准 PPI（5寸 480×800）
    _G.density_scale = (dp / _G.screen_size) / bp
    _G.density_scale = math.max(1.0, _G.density_scale) -- 低分辨率屏不做缩小
    log.info("lcd_common", string.format("screen %dx%d size=%.1f\" density=%.2f",
        _G.screen_w, _G.screen_h, _G.screen_size, _G.density_scale))

    return true
end

--[[
开启背光
支持两种模式:
  PWM 模式: backlight = { pwm_ch, pwm_freq } — 通过 PWM 通道调节亮度
  GPIO 模式: backlight = { gpio_bl } — 通过 GPIO 直接控制亮灭（不支持调光）
@param table cfg  包含 backlight 配置
]]
function M.backlight_on(cfg)
    local bl = cfg.backlight or {}
    if bl.gpio_bl then
        -- GPIO 背光模式: 设置 GPIO 为输出高电平，不支持亮度调节
        gpio.setup(bl.gpio_bl, 1)
        gpio.set(bl.gpio_bl, 1)
        log.info("lcd_common", "背光已开启 gpio=" .. bl.gpio_bl)
    else
        -- PWM 背光模式（默认）
        local ch = bl.pwm_ch or 0
        local freq = bl.pwm_freq or 1000
        pwm.setup(ch, freq, 100) -- 占空比 100%（最大亮度）
        pwm.start(ch)            -- 启动 PWM 输出
        log.info("lcd_common", "背光已开启 ch=" .. ch .. " freq=" .. freq)
    end
end

-- PC 模拟器跳过 display.init，display.getSize() 会返回 0,0。用 Lua 代理覆盖全局 display：
-- getSize 优先透传 display.getSize()，无效则回退 airui_init 算出的 _G.screen_w/h；
-- 其它字段/方法（init/getFbInfo/...）原样透传给 C 的 display 库。
do
    local orig_display = display
    local proxy = {}
    if orig_display then
        setmetatable(proxy, { __index = orig_display })
    end
    function proxy.getSize(...)
        if orig_display and orig_display.getSize then
            local w, h = orig_display.getSize(...)
            if w and w > 0 then
                return w, h
            end
        end
        if _G.screen_w and _G.screen_w > 0 then
            return _G.screen_w, _G.screen_h
        end
        return 800, 480
    end

    rawset(_G, "display", proxy)
end

-- ==================== 构建全局驱动接口（require 时自动执行） ====================
-- 读取 project_config，动态 require LCD/TP 驱动模块，构建 _G.lcd_drv / _G.tp_drv
-- 后续 ui_main.lua 通过这两个全局对象调用 init() / backlight_on()，不感知底层型号差异
do
    local cfg       = _G.project_config

    -- 动态加载驱动模块：根据配置中的 model 字段 require 对应 .lua 文件
    -- 例：cfg.hw.lcd.model = "lcd_display_rgb" → require "lcd_display_rgb"
    local lcd_model = require(cfg.hw.lcd.model)
    local tp_model  = require(cfg.hw.tp.model)

    -- LCD 驱动全局接口
    _G.lcd_drv      = {
        init = function()
            -- ic_init 已改为返回 custom_cmds 表（由 display.init 内部发送），
            -- 无运行时 lcd.cmd/data 调用，PC 模拟器由 lcd_display_rgb 内部跳过 display.init，
            -- 不再需要旧 lcd 库的命令桩
            local ok = lcd_model.init(cfg.hw.lcd.params)
            if ok then
                -- 硬件就绪后立即初始化 AirUI 渲染引擎（字体、旋转、密度）
                M.airui_init(cfg.hw.lcd)
            end
            return ok
        end,
        backlight_on = function()
            M.backlight_on(cfg.hw.lcd)
        end,
    }

    -- TP 触摸驱动全局接口
    _G.tp_drv       = {
        init = function()
            -- 初始化 GT911 触摸芯片（I2C 配置、中断引脚、分辨率映射）
            return tp_model.init(cfg.hw.tp.params)
        end,
        -- 恢复触摸 I2C 总线配置（exaudio.setup 会用 i2c.setup 重置总线，见 tp_gt911.i2c_restore）
        i2c_restore = function()
            if tp_model.i2c_restore then return tp_model.i2c_restore() end
            return false
        end,
    }
end

return M
