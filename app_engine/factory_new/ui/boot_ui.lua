--[[
@module  boot_ui
@summary 开机快速点亮 + 延迟初始化编排：display就绪→logo+背光→供电就绪→分批加载→通知播hzv
@version 1.2
@date    2026.09.26
@author  江访

=== 执行流程 ===

require "boot_ui" 即启动 boot_task 协程（main.lua 阶段4）：

  1. lcd_drv.init()             → display + AirUI 初始化（屏幕尺寸/字体/旋转/密度）
  2. OPEN_WELCOME_WIN           → welcome 进入 LOGO 阶段（黑底 + logo，不开播）
  3. sys.wait(100) → backlight_on() → logo 首帧上屏后再开背光
  4. 等 POWER_ON_DONE           → 上电序列（含各步 delay 稳定时间）全部完成才碰 I2C
  5. tp_drv.init()              → 触摸初始化（失败 200ms 后重试一次）
  6. 分批 require app_main / ui_main → 业务与 UI 窗口（批间 sys.wait(0) 让 logo 刷新不卡）
  7. ui_theme.restore()         → 主题恢复（此时无页面构建，直接改令牌即可）
  8. _G.__boot_init_done + BOOT_INIT_DONE → welcome 进入 VIDEO 阶段播 hzv

订阅: POWER_ON_DONE（platform_loader 上电序列完成）
发布: OPEN_WELCOME_WIN（LOGO 阶段） / BOOT_INIT_DONE（初始化完成，粘性标记 _G.__boot_init_done）

=== 关键设计 ===

1. 「点亮屏幕」从初始化链尾提到链头：黑屏时长只剩固件启动 + display init 固定开销，
   其余初始化与 logo 展示并行，不增加总时长

2. BOOT_INIT_DONE 语义 = 模块全部加载 + TP 就绪 + 主题已恢复。
   **绝不等待网络**（IP_READY/NTP/天气本就异步事件驱动），否则没网环境永远进不了桌面

3. 粘性标记 _G.__boot_init_done 双保险：正常时序 welcome 先创建、事件后到不会丢；
   即便事件早于窗口创建，welcome.on_create 查粘性标记补开播

4. app_main / ui_main 的 require 是源码文本中的静态语句，编译系统文本扫描即可打包
   （与 features 门控里的 require "llm_chat" 同一机制）。
   **不可登记进 platform_loader 编译清单**：清单 require 在 platform_loader 顶部
   立即执行，此刻 project_config 尚未加载，app_main 的 features 门控将全部落空，
   且 require 缓存后不会二次执行，造成特性静默丢失

5. 全链 pcall 装甲：任何一段抛错都只丢该段（log.error），不拖垮后续
   （tp/分批加载/BOOT_INIT_DONE 仍会执行）——单点异常不再表现为"触摸死了/进不了桌面"

6. **触摸初始化以 POWER_ON_DONE 为门**：I2C 总线上未上电的设备会钳住 SDA/SCL，
   GT911 电源未稳时 tp.init 会软失败（只 log 一行），静默变成"触摸完全失灵"。
   power_on 序列的电源稳定时间（各步 delay）与 logo 展示并行消化，不占关键路径；
   旧版 tp init 排在几十个 require 之后（≈上电+2s）天然满足，提速后必须显式等。
   门内 1s 兜底超时防 power_on 异常时永久卡在 logo；GT911 自身上电余量由失败重试兜底
]]

-- 提前加载欢迎页：LOGO 阶段零主题依赖（黑底用字面量，不 require ui_theme）
require "welcome_win"

-- logo 首帧上屏余量：airui 首帧刷新是异步的，RGB 帧缓冲跨热复位不清屏，
-- 背光早于首帧会把上一次会话的残留画面（如 hzv 定格帧）闪给用户。
-- 个别屏首帧慢可调到 150~200；代价只是背光晚亮几十 ms。
local BOOT_BACKLIGHT_DELAY_MS = 100

