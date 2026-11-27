--[[
@module  exd_st7102_rgb
@summary ST7102 显示IC初始化扩展库（RGB 接口，BOE 3.95寸 480x480 in-cell）
@version 1.0
@date    2026.11.27
@author  江访
@usage
本文件为 ST7102 显示 IC（RGB 接口）的显示IC初始化扩展库，核心业务逻辑为：
1、显示初始化：复位 + IC 寄存器初始化 + RGB 时序配置 + 帧缓冲分配（lcd 后端）
2、双后端自动适配：优先使用display核心库初始化，固件不支持display核心库就使用lcd核心库初始化
3、库内自带寄存器初始化序列（来源厂商序列 ST7102-BOE3.95-480X480-SPI3W-RGB18-incell.txt，字节级搬运）
4、提供颜色值换算接口：这块屏显存按BGR顺序取数，写显存前要先换算

初始化寄存器的命令走SPI（CLK/SDA/CS），显示数据走RGB接口。
本扩展库单文件独立，拷本文件一个即可在工程中使用。
初始化参数不传时使用内置默认值，传入则覆盖默认值。

本文件的对外接口有4个：
1、exd_st7102_rgb.setup(params)：显示初始化
2、exd_st7102_rgb.info()：查询屏幕信息
3、exd_st7102_rgb.version()：扩展库版本号查询
4、exd_st7102_rgb.to_panel_color(color_value)：把0xRRGGBB颜色值换算成这块屏显存需要的颜色值

-- 版本更新说明
-- 版本号：202611271000（正式版）
-- 1、更新时间：2026-11-27
-- 2、更新内容
--   - 正式版（ST7102 RGB 接口，BOE 3.95寸 480x480 in-cell，自带寄存器初始化序列）
]]

local M = {}

-- 扩展库版本号，格式 yyyymmddhhmm
local VERSION = "202611271000"

-- 显示 IC 固有参数（分辨率、时序、总线时钟、序列开关、核心库内置型号名）
local ic_info = {
    ic = "ST7102",
    core_model = { display = nil, lcd = nil },  -- 核心库无内置型号，全部走库内自带序列
    w = 480, h = 480,
    hspw = 2, hbp = 40, hfp = 40,
    vspw = 2, vbp = 14, vfp = 200,
    bus_speed = 23000000,       -- 像素时钟，23MHz
    spi_init = true,            -- 初始化寄存器的命令走SPI
}

-- RGB 时序信号极性
local HS_POLARITY = 0       -- HSYNC极性，0=低有效
local VS_POLARITY = 0       -- VSYNC极性，0=低有效
local DE_POLARITY = 0       -- DE极性，0=低有效
local PCLK_POLARITY = 1     -- PCLK极性，1=高电平采样

-- 显存数据访问方向与接口像素格式，两个值共同决定颜色对不对
-- 厂商自己给的值，不要动
local MADCTL_VALUE = 0x08           -- 显存数据访问方向，bit3置1按BGR顺序取数
local PIXEL_FORMAT_VALUE = 0x77     -- 接口像素格式，7h=24bit/像素

