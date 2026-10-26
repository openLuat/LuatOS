--[[
@module  hzv_hw
@summary HZV 视频播放 demo 的硬件环境配置模块（按 HARDWARE_ENV 区分板型）
@version 1.0
@date    2026.10.26
@author  拓毅恒
@usage
本文件是 play_hzv demo 中唯一的板型差异集中点，作用是把一个 HARDWARE_ENV 字符串
映射成一份完整的硬件参数表；业务模块（lcd_app / hzv_ui / sd_app / hzv_player）只读参数、
不判断板型，新增板型时只需要在本文件的 board_cfg 表里加一条记录。

参数表的取值原则（重要）：
本文件的每一行参数都与对应型号出厂固件的配置保持一致，不自行推测；
每条记录上方的注释写明了对应的配置文件，两者不一致时以出厂固件为准：
  - Air8601  → module/Air8601/project/factory/config/eng_8601_7i_4g.lua（与 _wifi 硬件一致）
  - Air8602  → module/Air8602/project/factory/config/eng_8602_9i_4g.lua（与 _wifi 硬件一致）
  - Air8603  → module/Air1601_Air1602_Air1603_Air1604_Air1605/project/factory/config/eng_8603m_10i_v0.lua
  - Air8605  → module/Air8605/project/factory/config/eng_8605_10i_4g.lua
  - Air8607  → module/Air8607/project/factory/config/eng_8607_10i_v0.lua
  - Air8607A → module/Air8607/project/factory/config/eng_8607a_10i_v0.lua
  - Air1601 V1.1 EVB → .../project/Air1601_dev_board_V1.1/factory/config/evb_1601_7i_v11.lua
  - Air1601/Air1602 V1.2 EVB → .../project/Air1602_dev_board_V1.2/factory/config/evb_1602_7i_v12.lua

参数表分五组：
1、lcd  ：屏幕分辨率、RGB 时序、复位脚、供电使能脚、背光（GPIO 直拉 或 PWM 调光）；
2、audio：功放 PA 使能脚和有效电平（HZV 带音轨，PA 不使能就只有画面没有声音）；
3、tp   ：触摸屏（GT911）的 I2C 端口与复位/中断脚，界面选片靠它，nil 表示该板不接触摸；
4、sd   ：TF 卡 SPI 总线、片选、供电使能脚、挂载时钟（用于播放 /sd 下的大文件 HZV）；
5、name ：板型中文名，只用于日志打印。

对外接口：
1、hzv_hw.get()      ：返回当前 HARDWARE_ENV 对应的参数表，未知型号回退默认板型；
2、hzv_hw.pa_set(on) ：按板型打开/关闭功放 PA，on=true 打开，on=false 关闭；
3、hzv_hw.name()     ：返回当前板型中文名，方便日志打印；
4、hzv_hw.has_sd()   ：查询当前板型是否带 SD 卡；
5、hzv_hw.has_tp()   ：查询当前板型是否配置了触摸屏（决定进选片界面还是自动演示）。

切换板型：
1、直接修改本文件顶部的 HARDWARE_ENV；
2、或者先在 main.lua 里给全局 HARDWARE_ENV 赋值，再 require 业务模块
   （本文件优先采用外部已经赋好的值，不会被覆盖）。
详细说明见本目录下的 readme.md 文件。
]]

-- 硬件环境配置说明
-- 本 Demo 支持以下硬件环境，请根据实际使用情况修改 HARDWARE_ENV 变量：
--   "8601_DEV_BOARD"   - Air8601 引擎开发板(7寸 1024x600)                ← 默认
--   "8602_DEV_BOARD"   - Air8602 工业模组(7/9/10寸，均为 1024x600)
--   "8603_DEV_BOARD"   - Air8603M/Air8603W 引擎(10寸 1024x600)
--   "8605_DEV_BOARD"   - Air8605 引擎(10寸 1024x600，音频走 Air1103)
--   "8607_DEV_BOARD"   - Air8607 引擎(10寸 1024x600，Air1603 主控)
--   "8607A_DEV_BOARD"  - Air8607A 引擎(10寸 1024x600，无 SD 卡)
--   "1601_EVB_V11"     - Air1601 V1.1 EVB(7寸 1024x600，GPIO2 直驱背光、无 PWM)
--   "1601_EVB_V12"     - Air1601/Air1602 V1.2 EVB(7寸 1024x600，LCD_EN=GPIO57)
-- 详细说明（引脚依据、待核对项）见本目录下的 readme.md 文件
HARDWARE_ENV = HARDWARE_ENV or "8601_DEV_BOARD"   -- Air8601 引擎开发板(默认)

