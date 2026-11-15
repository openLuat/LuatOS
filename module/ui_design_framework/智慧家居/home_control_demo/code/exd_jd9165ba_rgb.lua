--[[
@module  exd_jd9165ba_rgb
@summary JD9165BA 显示IC初始化扩展库（RGB 接口）
@version 1.1
@date    2026.10.01
@author  江访
@usage
本文件为 JD9165BA 显示 IC（RGB 接口）的显示IC初始化扩展库，核心业务逻辑为：
1、显示初始化：复位 + RGB 时序配置 + 帧缓冲分配（lcd 后端）
2、双后端自动适配：优先使用display核心库初始化，固件不支持display核心库就使用lcd核心库初始化
3、JD9165BA 为免初始化 IC：无 SPI 引脚、无寄存器初始化序列，面板由硬件绑带引脚（MODE/L-R/U-D/DITHB）配置

本扩展库单文件独立，拷本文件一个即可在工程中使用。
板级参数 pin_rst 必传；屏幕参数不传时使用内置默认值（参考面板 TL070WSH62CT-M1977A），传入则覆盖默认值。

本文件的对外接口有3个：
1、exd_jd9165ba_rgb.setup(params)：显示初始化
2、exd_jd9165ba_rgb.info()：查询屏幕信息
3、exd_jd9165ba_rgb.version()：扩展库版本号查询

-- 版本更新说明
-- 版本号：202610031000
-- 1、更新时间：2026-10-03
-- 2、更新内容
--   - 修正默认 RGB 时序：规格书 5.2 参考时序（20/20/20/10/4/4 @51.2MHz）实测仅部分
--     显示（画面横向偏移，仅一侧正常），默认改用实测正常时序 140/20/160/20/3/12 @50MHz
--     （与 hx8282 系 1024x600 RGB 面板一致，总量 1344x635）
-- 版本号：202610011000（初版）
-- 1、更新时间：2026-10-01
-- 2、更新内容
--   - 初版（JD9165BA RGB 接口，免初始化 IC，无寄存器序列）
--     参考面板 TL070WSH62CT-M1977A：7.0 英寸 1024x600，RGB 24bit TTL，GT911 触摸
]]
local M = {}

-- 扩展库版本号，格式 yyyymmddhhmm
local VERSION = "202610031000"

-- 显示 IC 固有参数（分辨率、时序、总线时钟）
-- 时序为实测正常值（与 hx8282 系 1024x600 RGB 面板一致，总量 1344x635）
-- 规格书 5.2 TCON 参考时序 thb/thpw/thfp=20/20/20、tvb/tvpw/tvfp=10/4/4、DCLK 51.2MHz
-- 实测仅部分显示（画面横向偏移），勿作默认；如需尝试用 setup 参数覆盖
local ic_info = {
    ic = "JD9165BA",
    w = 1024, h = 600,
    hbp = 140, hspw = 20, hfp = 160, vbp = 20, vspw = 3, vfp = 12,
    bus_speed = 50000000,
}