-- IC 寄存器初始化命令序列（来源厂商初始化时序 ST7102-BOE3.95-480X480-SPI3W-RGB18-incell.txt，字节级搬运，共 26 条）
-- 命令格式：{cmd, data1, ..., delay = ms}，delay 为发送后延时毫秒数，可省略
local custom_cmds = {
    {0x10},                                                     -- 休眠进入
    {0x28},                                                     -- 关显示
    {0x99, 0x71, 0x02, 0xA2},
    {0x99, 0x71, 0x02, 0xA3},
    {0x99, 0x71, 0x02, 0xA4},
    {0xB0, 0x22, 0x61, 0x1E, 0x61, 0x2F, 0x39, 0x39},
    {0xB7, 0x46, 0x46},
    {0xBF, 0x50, 0x50},
    {0xD7, 0x00, 0x10, 0x8C, 0x08, 0xF0, 0xF0},
    {0xA3, 0x40, 0x03, 0x80, 0x00, 0x45, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1E, 0x01, 0x00, 0x12, 0x00, 0x45, 0x05, 0x00, 0x00, 0x00, 0x00, 0x1E, 0x01, 0x00, 0x12, 0x20, 0x52, 0x00, 0x05, 0x00, 0x00, 0xFF},
    {0xA6, 0x08, 0x00, 0x24, 0x55, 0x35, 0x00, 0x76, 0x40, 0x4E, 0x4E, 0x00, 0x24, 0x55, 0x00, 0x00, 0x40, 0x40, 0x4E, 0x4E, 0x02, 0xAC, 0x51, 0x00, 0xCC, 0x40, 0x40, 0x4E, 0x4E, 0x00, 0xAC, 0x11, 0x00, 0x00, 0x40, 0x40, 0x4E, 0x4E, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00},
    {0xA7, 0x19, 0x19, 0x00, 0x64, 0x40, 0x07, 0x16, 0x40, 0x00, 0x44, 0x43, 0x4E, 0x4E, 0x00, 0x64, 0x40, 0x25, 0x34, 0x00, 0x00, 0x42, 0x41, 0x4E, 0x4E, 0x00, 0x64, 0x40, 0x4B, 0x5A, 0x00, 0x00, 0x42, 0x41, 0x4E, 0x4E, 0x00, 0x24, 0x40, 0x69, 0x78, 0x00, 0x00, 0x40, 0x40, 0x4E, 0x4E, 0x00, 0x44},
    {0xAC, 0x00, 0x1C, 0x04, 0x1A, 0x19, 0x1B, 0x1B, 0x18, 0x06, 0x13, 0x19, 0x11, 0x1B, 0x08, 0x18, 0x0A, 0x01, 0x1C, 0x04, 0x1A, 0x19, 0x1B, 0x1B, 0x18, 0x06, 0x12, 0x19, 0x10, 0x1B, 0x09, 0x18, 0x0B, 0xBF, 0xAA, 0xBF, 0xAA, 0x00},
    {0xAD, 0xCC, 0x40, 0x46, 0x11, 0x04, 0x6F, 0x6F},
    {0xE8, 0x30, 0x07, 0x05, 0x6A, 0x6A, 0x9C, 0x00, 0xE2, 0x04, 0x00, 0x00, 0x00, 0x00, 0xEF},
    {0x75, 0x03, 0x04},
    {0xE7, 0x8B, 0x3C, 0x00, 0x0C, 0xF0, 0x5D, 0x00, 0x5D, 0x00, 0x5D, 0x00, 0x5D, 0x00, 0xFF, 0x00, 0x08, 0x7B, 0x00, 0x00, 0xC8, 0x6A, 0x5A, 0x08, 0x1A, 0x3C, 0x00, 0xA1, 0x01, 0x8C, 0x01, 0x7F, 0xF0, 0x22},
    {0xE9, 0x3C, 0x7F, 0x08, 0x10, 0x1A, 0x7A, 0x22, 0x1A, 0x33},
    {0xC8, 0x00, 0x00, 0x15, 0x26, 0x44, 0x00, 0x78, 0x03, 0xBE, 0x06, 0x11, 0x1C, 0x09, 0x8A, 0x03, 0x21, 0xD4, 0x01, 0x11, 0x0F, 0x22, 0x4A, 0x0F, 0x8F, 0x0A, 0x32, 0xF0, 0x0A, 0x41, 0x0D, 0xF3, 0x80, 0x0D, 0xAE, 0xC5, 0x03, 0xC4},
    {0xC9, 0x00, 0x00, 0x15, 0x26, 0x44, 0x00, 0x78, 0x03, 0xBE, 0x06, 0x11, 0x1C, 0x09, 0x8A, 0x03, 0x21, 0xD4, 0x01, 0x11, 0x0F, 0x22, 0x4A, 0x0F, 0x8F, 0x0A, 0x32, 0xF0, 0x0A, 0x41, 0x0D, 0xF3, 0x80, 0x0D, 0xAE, 0xC5, 0x03, 0xC4},
    {0x62, 0x00},
    {0x11, delay = 120},                                        -- 休眠退出，等待120ms
    {0x29},                                                     -- 开显示
    {0x35, 0x00},                                               -- 开撕裂效应行
    {0x36, MADCTL_VALUE},                                       -- 显存数据访问方向，按BGR顺序取数
    {0x3A, PIXEL_FORMAT_VALUE},                                 -- 像素格式，24bit/像素
}

