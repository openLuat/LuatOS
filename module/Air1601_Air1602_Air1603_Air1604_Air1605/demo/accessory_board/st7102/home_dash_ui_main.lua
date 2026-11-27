--[[
@module  home_dash_ui_main
@summary 86盒深色部件仪表盘的主控模块，负责屏幕、airui、触摸初始化和页面调度
@version 1.0
@date    2026.11.04
@author  江访
@usage
本文件为86盒深色部件仪表盘的主控模块，核心业务逻辑为：
1、调用exd_st7102_rgb显示IC初始化扩展库初始化屏幕，这块屏是480x480，显示数据走RGB接口，寄存器初始化走SPI；
2、初始化airui控件库并加载hzfont矢量字库，抗锯齿取最锐的4x4边缘采样；
3、初始化ST7102触摸并绑定给airui，绑上之后点击由airui自己处理；
4、建一个铺满屏幕的根容器当纯黑底板，界面所有控件都挂在它下面；
5、把根容器交给dash_page排整页；

本文件的对外接口有1个：
1、home_dash_ui_main.create()：初始化硬件并搭建整套界面

更多说明参考本目录下的readme.md文件
]]

local exd_st7102_rgb = require "exd_st7102_rgb"
local dash_theme = require "dash_theme"
local dash_page = require "dash_page"

local home_dash_ui_main = {}

-- ==================== 硬件参数 ====================

-- 屏幕分辨率，这块屏是480x480正方形
local SCREEN_W = 480
local SCREEN_H = 480

-- 触摸接线（Air1602 引擎）
-- 触摸和显示集成在ST7102这颗TDDI上，触摸单独走I2C
local TP_I2C_PORT = 1       -- 触摸I2C端口号
local TP_PIN_RST = 46       -- 触摸复位引脚
local TP_PIN_INT = 51       -- 触摸中断引脚
local TP_INT_TYPE = tp.FALLING  -- 中断触发方式，下降沿
local TP_DIRECTION = 0      -- 触摸方向，与屏幕方向一致

-- hzfont字库配置
local FONT_CACHE_SIZE = 2048    -- 字形缓存个数
local FONT_ANTIALIAS = 3        -- 汉字边界采样档位，3是4x4，最锐

-- ==================== 内部函数 ====================

--[[
初始化airui并加载hzfont矢量字库；
airui不负责初始化屏幕，它接管的是已经初始化好的0号屏；
字库只加载一次，重复加载新的配置会被忽略；

@function (内部函数) init_airui

@return boolean, string
成功返回true与"ok"，失败返回false与错误信息字符串
]]
local function init_airui()
    local ok = airui.init(SCREEN_W, SCREEN_H, airui.COLOR_FORMAT_RGB565)
    if not ok then
        return false, "airui.init失败"
    end
    -- antialias是汉字边界的采样档位，1为2x2、2为3x3、3为4x4，取3最锐
    airui.font_load({
        type = "hzfont",
        size = dash_theme.FONT_SIZE.TITLE,
        cache_size = FONT_CACHE_SIZE,
        antialias = FONT_ANTIALIAS,
    })
    log.info("home_dash_ui_main", "airui初始化完成", airui.version())
    return true, "ok"
end

--[[
初始化ST7102触摸并绑定给airui；
绑定之后触摸坐标由airui自己从输入服务取，脚本不需要手动转发坐标，
点配件行、点播放暂停按钮这些交互都由airui处理；

@function (内部函数) init_touch

@return boolean, string
成功返回true与"ok"，失败返回false与错误信息字符串
]]
local function init_touch()
    local tp_config = {
        port = TP_I2C_PORT,
        pin_rst = TP_PIN_RST,
        pin_int = TP_PIN_INT,
        w = SCREEN_W,
        h = SCREEN_H,
        direction = TP_DIRECTION,
        int_type = TP_INT_TYPE,
    }
    local tp_device = tp.init("st7102", tp_config)
    if tp_device == nil then
        return false, "tp.init失败"
    end
    if not airui.device_bind_touch(tp_device) then
        return false, "airui.device_bind_touch失败"
    end
    log.info("home_dash_ui_main", "触摸绑定完成")
    return true, "ok"
end

--[[
建一个铺满屏幕的根容器当纯黑底板；
界面所有控件都挂在根容器下面，根容器的边框宽度取0，
子控件的坐标原点就是屏幕左上角，不需要再内缩；

@function (内部函数) create_root

@return userdata
页面根容器对象
]]
local function create_root()
    local root_obj = airui.container({
        parent = nil,
        x = 0, y = 0, w = SCREEN_W, h = SCREEN_H,
        color = dash_theme.COLOR.BG,
        radius = 0,
        border_width = 0,
    })
    return root_obj
end

-- ==================== 对外接口 ====================

--[[
初始化硬件并搭建整套界面；
先起屏幕，再起airui和字库，然后绑触摸，最后建界面；

@api home_dash_ui_main.create()

@return boolean, string
成功返回true与"ok"，失败返回false与错误信息字符串

@usage
local ok, err = home_dash_ui_main.create()
]]
function home_dash_ui_main.create()
    local ok, err = exd_st7102_rgb.setup()
    if not ok then
        return false, err
    end

    ok, err = init_airui()
    if not ok then
        return false, err
    end

    ok, err = init_touch()
    if not ok then
        return false, err
    end

    local root_obj = create_root()
    if root_obj == nil then
        return false, "根容器创建失败"
    end

    dash_page.create(root_obj)
    log.info("home_dash_ui_main", "界面搭建完成")
    return true, "ok"
end

return home_dash_ui_main
