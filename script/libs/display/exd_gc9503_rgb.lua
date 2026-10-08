--[[
@module  exd_gc9503_rgb
@summary GC9503 显示IC初始化扩展库（RGB 接口）
@version 1.1
@date    2026.09.29
@author  江访
@usage
本文件为 GC9503 显示 IC（RGB 接口）的显示IC初始化扩展库，核心业务逻辑为：
1、显示初始化：复位 + IC 寄存器初始化 + RGB 时序配置 + 帧缓冲分配（lcd 后端）
2、双后端自动适配：优先使用display核心库初始化，固件不支持display核心库就使用lcd核心库初始化
3、核心库内置面板直调 / 库内自带序列（use_builtin_ic，默认 false 用自带序列）

本扩展库单文件独立，拷本文件一个即可在工程中使用。
初始化参数不传时使用内置默认值，传入则覆盖默认值。

本文件的对外接口有3个：
1、exd_gc9503_rgb.setup(params)：显示初始化
2、exd_gc9503_rgb.info()：查询屏幕信息
3、exd_gc9503_rgb.version()：扩展库版本号查询

-- 版本更新说明
-- 版本号：202609301000
-- 1、更新时间：2026-09-30
-- 2、更新内容
--   - use_builtin_ic 默认改为 false，库内自带序列优先（真机实测：核心库内置序列与面板批次不匹配时黑屏）；补充触摸初始化注意事项
-- 版本号：202609291000（正式版）
-- 1、更新时间：2026-09-29
-- 2、更新内容
--   - 正式版（GC9503 RGB 接口，自带寄存器初始化序列）
]]
local M = {}

-- 扩展库版本号，格式 yyyymmddhhmm
local VERSION = "202609301000"

-- 显示 IC 固有参数（分辨率、时序、总线时钟、序列开关、核心库内置型号名）
local ic_info = {
    ic = "GC9503",
    core_model = { display = nil, lcd = nil },  -- 核心库内置型号名，nil 表示无内置
    w = 480, h = 854,
    hbp = 40, hspw = 10, hfp = 40, vbp = 10, vspw = 8, vfp = 20,
    bus_speed = 30000000,
    spi_init = true,  -- 是否需要 SPI 寄存器初始化序列
}

-- IC 寄存器初始化命令序列（来源 factory_new config/evb_8101b_5i_v2.lua，字节级搬运，共 39 条）
-- 命令格式：{cmd, data1, ..., delay = ms}，delay 为发送后延时毫秒数，可省略
local custom_cmds = {
    {0xFE},
    {0xEF},
    {0x36, 0x48},
    {0x3A, 0x10},
    {0xB0, 0x01},
    {0xB1, 0x26, 0x23, 0x22, 0x21, 0x20, 0x1F, 0x1E, 0x1D, 0x1C, 0x18, 0x02},
    {0xB2, 0x01},
    {0xB3, 0x00, 0x00, 0x00, 0x00, 0x22, 0x21, 0x20, 0x1F, 0x1E, 0x1D, 0x1C, 0x18},
    {0xB4, 0x41},
    {0xB5, 0x02, 0x08},
    {0xB6, 0x80},
    {0xB8, 0x45, 0x09},
    {0xB9, 0x41, 0x08},
    {0xBA, 0x00},
    {0xBC, 0x43, 0x00, 0x00, 0x00, 0x0F, 0x39, 0x00},
    {0xBD, 0x30, 0x08, 0x00, 0x00, 0x00},
    {0xBE, 0x23, 0x00, 0x00, 0x00, 0x00},
    {0xBF, 0x27, 0x00, 0x00, 0x00, 0x00},
    {0xC0, 0x12, 0x12},
    {0xC1, 0x24, 0x02},
    {0xC2, 0x01, 0x08},
    {0xCC, 0x18},
    {0xCD, 0x00},
    {0xD0, 0x22, 0x0A, 0x0A, 0xE0},
    {0xD1, 0xC0, 0x44, 0x26, 0x06},
    {0xD2, 0x08, 0x40, 0x24, 0x08},
    {0xD5, 0x20, 0x00, 0x04, 0x80},
    {0xE6, 0x00, 0x00, 0x10, 0x00},
    {0xD6, 0xC0, 0x44, 0x26, 0x06},
    {0xD7, 0x22, 0x0A, 0x0A, 0xE0},
    {0xD8, 0x20, 0x00, 0x04, 0x80},
    {0xE7, 0x00, 0x00, 0x10, 0x00},
    {0xE8, 0x01, 0x0A},
    {0xEC, 0x3C, 0x00},
    {0xED, 0x00, 0x00, 0x20, 0x5F},
    {0xEF, 0x10, 0x0D, 0x04, 0x08, 0x3F, 0x1F},
    {0x36, 0x00},
    {0x11, delay = 120},
    {0x29, delay = 20},}
