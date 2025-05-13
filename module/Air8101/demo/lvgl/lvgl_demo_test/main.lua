-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lvgl_demo_test"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
_G.symbol = require "symbol"

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local lcd_use_buff = false  -- 是否使用缓冲模式, 提升绘图效率，占用更大内存

local rtos_bsp = rtos.bsp()
local chip_type = hmeta.chip()
-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
function lcd_pin()
    if string.find(rtos_bsp,"Air8101") then
        lcd_use_buff = true -- RGB仅支持buff缓冲模式
        return lcd.RGB,36,0xff,0xff,25
    else
        log.info("main", "bsp not support")
        return
    end
end

local spi_id,pin_reset,pin_dc,pin_cs,bl = lcd_pin()

if spi_id ~= lcd.HWID_0 and spi_id ~= lcd.RGB then
    spi_lcd = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)
    port = "device"
else
    port = spi_id
end

if spi_id == lcd.RGB then
    -- -- Air8101开发板配套LCD屏幕 分辨率800*480
    -- lcd.init("h050iwv",
    --         {port = port, pin_dc = 0xff, pin_pwr = bl, pin_rst = pin_reset,
    --         direction = 0, w = 800, h = 480, xoffset = 0, yoffset = 0})

    -- -- Air8101开发板配套LCD屏幕 分辨率1024*600
    -- lcd.init("hx8282",
    --         {port = port,pin_pwr = bl, pin_rst = pin_reset,
    --         direction = 0,w = 1024,h = 600,xoffset = 0,yoffset = 0})

    -- Air8101开发板配套LCD屏幕 分辨率720*1280
    lcd.init("nv3052c",
            {port = port,pin_pwr = bl, pin_rst = pin_reset,
            direction = 0,w = 720,h = 1280,xoffset = 0,yoffset = 0})

    -- -- Air8101开发板配套LCD屏幕 分辨率480*854
    -- lcd.init("st7701sn",
    --         {port = port,pin_pwr = bl, pin_rst = pin_reset,
    --         direction = 0,w = 480,h = 854,xoffset = 0,yoffset = 0})
end


-- LVGL（Light and Versatile Graphics Library）的各种 UI 组件（Widgets）的演示模块。
-- 以下是每个模块对应的 LVGL 组件及其用途：
-- 模块名                  LVGL 组件                   功能描述
-- arc_demo                圆弧 (Arc)                  用于显示进度或旋钮控制（如音量调节）。
-- bar_demo                进度条 (Bar)                水平/垂直进度条，展示加载或数值范围。
-- btn_demo                按钮 (Button)               基础点击交互按钮。
-- btnmatrix_demo          按钮矩阵 (Button Matrix)    网格状排列的多个按钮（如键盘布局）。
-- calendar_demo           日历 (Calendar)             日期选择组件。
-- canvas_demo             画布 (Canvas)               自定义绘制图形/图像的低级绘图接口。
-- checkbox_demo           复选框 (Checkbox)           二元选择框（勾选/未勾选）。
-- chart_demo              图表 (Chart)                显示折线图、柱状图等数据可视化。
-- cont_demo               容器 (Container)            布局容器，用于自动排列子组件。
-- cpicker_demo            颜色选择器 (Color Picker)   允许用户选择颜色值。
-- dropdown_demo           下拉菜单 (Dropdown)         点击后展开选项列表的选择组件。
-- gauge_demo              仪表盘 (Gauge)              模拟仪表（如速度表、温度计）。
-- img_demo                图像 (Image)                显示位图或图标。
-- imgbtn_demo             图像按钮 (Image Button)     使用图片作为按钮的交互元素。
-- label_demo              标签 (Label)                显示静态或动态文本。
-- led_demo                LED 指示灯 (LED)            模拟 LED 灯的开关状态指示。
-- line_demo               线条 (Line)                 绘制直线图形。
-- list_demo               列表 (List)                 垂直/水平滚动列表容器。
-- lmeter_demo             线性量表 (Line Meter)       线性比例指示器（如电池电量条）。
-- msdbox_demo             消息框 (Message Box)        弹出对话框显示提示信息（确认/取消）。
-- objmask_demo            对象遮罩 (Object Mask)      对组件应用遮罩效果（裁剪/透明）。
-- page_demo               页面 (Page)                 可滚动的容器，用于管理复杂布局。
-- roller_demo             滚轮 (Roller)               滚动选择器（如时间选择）。
-- slider_demo             滑块 (Slider)               拖动滑块选择数值范围。
-- spinbox_demo            数字输入框 (Spinbox)        带加减按钮的数字输入控件。
-- spinner_demo            加载动画 (Spinner)          旋转指示器，表示加载中状态。
-- switch_demo             开关 (Switch)               切换开关（如 ON/OFF 状态）。
-- table_demo              表格 (Table)                显示行列数据（类似电子表格）。
-- tabview_demo            标签页 (Tab View)           多标签页容器，切换不同内容视图。
-- textarea_demo           文本域 (Text Area)          多行文本输入框（支持编辑）。
-- tileview_demo           平铺视图 (Tile View)        滑动平铺页面（如手机主屏幕）。
-- win_demo                窗口 (Window)               带标题栏和内容区域的窗口容器。

