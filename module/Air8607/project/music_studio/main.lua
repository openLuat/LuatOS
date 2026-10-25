--[[
@module  main
@summary Air8607 音乐播放器（AirUI 界面 + SD 卡歌曲/歌词 + 五种画面风格）
@version 1.0.0
@date    2026.10.23
@board   Air8607 + 10 寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸
         + 内置 DAC + HT6873 功放 + SPI1 SD 卡
         引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位/DISP pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3 (GPIO13)           SD_EN = GPIO74
           AUDIOPA_EN = GPIO73          GT911: I2C1 400kHz, pin_rst = 14, pin_int = 51

=== 功能 ===
1. 音频优先从 SD 卡读取（扫描 /sd/music/、/sd/audio/、/sd/mp3/ 及其一级子目录）；
   没检测到 SD 卡时播放随脚本打包的内置示例 res/Time_travel_8k.mp3。
2. 歌词：自动找与歌曲同名的 .lrc（同目录 / /sd/lyric/ / /sd/lrc/ / /sd/lyrics/）。
3. 播放模式：顺序播放 / 随机播放 / 单曲循环。
4. 上一曲、下一曲、暂停/继续、音量滑块 + 加减键。
5. 播放列表：8 行可视 + 上下翻页 + 点歌名直接播。
6. 中间画面五种风格：唱片模式 / 歌词模式 / 柱状频谱 / 波形频谱 / 玻璃光波。

=== 文件分工 ===
main.lua          本文件：上电时序、显示/触摸/背光初始化、启动顺序
exd_air8607_rgb.lua  10 寸 RGB 屏显示 IC 初始化扩展库（只做显示初始化）
ui_theme.lua      设计令牌：配色 / 布局 / 字号 / 帧率预算
fx_core.lua       绘图工具库：图元对象池 / 颜色 / 文本裁剪
lrc.lua           歌词文件解析与查找
app_audio.lua     音频后端：SD 挂载、播放列表、播放/暂停/切曲、进度、歌词加载
ui_styles.lua     五种画面风格的绘制
ui_main.lua       界面搭建、按键交互、逐帧动画调度

=== 上传 / 烧录 ===
把本目录下全部 .lua 与 res/Time_travel_8k.mp3 平铺添加到脚本区（不需要保留子目录），
入口为 main.lua（PROJECT = "music_studio"）。res/ 被拍平到 /luadb/ 也没关系，
app_audio 会依次探测 /luadb/res/、/luadb/、/res/、/ 等落点。
SD 卡上的歌放在 /sd/music/（推荐）、/sd/audio/、/sd/mp3/ 或 /sd/ 根目录都可以，
歌词放同名 .lrc 在歌曲旁边即可，必须是 UTF-8 编码。

=== 上电顺序（顺序错了会踩坑）===
1. power_on()  供电与引脚：背光 PWM3 占空比 0、LCD 供电、SD_EN、PA 关断、I2C1
2. exd.setup() 显示初始化（复位 + RGB 时序 + 帧缓冲）
3. airui 初始化：init + 字体 + 旋转
4. ui.build()  搭界面（只创建控件）
5. touch_init() GT911 初始化并绑定 airui —— 必须在动画任务之前，
   否则动画每帧 set_items 会跟触摸绑定/首帧重绘撞在启动期，表现为"日志说初始化完成但点不动"
6. 起两个任务：音频初始化、逐帧动画
7. backlight_on() 界面就绪后再点亮背光，防花屏
]]
PROJECT = "music_studio"
VERSION = "1.0.0"

local exd = require "exd_air8607_rgb"
local ui = require "ui_main"
local audio = require "app_audio"

local SCREEN_W, SCREEN_H = 1024, 600

-- 供电、背光 PWM3 上电占空比 0 与 I2C 引脚配置
local function power_on()
    -- 背光 PWM3 先给 0 占空比，UI 就绪后再点亮
    pwm.setup(3, 1000, 0)
    pwm.start(3)
    -- LCD 供电使能（低有效）与 DISP/复位脚
    gpio.setup(17, 0)
    gpio.setup(15, 1)
    -- SD 卡供电使能（SD_EN = GPIO74，高有效）
    gpio.setup(74, 1)
    -- 功放先关断（AUDIOPA_EN = GPIO73，高有效），起播时由音频驱动自动打开
    gpio.setup(73, 0)
    -- GT911 触摸 I2C1（400kHz）
    i2c.setup(1, i2c.FAST)
    sys.wait(100)     -- 等供电稳定
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
与 agri_greenhouse / aurora_ui 在本板验证过的写法一致：
I2C 走 400kHz、不启用轮询模式、tp.init 只调一次。
w/h 必须给：缺了会让 input 适配器以 EINVAL 静默拒绝，表现为"点不动"。
]]
local function touch_init()
    local dev = tp.init("gt911", {
        port = 1,
        pin_rst = 14,
        pin_int = 51,
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

sys.taskInit(function()
    -- 1、供电与引脚
    power_on()

    -- 2、显示初始化（扩展库仅做显示 IC 初始化：复位 + RGB 时序 + 帧缓冲）
    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("main", "显示初始化失败", info)
        return
    end
    log.info("main", "显示初始化完成", info.backend, info.w, info.h)

    -- 3、AirUI 初始化
    airui.init(SCREEN_W, SCREEN_H)
    airui.set_rotation(0)
    -- 界面用了 8 档字号，字形缓存给到 3072（单位是"字形个数"）。
    -- 歌词滚动时若串口出现大量"栅格化"日志、或文字反复重绘，就把这个数调大。
    airui.font_load({ type = "hzfont", size = 16, cache_size = 3072, antialias = 1 })
    -- 打开后每秒会打一条 LVGL 帧率日志；HUD 上的第二个 FPS 数字依赖它。
    -- 嫌串口吵就改 false，HUD 会显示 "FPS 30 / LV --"。
    airui.debug(true)

    -- 4、搭界面
    ui.build(SCREEN_W, SCREEN_H)

    -- 5、触摸初始化 + 绑定（必须在动画任务之前）
    touch_init()

    --[[6、音频初始化放独立任务
    SD 卡挂载 + 扫歌 + 首曲解码要几百毫秒，放在主任务里会挡住动画启动、看起来像卡死。
    界面先跑起来，音频就绪后由 ui.refresh() 把曲名/进度/歌词补上。]]
    sys.taskInit(function()
        local okAudio, err = pcall(audio.init)
        if not okAudio then log.error("main", "音频初始化异常", err) end
        ui.refresh()
        ui.auto_style()
    end)

    -- 6.1 逐帧动画任务（触摸绑定完成后才启动）
    sys.taskInit(function()
        ui.run()
    end)

    -- 7、界面就绪后点亮背光
    backlight_on()
    log.info("main", "音乐播放器已就绪", PROJECT, VERSION)
end)

sys.run()