-- 默认板型：HARDWARE_ENV 填了未知型号时回退到这里
local BOARD_DEFAULT = "8601_DEV_BOARD"

-- 各硬件环境的完整硬件参数表
-- 字段说明：
--   lcd.w / lcd.h        ：屏幕分辨率
--   lcd.pin_rst          ：LCD 复位/显示使能脚（display.init 内部做复位时序）
--   lcd.pin_pwr          ：LCD 供电使能脚，nil 表示该板无此脚（不需要常拉高）
--   lcd.pin_bl           ：背光使能脚（GPIO 直驱，不支持 PWM 调光），nil 表示该板不用 GPIO 背光
--   lcd.backlight        ：PWM 背光参数，{pwm_ch=通道, pwm_freq=频率, level=初始占空比0~100}；
--                          nil 表示该板不是 PWM 调光
--   lcd.hbp/hspw/hfp     ：RGB 水平后沿/同步脉宽/前沿
--   lcd.vbp/vspw/vfp     ：RGB 垂直后沿/同步脉宽/前沿
--   lcd.pclk_hz          ：RGB 总线时钟
--   audio.pa_pin         ：功放使能脚；nil 表示该板没有可控 PA（例如音频走 Air1103 整芯片）
--   audio.pa_on_level    ：PA 有效电平，1=高电平使能，0=低电平使能
--   tp                   ：触摸屏参数，nil 表示该板不接触摸屏（进自动演示模式）
--   tp.model/port        ：触摸 IC 型号、I2C 端口号
--   tp.pin_rst / pin_int ：触摸复位脚 / 中断脚；pin_rst=nil 表示出厂固件不传（部分板传了会锁死 INT）
--   tp.pins              ：I2C 功能复用表，{ {pin=脚号, func="功能名"}, ... }
--   sd.spi_id / pin_cs   ：TF 卡所在 SPI 总线号、片选脚；sd 为 nil 表示该板没有 SD 卡
--   sd.pin_sd_en         ：TF 卡供电使能脚，nil 表示供电直连无需控制
--   sd.speed             ：TF 卡挂载后的 SPI 时钟（与出厂固件的 storage.sd_card.speed 一致）
local board_cfg = {
    -- ============ Air8601 引擎开发板（默认板型）============
    -- 来源：module/Air8601/project/factory/config/eng_8601_7i_4g.lua
    --   lcd   ：pin_rst=15、背光 PWM3、时序 140/20/160/20/3/12 @50MHz（无 LCD_EN）
    --   audio ：pa_ctrl=GPIO74、pa_on_level=0（AUDIOPA_EN 低电平使能）
    --   tp    ：GT911 走 I2C1（PIN33/PIN32 复用）、TP_RST=GPIO56、TP_INT=GPIO51
    --   sd    ：SPI1 CS=GPIO8、SD_EN=GPIO65、speed=20MHz
    ["8601_DEV_BOARD"] = {
        name = "Air8601 引擎开发板(7寸 1024x600)",
        lcd  = {
            w = 1024, h = 600,
            pin_rst = 15,     -- LCD_DISP，显示使能/复位
            pin_pwr = nil,    -- 出厂固件无 LCD_EN
            backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 },  -- PWM3 调光
            hbp = 140, hspw = 20, hfp = 160,
            vbp = 20,  vspw = 3,  vfp = 12,
            pclk_hz = 50 * 1000 * 1000,
        },
        audio = { pa_pin = 74, pa_on_level = 0 },   -- AUDIOPA_EN 低电平使能
        tp    = {
            model = "gt911", port = 1,
            pin_rst = 56, pin_int = 51,
            pins = {
                { pin = 33, func = "I2C1_CLK" },
                { pin = 32, func = "I2C1_SDA" },
            },
        },
        sd    = { spi_id = 1, pin_cs = 8, pin_sd_en = 65, speed = 20000000 },
    },

    -- ============ Air8602 工业模组（寄存柜整机，7/9/10 寸）============
    -- 来源：module/Air8602/project/factory/config/eng_8602_9i_4g.lua
    --   lcd   ：pin_rst=15、背光 PWM3、时序同 7 寸 HX8282、无 LCD_EN
    --   audio ：pa_ctrl=GPIO73、pa_on_level=0（低电平使能）
    --   tp    ：TP_RST=GPIO72、TP_INT=GPIO51、I2C1 复用 PIN33/PIN32
    --   sd    ：SPI1、SD_EN=GPIO74、speed=20MHz
    -- 【待核对】出厂固件里 SD 片选写的是 pin_cs=38（注释为"SPI1_CS0 = PIN38（GPIO 待确认）"，
    --   38 是排针 PIN 号而不是 GPIO 号）。同族 8601/8605/8607 出厂固件都写作 "PIN38 = GPIO8"，
    --   故这里按 GPIO8 填；上板若识别不到卡，优先把 pin_cs 改成其它候选值试。
    ["8602_DEV_BOARD"] = {
        name = "Air8602 工业模组(7/9/10寸 1024x600)",
        lcd  = {
            w = 1024, h = 600,
            pin_rst = 15,
            pin_pwr = nil,
            backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 },
            hbp = 140, hspw = 20, hfp = 160,
            vbp = 20,  vspw = 3,  vfp = 12,
            pclk_hz = 50 * 1000 * 1000,
        },
        audio = { pa_pin = 73, pa_on_level = 0 },   -- 低电平使能
        tp    = {
            model = "gt911", port = 1,
            pin_rst = 72, pin_int = 51,
            pins = {
                { pin = 33, func = "I2C1_CLK" },
                { pin = 32, func = "I2C1_SDA" },
            },
        },
        sd    = { spi_id = 1, pin_cs = 8, pin_sd_en = 74, speed = 20000000 },
    },

    -- ============ Air8603M / Air8603W 引擎（10 寸）============
    -- 来源：project/factory/config/eng_8603m_10i_v0.lua（module 下没有独立 Air8603 目录）
    --   lcd   ：pin_rst=15、背光 PWM3、时序 140/20/160/20/3/12 @50MHz
    --   audio ：走 Air1103 语音芯片（UART），出厂固件**不写 pa_ctrl**；
    --           GPIO73 = AUDIOPAEN 是 Air1103 的供电脚，power_on 里拉高常供电
    --   tp    ：TP_RST=GPIO72、TP_INT=GPIO51（该配置的 pins 复用表整段被注释，不重复复用）
    --   sd    ：SPI1 CS=GPIO8、SD_EN=GPIO74、speed=20MHz
    ["8603_DEV_BOARD"] = {
        name = "Air8603M/W 引擎(10寸 1024x600)",
        lcd  = {
            w = 1024, h = 600,
            pin_rst = 15,
            pin_pwr = nil,
            backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 },
            hbp = 140, hspw = 20, hfp = 160,
            vbp = 20,  vspw = 3,  vfp = 12,
            pclk_hz = 50 * 1000 * 1000,
        },
        audio = { pa_pin = nil, pa_on_level = 1 },  -- Air1103 常供电，软件不开关 PA
        tp    = {
            model = "gt911", port = 1,
            pin_rst = 72, pin_int = 51,
        },
        sd    = { spi_id = 1, pin_cs = 8, pin_sd_en = 74, speed = 20000000 },
    },

    -- ============ Air8605 引擎（10 寸）============
    -- 来源：module/Air8605/project/factory/config/eng_8605_10i_4g.lua
    --   lcd   ：pin_rst=15、背光 PWM3、时序同族
    --   audio ：走 Air1103 语音芯片（UART1，2M），GPIO73 = AUDIOPA_EN 是 Air1103 供电脚，
    --           power_on 拉高常供电，出厂固件不写 pa_ctrl，故本表 pa_pin=nil
    --   tp    ：**TP_RST 不传给 tp.init**（出厂固件注释：传了会真复位且复位期间 C 驱动把 INT
    --           拉低锁 0x5D，本板实测 INT 输出卡死），只传 TP_INT=GPIO51 + I2C1 复用
    --   sd    ：SPI1 CS=GPIO8、SD_EN=GPIO74、speed=20MHz
    ["8605_DEV_BOARD"] = {
        name = "Air8605 引擎(10寸 1024x600)",
        lcd  = {
            w = 1024, h = 600,
            pin_rst = 15,
            pin_pwr = nil,
            backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 },
            hbp = 140, hspw = 20, hfp = 160,
            vbp = 20,  vspw = 3,  vfp = 12,
            pclk_hz = 50 * 1000 * 1000,
        },
        audio = { pa_pin = nil, pa_on_level = 1 },  -- Air1103 常供电，软件不开关 PA
        tp    = {
            model = "gt911", port = 1,
            pin_rst = nil, pin_int = 51,
            pins = {
                { pin = 33, func = "I2C1_CLK" },
                { pin = 32, func = "I2C1_SDA" },
            },
        },
        sd    = { spi_id = 1, pin_cs = 8, pin_sd_en = 74, speed = 20000000 },
    },

    -- ============ Air8607 引擎（10 寸，Air1603 主控）============
    -- 来源：module/Air8607/project/factory/config/eng_8607_10i_v0.lua
    --   lcd   ：pin_rst=15、背光 PWM3(PIN55=GPIO13)、时序 140/20/160/20/3/12 @50MHz
    --   audio ：内置 DAC + HT6873 功放，pa_ctrl=GPIO73、pa_on_level=1（高电平使能）
    --   tp    ：GT911 走 I2C1（I2C1_SCL=GPIO39/I2C1_SDA=GPIO38），TP_RST=GPIO14、TP_INT=GPIO51
    --   sd    ：SPI1 CS=GPIO8、SD_EN=GPIO74、speed=20MHz
    ["8607_DEV_BOARD"] = {
        name = "Air8607 引擎(10寸 1024x600)",
        lcd  = {
            w = 1024, h = 600,
            pin_rst = 15,
            pin_pwr = nil,
            backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 },
            hbp = 140, hspw = 20, hfp = 160,
            vbp = 20,  vspw = 3,  vfp = 12,
            pclk_hz = 50 * 1000 * 1000,
        },
        audio = { pa_pin = 73, pa_on_level = 1 },   -- HT6873 高电平使能
        tp    = {
            model = "gt911", port = 1,
            pin_rst = 14, pin_int = 51,
        },
        sd    = { spi_id = 1, pin_cs = 8, pin_sd_en = 74, speed = 20000000 },
    },

    -- ============ Air8607A 引擎（10 寸，带 UVC，无 SD 卡）============
    -- 来源：module/Air8607/project/factory/config/eng_8607a_10i_v0.lua
    --   lcd   ：pin_rst=15、背光 PWM3
    --   audio ：pa_ctrl=GPIO73、pa_on_level=1
    --   tp    ：TP_RST=GPIO14、TP_INT=GPIO51
    --   sd    ：出厂固件**没有 storage.sd_card 段**（本板无 SD 卡座），故 sd=nil，
    --           本 demo 在该板只能播 /luadb 下的素材
    ["8607A_DEV_BOARD"] = {
        name = "Air8607A 引擎(10寸 1024x600，无SD卡)",
        lcd  = {
            w = 1024, h = 600,
            pin_rst = 15,
            pin_pwr = nil,
            backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 },
            hbp = 140, hspw = 20, hfp = 160,
            vbp = 20,  vspw = 3,  vfp = 12,
            pclk_hz = 50 * 1000 * 1000,
        },
        audio = { pa_pin = 73, pa_on_level = 1 },
        tp    = {
            model = "gt911", port = 1,
            pin_rst = 14, pin_int = 51,
        },
        sd    = nil,   -- 无 SD 卡
    },

    -- ============ Air1601 V1.1 EVB（7 寸）============
    -- 来源：project/Air1601_dev_board_V1.1/factory/config/evb_1601_7i_v11.lua
    --   lcd   ：pin_rst=15、pin_bl=GPIO2（GPIO 直驱背光，明确"不支持 PWM 调光"）、无 LCD_EN
    --   audio ：GPIO12 同时是 PA_EN / 5V_EN / 6205 EN，高电平有效（power_on 拉高 120ms）
    --   tp    ：TP_RST=GPIO3、TP_INT=GPIO51（无额外复用表）
    --   sd    ：SPI1 CS=GPIO8、speed=40MHz、无 SD_EN
    ["1601_EVB_V11"] = {
        name = "Air1601 V1.1 EVB(7寸 1024x600)",
        lcd  = {
            w = 1024, h = 600,
            pin_rst = 15,
            pin_pwr = nil,
            pin_bl = 2,       -- GPIO2 直驱背光
            backlight = nil,  -- 不支持 PWM 调光
            hbp = 140, hspw = 20, hfp = 160,
            vbp = 20,  vspw = 3,  vfp = 12,
            pclk_hz = 50 * 1000 * 1000,
        },
        audio = { pa_pin = 12, pa_on_level = 1 },
        tp    = {
            model = "gt911", port = 1,
            pin_rst = 3, pin_int = 51,
        },
        sd    = { spi_id = 1, pin_cs = 8, pin_sd_en = nil, speed = 40000000 },
    },

    -- ============ Air1601 / Air1602 V1.2 EVB（7 寸）============
    -- 来源：project/Air1602_dev_board_V1.2/factory/config/evb_1602_7i_v12.lua
    --   lcd   ：pin_rst=15、pin_pwr=GPIO57(LCD_EN)、背光 PWM3
    --   audio ：pa_ctrl=GPIO73、pa_on_level=0（Air160X V1.2 底板为低电平使能）
    --   tp    ：TP_RST=GPIO3、TP_INT=GPIO51
    --   sd    ：SPI1 CS=GPIO8、SD_EN=GPIO56、speed=8MHz
    ["1601_EVB_V12"] = {
        name = "Air1601/Air1602 V1.2 EVB(7寸 1024x600)",
        lcd  = {
            w = 1024, h = 600,
            pin_rst = 15,
            pin_pwr = 57,     -- LCD_EN 高电平使能
            backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 },
            hbp = 140, hspw = 20, hfp = 160,
            vbp = 20,  vspw = 3,  vfp = 12,
            pclk_hz = 50 * 1000 * 1000,
        },
        audio = { pa_pin = 73, pa_on_level = 0 },
        tp    = {
            model = "gt911", port = 1,
            pin_rst = 3, pin_int = 51,
        },
        sd    = { spi_id = 1, pin_cs = 8, pin_sd_en = 56, speed = 8000000 },
    },
}