-- 默认显示参数（参考面板参数组；不传用默认值，传入覆盖默认值）
M.defaults = {
    pin_rst = 1,                -- LCD 复位脚
    pin_clk = 41,               -- IC 初始化 SPI 时钟
    pin_sda = 40,               -- IC 初始化 SPI 数据
    pin_cs = 42,                -- IC 初始化 SPI 片选
    rotation = 0,               -- 不旋转
    screen_size = 3.95,         -- 物理尺寸 3.95 英寸
    use_builtin_ic = false,     -- 核心库无内置ST7102型号，恒用库内自带序列
}

-- 运行状态缓存（模块级局部变量）
local state = {
    inited = false,       -- 显示是否已初始化
    backend = nil,        -- 实际使用的后端："display" 或 "lcd"
    params = nil,         -- 合并后的显示参数
    info = nil,           -- 屏幕信息表
}

-- ==================== 内部函数 ====================

--[[
探测可用的显示后端；
display 优先（与 airui C 层探测顺序一致），lcd 兜底；

@function (内部函数) pick_backend
@return string, table "display"/"lcd" 与对应全局库表；都不可用时返回 nil
]]
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

--[[
旋转角度转换为 lcd 库的 direction 值；
lcd direction 真实映射：0=0° 1=90° 2=180° 3=270°（核心库文档有误，以代码为准）；

@function (内部函数) rot_to_direction
@return number lcd.direction 取值 0~3
]]
local function rot_to_direction(rotation)
    if rotation == 90 then return 1 end
    if rotation == 180 then return 2 end
    if rotation == 270 then return 3 end
    return 0
end

--[[
custom_cmds 自然表 → lcd initcmd 打包数组转换；
initcmd 编码：opcode 放 bit23:16、值放 bit7:0，opcode 0x02=发命令 0x03=追加1字节数据 0x01=延时ms；
延时超过 255ms 时自动拆分为多条；

@function (内部函数) cmds_to_initcmd
@return table lcd.init 的 initcmd 打包数组
]]
local function cmds_to_initcmd(cmds)
    local out = {}
    for i = 1, #cmds do
        local e = cmds[i]
        table.insert(out, 65536 * 2 + (e[1] or 0))      -- 0x02 发命令
        for j = 2, #e do
            table.insert(out, 65536 * 3 + (e[j] or 0))  -- 0x03 追加 1 字节数据
        end
        local delay = e.delay
        while delay and delay > 0 do
            local d = (delay > 255) and 255 or delay
            table.insert(out, 65536 * 1 + d)            -- 0x01 延时 ms
            delay = delay - d
        end
    end
    return out
end