--[[触摸总线守护：exaudio 的 audio_setup() 无条件 i2c.setup(codec总线, i2c.FAST)，
会把触摸总线重置回中断模式（丢轮询设置）→ 音频播放（DMA 中断风暴）期间
I2C 传输出错，表现为"播放音频就 I2C 报错，不管有没有触摸"。

给 exaudio 的入口包一层：每次调用后立即恢复 tp 总线配置（速率 + 轮询）。
exaudio 若是固件 rotable（不可写表），包不上则 log.warn 提示、行为不劣化。
根治需改 exaudio 的 audio_setup：仅 codec model 需要 I2C 时才 i2c.setup。]]
local function guard_tp_bus()
    local ok, exaudio = pcall(require, "exaudio")
    if not (ok and exaudio and type(exaudio) == "table") then return end
    if rawget(exaudio, "__tp_bus_guard") then return end

    local function restore()
        if _G.tp_drv and _G.tp_drv.i2c_restore then
            pcall(_G.tp_drv.i2c_restore)
        end
    end

    local wrapped = 0
    for _, fname in ipairs({ "setup", "play_start", "record_start", "pm" }) do
        local raw = exaudio[fname]
        if type(raw) == "function" then
            local raw_fn = raw
            local ok2 = pcall(function()
                exaudio[fname] = function(...)
                    local r = raw_fn(...)
                    restore()
                    return r
                end
            end)
            if ok2 then wrapped = wrapped + 1 end
        end
    end
    pcall(function() exaudio.__tp_bus_guard = true end)
    log.info("boot_ui", "exaudio 触摸总线守护已挂", wrapped, "个入口")
end

local function boot_task()
    -- 1. display + airui 初始化（拿到屏幕尺寸/字体/旋转/密度）
    local ok, err = pcall(lcd_drv.init)
    if not ok then
        log.error("boot_ui", "lcd_drv.init 失败", err)
    end

    -- 2. 进入 welcome 的 LOGO 阶段（黑底 + logo 图，不开播视频）
    --    pcall 装甲：on_create 抛错不拖垮启动链（tp/分批加载照常）
    ok, err = pcall(function() sys.publish("OPEN_WELCOME_WIN") end)
    if not ok then
        log.error("boot_ui", "LOGO 阶段创建失败", err)
    end

    -- 3. 等 logo 首帧刷上屏再开背光，避免用户看到残留画面/清屏过程
    sys.wait(BOOT_BACKLIGHT_DELAY_MS)
    pcall(lcd_drv.backlight_on)

    -- 4. 等上电序列全部完成（含 power_on 各步 delay 的电源稳定时间）再碰 I2C。
    --    粘性标记防事件早于订阅丢失；1s 兜底防 power_on 异常卡死
    if not _G.__power_on_done then
        sys.waitUntil("POWER_ON_DONE", 1000)
        if not _G.__power_on_done then
            log.warn("boot_ui", "POWER_ON 未在 1s 内完成，继续初始化触摸")
        end
    end

    -- 5. 触摸初始化：失败 200ms 后重试一次（GT911 电源刚稳仍可能需要余量）
    local ok2, r = pcall(tp_drv.init)
    if not (ok2 and r) then
        log.warn("boot_ui", "tp 初始化未成功，200ms 后重试", ok2 and r or r)
        sys.wait(200)
        pcall(tp_drv.init)
    end

    -- 5.5 触摸总线守护：exaudio 入口包一层，音频初始化后自动恢复 tp 总线配置
    pcall(guard_tp_bus)

    -- 6. 其余初始化：与 logo 展示并行，批间让出循环保证 logo 刷新不卡
    ok, err = pcall(require, "app_main")
    if not ok then
        log.error("boot_ui", "app_main 加载失败", err)
    end
    sys.wait(0)
    ok, err = pcall(require, "ui_main")
    if not ok then
        log.error("boot_ui", "ui_main 加载失败", err)
    end
    sys.wait(0)

    -- 7. 主题恢复（原 init_ui_task 语义：app_main 已跑完、无页面构建，直接改令牌即可）
    pcall(function() require("ui_theme").restore() end)

    -- 8. 通知 welcome 进入 VIDEO 阶段
    _G.__boot_init_done = true
    sys.publish("BOOT_INIT_DONE")
end

sys.taskInit(boot_task)
