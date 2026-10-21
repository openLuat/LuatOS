--[[
@module  main
@summary AirUI 视觉特效演示（Air8607 + 10寸 RGB 屏 1024x600 + GT911 触摸）
@version 1.0
@date    2026.10.21
@board   Air8607 + 10寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸
         硬件引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3 (GPIO13)      触摸 I2C1 (400kHz) pin_rst = 14 pin_int = 51
@boot
1、power_on()      —— 供电/背光 PWM3 占空比 0/I2C 引脚配置
2、exd.setup()     —— 显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui 初始化    —— init + 字体加载 + 旋转
4、ui.build()      —— 搭建演示界面（顶栏 HUD + 特效舞台 + 场景切换栏）
5、ui.run()        —— 启动逐帧动画任务（约 30fps，shape:set_items 重绘舞台）
6、touch_init()    —— GT911 触摸初始化 + airui 绑定（可点击切换场景）
7、backlight_on()  —— 界面就绪后点亮背光，防花屏
@note
本演示全部视觉都由 airui.shape 的 line/circle/rect 图元实时计算生成，
不依赖任何图片资源；切换场景只隐藏/显示对应容器，不销毁对象。
]]
PROJECT = "airui_showcase"
VERSION = "1.0.0"

-- 加载 10寸 RGB 显示IC初始化扩展库
local exd = require "exd_air8607_rgb"
local ui = require "ui_showcase"

local SCREEN_W, SCREEN_H = 1024, 600

-- 供电、背光 PWM3 上电占空比 0 与 I2C 引脚配置
local function power_on()
    -- 背光 PWM3 上电占空比 0（UI 就绪后再点亮，防花屏）
    pwm.setup(3, 1000, 0)
    pwm.start(3)
    -- LCD 供电使能（低有效，先关闭）
    gpio.setup(17, 0)
    -- LCD 显示使能/复位脚拉高
    gpio.setup(15, 1)
    -- GT911 触摸 I2C1 总线（与 agri_greenhouse 一致：400kHz，不启用轮询模式）
    i2c.setup(1, i2c.FAST)
    sys.wait(100)   -- 等供电稳定
end

-- 背光点亮（PWM3 调光）
local function backlight_on()
    if pwm.setup(3, 1000, 100) then
        pwm.start(3)
        log.info("main", "背光已点亮")
    else
        log.error("main", "背光初始化失败，请确认 PWM 通道与原理图一致")
    end
end

--[[GT911 触摸初始化 + airui 绑定
完全对齐已在本板跑通的 module/Air8607/project/agri_greenhouse/code/main.lua：
I2C 走 400kHz、不启用轮询模式、tp.init 只调一次、按钮用 on_click。

之前试过 100kHz + 轮询模式 + 失败重试，反而连"初始化完成"都读到日志了却点不动，
说明方向错了（那是工厂工程 i2c 参数，不是本板验证过的写法）。
w/h 必须给：缺了会让 input 适配器以 EINVAL 静默拒绝。
]]
local function touch_init()
    local dev = tp.init("gt911", {
        port = 1,             -- I2C1
        pin_rst = 14,         -- TP_RESET
        pin_int = 51,         -- TP_INT
        int_type = tp.FALLING,
        w = SCREEN_W,
        h = SCREEN_H,
    })
    if dev then
        airui.device_bind_touch(dev)
        log.info("main", "GT911 触摸初始化完成")
        return true
    end
    log.error("main", "触摸初始化失败")
    return false
end

-- 主任务：初始化显示与触摸后进入特效演示界面
sys.taskInit(function()
    -- 1、供电与引脚配置
    power_on()

    -- 2、显示初始化（扩展库仅做显示IC初始化：复位 + RGB 时序 + 帧缓冲）
    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("main", "显示初始化失败", info)
        return
    end
    log.info("main", "显示初始化完成", info.backend, info.w, info.h)

    -- 3、AirUI 初始化：分辨率 + 字体 + 旋转
    airui.init(SCREEN_W, SCREEN_H)
    airui.set_rotation(0)
    airui.font_load({ type = "hzfont", size = 16, cache_size = 2048, antialias = 1 })

    --[[ 开启 AirUI 内置性能统计
    HUD 上「FPS 29/28」的第二个数字来自 airui.debug()，它是 LVGL 真实的画面刷新率；
    第一个数字是本脚本的动画更新率。两者对比即可判断慢在哪：
      计算耗时高 + 两个 FPS 都低  -> 脚本侧吃亏
      计算耗时低 + LVGL FPS 低     -> 渲染/刷屏侧吃亏
    这个计数器只在 debug(true) 时才统计，关掉会一直读 0。会每秒打一条日志，
    定位完问题可以改成 airui.debug(false) 减少串口输出。]]
    airui.debug(true)

    -- 4、搭建演示界面（只创建控件，不启动动画）
    ui.build(SCREEN_W, SCREEN_H)

    --[[5、触摸初始化 + airui 绑定
    必须放在动画任务之前。之前是先 sys.taskInit(ui.run) 再 touch_init，
    动画任务会抢在绑定完成前就开始每帧 shape:set_items()，
    触摸绑定与 LVGL 重绘在启动期撞在一起，表现为"日志说初始化完成但点不动"。
    参考工程 agri_greenhouse 就是先 build + touch_init，最后才起刷新任务。]]
    touch_init()

    --[[触摸诊断：用来判断触摸卡在哪一环
    state: 0=无 1=按下 2=保持 3=抬起    x/y 是 AirUI 逻辑坐标
    对照方法：
      点按钮时一条 TP 日志都没有   -> 触摸没进 AirUI，问题在驱动/中断/绑定
      有日志但 y 不在 522~588      -> 坐标映射不对
      有日志、坐标也对但不切场景   -> 按钮被上层控件遮挡
    定位完把 TP_DEBUG 改成 false，避免串口被刷屏。]]
    local TP_DEBUG = true
    if TP_DEBUG and airui.touch_subscribe then
        local n = 0
        local ok = airui.touch_subscribe(function(state, x, y)
            n = n + 1
            if n % 5 == 1 then     -- 按住移动时事件很密，抽 1/5 打印
                log.info("TP", "state=" .. tostring(state),
                    "x=" .. tostring(x), "y=" .. tostring(y))
            end
        end)
        if not ok then log.warn("main", "触摸诊断订阅失败") end
    end

    -- 6、触摸绑定完成后，再启动逐帧动画任务
    sys.taskInit(function()
        ui.run()
    end)

    -- 7、界面就绪后点亮背光
    backlight_on()
    log.info("main", "AirUI 视觉特效演示已就绪")
end)

sys.run()