--[[
执行显示初始化；
后端探测、序列发送、帧缓冲分配都在这里完成；

@function (内部函数) do_init
@table params 合并后的显示参数表
@return boolean, string 成功返回true与后端名"display"/"lcd"，失败返回false与错误信息字符串
]]
local function do_init(params)
    -- 后端探测：display 优先，lcd 兜底
    local backend, lib = pick_backend()
    if not backend then
        log.error("exd_st7102_rgb", "固件缺少 display 与 lcd 库，无法初始化屏幕")
        return false, "no display/lcd lib in firmware"
    end
    -- PC 模拟器跳过（airui 走 SDL 渲染，避免双窗口）
    if rtos.bsp() == "PC" then
        log.info("exd_st7102_rgb", "PC 模拟器，跳过显示初始化")
        return true, "display"
    end
    if backend == "display" then
        local cfg = {
            id = 0,                     -- airui 固定挂 display id 0，必须显式传
            interface = "rgb",
            w = params.w, h = params.h,
            crop_w = params.w,          -- 裁剪窗口与屏幕等大
            crop_h = params.h,
            hbp = params.hbp, hspw = params.hspw, hfp = params.hfp,
            vbp = params.vbp, vspw = params.vspw, vfp = params.vfp,
            pclk_hz = params.bus_speed, -- display 字段名是 pclk_hz
            hs_polarity = HS_POLARITY,
            vs_polarity = VS_POLARITY,
            de_polarity = DE_POLARITY,
            pclk_polarity = PCLK_POLARITY,
            pin_rst = params.pin_rst,
        }
        local ok, err
        if params.use_builtin_ic and params.core_model and params.core_model.display then
            -- 核心库内置面板直调（初始化序列由核心库内置；ST7102 无内置型号，走不到这里）
            ok, err = lib.init(params.core_model.display, cfg)
        else
            if params.spi_init then
                cfg.pin_cs = params.pin_cs
                cfg.pin_scl = params.pin_clk   -- display 字段名是 pin_scl
                cfg.pin_sdi = params.pin_sda   -- display 字段名是 pin_sdi
            end
            cfg.custom_cmds = custom_cmds  -- display 用自然表格式
            ok, err = lib.init("custom", cfg)
        end
        if not ok then
            log.error("exd_st7102_rgb", "display.init失败", err)
            return false, "display.init 失败: " .. tostring(err)
        end
        log.info("exd_st7102_rgb", "屏幕初始化完成", params.w, params.h)
        log.info("exd_st7102_rgb", "颜色寄存器", string.format("0x36=0x%02X 0x3A=0x%02X", MADCTL_VALUE, PIXEL_FORMAT_VALUE))
        return true, "display"
    end
    -- lcd 后端（固件不支持 display 接口时的降级路径）
    local cfg = {
        port = rawget(lib, "RGB") or 0x22,  -- lcd.RGB 常量，取不到时用 0x22
        w = params.w, h = params.h,
        hbp = params.hbp, hspw = params.hspw, hfp = params.hfp,
        vbp = params.vbp, vspw = params.vspw, vfp = params.vfp,
        bus_speed = params.bus_speed,
        pin_rst = params.pin_rst,
        direction = rot_to_direction(params.rotation),
    }
    if params.spi_init then
        -- lcd 字段名就是 pin_clk / pin_sda / pin_cs，直接透传
        cfg.pin_clk = params.pin_clk
        cfg.pin_sda = params.pin_sda
        cfg.pin_cs = params.pin_cs
    end
    local ok
    if params.use_builtin_ic and params.core_model and params.core_model.lcd then
        -- 核心库内置型号直调
        ok = lib.init(params.core_model.lcd, cfg)
    else
        cfg.initcmd = cmds_to_initcmd(custom_cmds)  -- lcd 用打包格式，自动转换
        ok = lib.init("custom", cfg)
    end
    if not ok then
        return false, "lcd.init 失败"
    end
    -- 分配帧缓冲（PSRAM 优先，回退 SRAM），刷新交由上层/UI 框架控制
    if lib.setupBuff then
        lib.setupBuff(nil, true)
    end
    if lib.autoFlush then
        lib.autoFlush(false)
    end
    log.info("exd_st7102_rgb", "屏幕初始化完成", params.w, params.h)
    return true, "lcd"
end

--[[
合并参数：IC 固有参数 → M.defaults 参考面板默认 → 用户传入参数，逐层覆盖；

@function (内部函数) resolve_params
@return table 合并后的显示参数表
]]
local function resolve_params(opts)
    local p = {}
    local info = ic_info
    -- 第一层：显示 IC 固有参数（分辨率、时序、总线时钟、序列开关、核心库内置型号名）
    p.w, p.h = info.w, info.h
    p.hbp, p.hspw, p.hfp = info.hbp, info.hspw, info.hfp
    p.vbp, p.vspw, p.vfp = info.vbp, info.vspw, info.vfp
    p.bus_speed = info.bus_speed
    p.spi_init = info.spi_init
    p.core_model = info.core_model
    -- 第二层：参考面板默认参数（板级引脚、旋转、物理尺寸等）
    for k, v in pairs(M.defaults) do
        p[k] = v
    end
    -- 第三层：用户传入参数覆盖默认值
    if opts then
        for k, v in pairs(opts) do
            p[k] = v
        end
    end
    p.rotation = p.rotation or 0
    return p
end

-- ==================== 对外接口 ====================