-- 默认显示参数（参考面板参数组；不传用默认值，传入覆盖默认值）
-- JD9165BA 不设板级默认参数：pin_rst 按实际板级必传
M.defaults = {
    screen_size = 7.0,
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
显示初始化（双后端选择在内部完成）；
JD9165BA 免初始化 IC：不传寄存器序列，核心库只做复位 + RGB 时序配置；

@function do_init
@return boolean, string 成功返回 true 与后端名，失败返回 false 与错误信息
]]
local function do_init(params)
    -- 后端探测：display 优先，lcd 兜底
    local backend, lib = pick_backend()
    if not backend then
        log.error("exd_jd9165ba_rgb", "固件缺少 display 与 lcd 库，无法初始化屏幕")
        return false, "no display/lcd lib in firmware"
    end
    -- PC 模拟器跳过（airui 走 SDL 渲染，避免双窗口）
    if rtos.bsp() == "PC" then
        log.info("exd_jd9165ba_rgb", "PC 模拟器，跳过显示初始化")
        return true, "display"
    end
    if backend == "display" then
        -- 免序列路径：不传 custom_cmds，核心库只复位 + 配置 RGB 时序
        local cfg = {
            id = 0,                     -- airui 固定挂 display id 0，必须显式传
            interface = "rgb",
            w = params.w, h = params.h,
            hbp = params.hbp, hspw = params.hspw, hfp = params.hfp,
            vbp = params.vbp, vspw = params.vspw, vfp = params.vfp,
            pclk_hz = params.bus_speed, -- display 字段名是 pclk_hz
            pin_rst = params.pin_rst,
        }
        local ok, err = lib.init("custom", cfg)
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
    local ok = lib.init("custom", cfg)
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
    -- lcd 的 custom 型号必须标记用户初始化完成，否则后续显示操作不生效
    if lib.user_done then
        lib.user_done()
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
    -- 第一层：显示 IC 固有参数（分辨率、时序、总线时钟）
    p.w, p.h = info.w, info.h
    p.hbp, p.hspw, p.hfp = info.hbp, info.hspw, info.hfp
    p.vbp, p.vspw, p.vfp = info.vbp, info.vspw, info.vfp
    p.bus_speed = info.bus_speed
    -- 第二层：参考面板默认参数（物理尺寸等）
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
屏幕参数不传时使用内置默认值，传入则覆盖默认值；板级参数 pin_rst 必传；

@api exd_jd9165ba_rgb.setup(params)

@table
params
参数含义：用户参数表，屏幕参数可选（覆盖默认值），pin_rst 必传
数据类型：table
是否必选：否
注意事项：完整参数说明见本扩展库文档（exd_jd9165ba_rgb.md）
参数示例：{ pin_rst = 20 }

@return boolean, table or string
成功返回 true 与屏幕信息表 {ic, backend, w, h, screen_size, rotation}，失败返回 false 与错误信息字符串

@usage
-- 基础用法：只传板级复位脚
local ok, info = exd_jd9165ba_rgb.setup({ pin_rst = 20 })
]]
function M.setup(params)
    if state.inited then
        log.warn("exd_jd9165ba_rgb", "已初始化过，忽略重复 setup")
        return true, state.info
    end
    -- 参数合并：IC 固有 → 参考面板默认 → 用户覆盖
    local merged = resolve_params(params)
    -- 板级复位脚必传：JD9165BA 不设板级默认参数
    if not merged.pin_rst then
        log.error("exd_jd9165ba_rgb", "缺少 pin_rst 参数，板级 LCD 复位引脚必传")
        return false, "pin_rst 必传：请传入板级 LCD 复位引脚编号，例如 setup({ pin_rst = 20 })"
    end
    -- 显示初始化（双后端选择在 do_init 内部完成）
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
    log.info("exd_jd9165ba_rgb", "显示初始化完成", info.ic, info.w, info.h, info.backend)
    return true, info
end

--[[
查询屏幕信息；setup 前返回内置默认值，setup 后返回实际初始化值；

@api exd_jd9165ba_rgb.info()

@return table
含义说明：屏幕信息表
数据类型：table
取值范围：{ ic, backend, w, h, screen_size, rotation }
返回示例：{ ic = "JD9165BA", backend = "display", w = 1024, h = 600, screen_size = 7.0, rotation = 0 }

@usage
local info = exd_jd9165ba_rgb.info()
log.info("exd_jd9165ba_rgb", info.w, info.h)
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

@api exd_jd9165ba_rgb.version()

@return string
含义说明：扩展库版本号
数据类型：string
取值范围：格式为 yyyymmddhhmm 的版本号字符串
返回示例："202610031000"

@usage
local ver = exd_jd9165ba_rgb.version()
]]
function M.version()
    return VERSION
end

return M