local arc = require "arc_demo"
local bar = require "bar_demo"
local btn = require "btn_demo"
local btnmatrix = require "btnmatrix_demo"
local calendar = require "calendar_demo"
local canvas = require "canvas_demo"
local checkbox = require "checkbox_demo"
local chart = require "chart_demo"
local cont = require "cont_demo"
local cpicker = require "cpicker_demo"
local dropdown = require "dropdown_demo"
local gauge = require "gauge_demo"
local img = require "img_demo"
local imgbtn = require "imgbtn_demo"
local label = require "label_demo"
local led = require "led_demo"
local line = require "line_demo"
local list = require "list_demo"
local lmeter = require "lmeter_demo"
local msdbox = require "msdbox_demo"
local objmask = require "objmask_demo"
local page = require "page_demo"
local roller = require "roller_demo"
local slider = require "slider_demo"
local spinbox = require "spinbox_demo"
local spinner = require "spinner_demo"
local switch = require "switch_demo"
local table = require "table_demo"
local tabview = require "tabview_demo"
local textarea = require "textarea"
local tileview = require "tileview_demo"
local win = require "win_demo"

sys.taskInit(function ()
    -- 开启缓冲区, 刷屏速度回加快, 但也消耗2倍屏幕分辨率的内存
    if lcd_use_buff then
        lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
        -- lcd.setupBuff()       -- 使用lua内存, 只需要选一种
        lcd.autoFlush(false)
    end
    -- sys.wait(5000)
    log.info("lvgl", lvgl.init())

    if tp then
        softI2C = i2c.createSoft(8, 5)
        tp_device =  tp.init("gt911",{port=softI2C,pin_rst = 9,pin_int = 6,w = 720,h = 1280})
        lvgl.indev_drv_register("pointer", "touch", tp_device)
    end

    -- arc.demo1()
    -- arc.demo2()
    -- bar.demo()
    -- btn.demo1()
    -- btn.demo2()
    -- btnmatrix.demo()
    -- calendar.demo()
    -- canvas.demo()
    -- checkbox.demo()
    -- chart.demo1()
    -- chart.demo2()
    -- cont.demo()
    -- cpicker.demo()
    -- dropdown.demo1()
    -- dropdown.demo2()
    -- gauge.demo1()
    -- img.demo()
    -- imgbtn.demo()
    -- label.demo()
    -- led.demo()
    -- line.demo()
    -- list.demo()
    -- lmeter.demo()
    -- msdbox.demo()
    -- objmask.demo()
    -- page.demo()
    -- roller.demo()
    -- slider.demo()
    -- spinbox.demo()
    -- spinner.demo()
    -- switch.demo()
    -- table.demo()
    -- tabview.demo()
    -- textarea.demo()
    -- tileview.demo()
    win.demo()

    while true do
        sys.wait(1000)
    end
end)

sys.run()