local M = {}

-- 当前生效的板型标识，首次调用 get() 时确定
local current_key = nil

-- 默认喇叭软件音量（0~100，100 = 原始音量不衰减，0 = 静音，数值越小声音越轻）
-- 说明：HZV 音轨由 Audio V2 输出，Lua 侧只能调"通道软件音量"（audio_v2.soft_volume），
--       出厂默认值是 100 也就是完全不衰减，10 寸整机的板载喇叭在这个值下普遍偏大，
--       所以这里统一降到 30（约 -10.5dB）；某块板想单独调，在该板 audio 段加 vol 字段覆盖即可，
--       例如 audio = { pa_pin = 73, pa_on_level = 1, vol = 40 }
-- 界面上"音量+/-"按钮按 5 级步进（hzv_ui 里的 VOL_STEP），范围同样是 0~100。
local BOARD_VOLUME = 10

--[[
获取当前 HARDWARE_ENV 对应的硬件参数表；

@api hzv_hw.get()
@summary 按 HARDWARE_ENV 取出板型参数表，未知型号打印警告并回退默认板型
@return table 板型参数表（name/lcd/audio/tp/sd）

@usage
local cfg = hzv_hw.get()
log.info("hw", cfg.name, cfg.lcd.w, cfg.lcd.h)
]]
function M.get()
    if current_key then
        return board_cfg[current_key]
    end

    local key = HARDWARE_ENV
    local cfg = board_cfg[key]
    if not cfg then
        log.warn("hzv_hw", "未知的 HARDWARE_ENV", tostring(key), "回退默认板型", BOARD_DEFAULT)
        key = BOARD_DEFAULT
        cfg = board_cfg[key]
    end

    current_key = key
    log.info("hzv_hw", "当前硬件环境", key, cfg.name,
        "分辨率", cfg.lcd.w .. "x" .. cfg.lcd.h,
        "LCD_RST=GPIO" .. tostring(cfg.lcd.pin_rst),
        cfg.lcd.pin_pwr and ("LCD_PWR=GPIO" .. cfg.lcd.pin_pwr) or "无 LCD_PWR",
        cfg.lcd.pin_bl and ("LCD_BL=GPIO" .. cfg.lcd.pin_bl) or "非GPIO背光",
        cfg.audio.pa_pin and ("PA=GPIO" .. cfg.audio.pa_pin) or "无PA(音频走Air1103)",
        cfg.tp and ("TP_RST=GPIO" .. tostring(cfg.tp.pin_rst)) or "无触摸",
        (cfg.sd and cfg.sd.pin_sd_en) and ("SD_EN=GPIO" .. cfg.sd.pin_sd_en) or
            (cfg.sd and "无 SD_EN" or "无 SD 卡"))
    return cfg