--[[
显示初始化；
复位、发送ST7102寄存器初始化序列、配置RGB时序、分配帧缓冲，一次完成；
参数不传时使用 M.defaults 默认值，传入则覆盖默认值；
重复调用直接返回成功，不会重复初始化；

@api exd_st7102_rgb.setup(params)

@table
params
参数含义：用户参数表，全部可选（覆盖默认值）
数据类型：table
是否必选：否
注意事项：可覆盖 pin_rst / pin_clk / pin_sda / pin_cs / rotation / screen_size
参数示例：{ pin_rst = 1 }

@return boolean, table or string
成功返回 true 与屏幕信息表 {ic, backend, w, h, screen_size, rotation}，失败返回 false 与错误信息字符串

@usage
-- 显示全默认（Air1602 引擎接线）
local ok, info = exd_st7102_rgb.setup()

-- 换板子时覆盖引脚
local ok, info = exd_st7102_rgb.setup({ pin_rst = 20, pin_cs = 22 })
]]
function M.setup(params)
    if state.inited then
        log.warn("exd_st7102_rgb", "已初始化过，忽略重复 setup")
        return true, state.info
    end
    -- 参数合并：IC 固有 → 参考面板默认 → 用户覆盖
    local merged = resolve_params(params)
    -- 显示初始化（双后端选择、序列发送在 do_init 内部完成）
    local ok, backend = do_init(merged)
    if not ok then
        return false, backend
    end
    -- 缓存运行状态
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
    log.info("exd_st7102_rgb", "显示初始化完成", info.ic, info.w, info.h, info.backend)
    return true, info
end

--[[
查询屏幕信息；setup 前返回内置默认值，setup 后返回实际初始化值；

@api exd_st7102_rgb.info()

@return table
含义说明：屏幕信息表
数据类型：table
取值范围：{ ic, backend, w, h, screen_size, rotation }
返回示例：{ ic = "ST7102", backend = "display", w = 480, h = 480, screen_size = 3.95, rotation = 0 }

@usage
local info = exd_st7102_rgb.info()
log.info("exd_st7102_rgb", info.w, info.h)
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

@api exd_st7102_rgb.version()

@return string
含义说明：扩展库版本号
数据类型：string
取值范围：格式为 yyyymmddhhmm 的版本号字符串
返回示例："202611271000"

@usage
local ver = exd_st7102_rgb.version()
]]
function M.version()
    return VERSION
end

--[[
把0xRRGGBB格式的颜色值换算成这块屏显存需要的颜色值；
这块屏的显存是BGR顺序，0xRRGGBB的红色分量会被当成蓝色显示，蓝色分量会被当成红色显示，
所以写显存之前要先交换红色和蓝色分量，绿色分量保持不变；
交换完还要把三个分量都截成显存的位码宽度，红色和蓝色各5位、绿色6位；

实测换算方向是：
显示的红 = ((P & 0xFF) & 0x1F) * 8，显示的绿 = (((P >> 8) & 0xFF) & 0x3F) * 4，显示的蓝 = (((P >> 16) & 0xFF) & 0x1F) * 8
也就是低字节才是红、中间字节是绿、高字节是蓝，并且只用每字节的低位段；

@api exd_st7102_rgb.to_panel_color(color_value)

@number
color_value
参数含义：0xRRGGBB格式的颜色值
数据类型：number
取值范围：0x000000到0xFFFFFF
是否必选：是
参数示例：0x2F80ED表示亮蓝色

@return number
含义说明：交换红蓝分量并截位之后的颜色值，可以直接传给airui的color参数
数据类型：number
取值范围：0x000000到0xFFFFFF
返回示例：0x2F80ED换算后得到0x1D2005

@usage
-- 亮蓝色0x2F80ED换算后得到0x1D2005
local panel_color = exd_st7102_rgb.to_panel_color(0x2F80ED)
]]
function M.to_panel_color(color_value)
    -- 红色分量在bit23到bit16
    local red = bit.band(bit.rshift(color_value, 16), 0xFF)
    -- 绿色分量在bit15到bit8
    local green = bit.band(bit.rshift(color_value, 8), 0xFF)
    -- 蓝色分量在bit7到bit0
    local blue = bit.band(color_value, 0xFF)
    -- 交换红色和蓝色分量，绿色分量保持不变
    -- 蓝色取高5位放bit23到bit16，绿色取高6位放bit15到bit8，红色取高5位放bit7到bit0
    return bit.lshift(bit.rshift(blue, 3), 16) + bit.lshift(bit.rshift(green, 2), 8) + bit.rshift(red, 3)
end

return M