-- 默认显示参数（参考面板参数组；不传用默认值，传入覆盖默认值）
M.defaults = {
    pin_rst = 9,                -- LCD 复位脚
    pin_clk = 2,                -- IC 初始化 SPI 时钟
    pin_sda = 4,                -- IC 初始化 SPI 数据
    pin_cs = 3,                 -- IC 初始化 SPI 片选
    rotation = 0,               -- 不旋转
    screen_size = 5.0,          -- 物理尺寸 5 英寸
    use_builtin_ic = false,      -- 默认用库内自带初始化序列（实测可靠；核心库内置序列面向其他批次面板）
}

-- 运行状态缓存（模块级局部变量）
local state = {
    inited = false,       -- 显示是否已初始化
    backend = nil,        -- 实际使用的后端："display" 或 "lcd"
    params = nil,         -- 合并后的显示参数
}

-- ==================== 内部函数 ====================

--[[
探测可用的显示后端；
display 优先（与 airui C 层探测顺序一致），lcd 兜底；

@function pick_backend
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

@function rot_to_direction
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

@function cmds_to_initcmd
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


local function do_init(params)
    -- 后端探测：display 优先，lcd 兜底
    local backend, lib = pick_backend()
    if not backend then
        log.error("exd_gc9503_rgb", "固件缺少 display 与 lcd 库，无法初始化屏幕")
        return false, "no display/lcd lib in firmware"
    end
    -- PC 模拟器跳过（airui 走 SDL 渲染，避免双窗口）
    if rtos.bsp() == "PC" then
        log.info("exd_gc9503_rgb", "PC 模拟器，跳过显示初始化")
        return true, "display"
    end
    -- use_builtin_ic：M.defaults 默认 false 用库内自带序列；传 true 直调核心库内置型号
    local use_builtin = params.use_builtin_ic ~= false
    if backend == "display" then
        local cfg = {
            id = 0,                     -- airui 固定挂 display id 0，必须显式传
            interface = "rgb",
            w = params.w, h = params.h,
            hbp = params.hbp, hspw = params.hspw, hfp = params.hfp,
            vbp = params.vbp, vspw = params.vspw, vfp = params.vfp,
            pclk_hz = params.bus_speed, -- display 字段名是 pclk_hz
            pin_rst = params.pin_rst,
        }
        local ok, err
        if use_builtin and params.core_model and params.core_model.display then
            -- 核心库内置面板直调（初始化序列由核心库内置）
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
            return false, "display.init 失败: " .. tostring(err)
        end
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
    if use_builtin and params.core_model and params.core_model.lcd then
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
    return true, "lcd"
end

--[[
合并参数：IC 固有参数 → M.defaults 参考面板默认 → 用户传入参数，逐层覆盖；

@function resolve_params
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
    p.screen_size = info.screen_size
    p.core_model = info.core_model
    -- 第二层：参考面板默认参数（板级引脚、旋转等）
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
参数不传时使用 M.defaults 默认值，传入则覆盖默认值；

@api exd_gc9503_rgb.setup(params)

@table
params
参数含义：用户参数表，全部可选（覆盖默认值）
数据类型：table
是否必选：否
注意事项：完整参数说明见本扩展库文档（exd_gc9503_rgb.md）
参数示例：{ pin_rst = 20 }

@return boolean, table or string
成功返回 true 与屏幕信息表 {ic, backend, w, h, screen_size, rotation}，失败返回 false 与错误信息字符串

@usage
-- 显示全默认
local ok, info = exd_gc9503_rgb.setup()
]]
function M.setup(params)
    if state.inited then
        log.warn("exd_gc9503_rgb", "已初始化过，忽略重复 setup")
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
    log.info("exd_gc9503_rgb", "显示初始化完成", info.ic, info.w, info.h, info.backend)
    return true, info
end

--[[
查询屏幕信息；setup 前返回内置默认值，setup 后返回实际初始化值；

@api exd_gc9503_rgb.info()

@return table
含义说明：屏幕信息表
数据类型：table
取值范围：{ ic, backend, w, h, screen_size, rotation }
返回示例：{ ic = "GC9503", backend = "display", w = 480, h = 854, screen_size = 9.0, rotation = 0 }

@usage
local info = exd_gc9503_rgb.info()
log.info("exd_gc9503_rgb", info.w, info.h)
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

@api exd_gc9503_rgb.version()

@return string
含义说明：扩展库版本号
数据类型：string
取值范围：格式为 yyyymmddhhmm 的版本号字符串
返回示例："202609291000"

@usage
local ver = exd_gc9503_rgb.version()
]]
function M.version()
    return VERSION
end

return M