end

--[[
获取当前板型中文名；

@api hzv_hw.name()
@summary 返回当前板型中文名，只用于日志打印
@return string 板型中文名
]]
function M.name()
    return M.get().name
end

--[[
查询当前板型是否带 SD 卡；

@api hzv_hw.has_sd()
@summary 供 main.lua / sd_app 判断是否需要尝试挂载 TF 卡
@return boolean 带 SD 卡返回 true
]]
function M.has_sd()
    return M.get().sd ~= nil
end

--[[
查询当前板型是否配置了触摸屏；

@api hzv_hw.has_tp()
@summary main.lua 用它决定进"选片界面"还是"自动演示模式"；
          注意这只是参数表上有触摸配置，实际 tp.init 失败时仍会回退自动演示
@return boolean 配置了触摸返回 true
]]
function M.has_tp()
    return M.get().tp ~= nil
end

--[[
按板型打开/关闭功放 PA；

@api hzv_hw.pa_set(on)
@summary HZV 带音轨，播放前必须打开 PA，暂停/停止后关闭，避免底噪；
          音频走 Air1103 的板型（8603/8605）pa_pin=nil，本函数直接返回，不动供电脚
@param boolean on true 打开功放，false 关闭功放
@return nil

@usage
hzv_hw.pa_set(true)   -- 开始播放前打开功放
hzv_hw.pa_set(false)  -- 暂停或停止后关闭功放
]]
function M.pa_set(on)
    local cfg = M.get()
    local pa_pin = cfg.audio.pa_pin
    if not pa_pin then
        return
    end

    -- 按 pa_on_level 换算实际输出电平：打开时输出有效电平，关闭时输出相反电平
    local on_level = cfg.audio.pa_on_level or 1
    local level = on and on_level or (1 - on_level)
    gpio.setup(pa_pin, level)
    log.info("hzv_hw", on and "功放打开" or "功放关闭", "GPIO" .. pa_pin, "电平", level)
end

--[[
查询当前板型应使用的喇叭软件音量；
@api hzv_hw.volume()
@summary 返回 0~1000 的软件音量值（100 = 不衰减），板型 audio.vol 优先，未配置时用 BOARD_VOLUME
@return number 软件音量
]]
function M.volume()
    local cfg = M.get()
    if cfg.audio and cfg.audio.vol then
        return cfg.audio.vol
    end
    return BOARD_VOLUME
end

return M
