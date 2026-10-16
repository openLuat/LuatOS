--[[
@module  boot_ui
@summary 开机快速点亮 + 延迟初始化编排：display就绪→logo+背光→供电就绪→分批加载→通知播hzv
@version 1.3
@date    2026.10.15
@author  江访

=== 执行流程 ===

require "boot_ui" 即启动 boot_task 协程（main.lua 阶段4）：

  0. fskv 初始化 → settings_display_app.restore() 恢复音量/亮度到配置表
  1. lcd_drv.init()             → display + AirUI 初始化（屏幕尺寸/字体/旋转/密度）
  2. OPEN_WELCOME_WIN           → welcome 进入 LOGO 阶段（黑底 + logo，不开播）
  3. sys.wait(100) → backlight_on() → logo 首帧上屏后再开背光（亮度取恢复值）
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

--[[音频 I2C 守护（触摸总线兜底）：
1) exaudio.setup 记忆化，只执行首次 —— audio_setup 每次都会 i2c.setup(codec总线)，
   把触摸总线重置回中断模式（丢轮询设置），TTS/试听/录音的重复 setup 全部挡住；
   首次成功后恢复一次触摸总线配置，失败不记账（下次可重试）。
2) play_start/play_stop/record_start/pm 入口包一层，调用后立即恢复 ——
   旧版 exaudio 的 pm(SHUTDOWN) 会关闭 I2C1（v3.3 已修），mp4 起播前的
   play_stop 也走这条路，兜住固件内旧版 exaudio。
exaudio 若是固件 rotable（不可写表），包不上则 log.warn 提示、行为不劣化。]]
local function guard_audio_init()
    local ok, exaudio = pcall(require, "exaudio")
    if not (ok and exaudio) then return end
    local t = type(exaudio)
    if t ~= "table" and t ~= "userdata" then return end

    local function restore()
        if _G.tp_drv and _G.tp_drv.i2c_restore then
            pcall(_G.tp_drv.i2c_restore)
        end
    end

    -- setup 仅首次执行，成功后恢复一次触摸总线配置
    local raw_setup = exaudio.setup
    if type(raw_setup) == "function" then
        local setup_done = false
        local ok1 = pcall(function()
            exaudio.setup = function(cfg)
                if setup_done then return true end
                local r = raw_setup(cfg)
                if r then
                    setup_done = true
                    restore()
                    log.info("boot_ui", "音频初始化完成，触摸 I2C 配置已定型")
                end
                return r
            end
        end)
        if ok1 then log.info("boot_ui", "exaudio.setup 已收口：仅首次初始化") end
    end

    -- 音频播录/电源入口调用后恢复触摸总线配置
    local wrapped = 0
    for _, fname in ipairs({ "play_start", "play_stop", "record_start", "pm" }) do
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
    log.info("boot_ui", "exaudio 音频入口守护已挂", wrapped, "个入口")
end

local function boot_task()
    -- 0. 先初始化 fskv，再做其余初始化：恢复用户音量/背光亮度写回配置表
    --    （hw.audio.play_vol / hw.lcd.backlight.level），背光点亮与后续起播直接使用；
    --    fskv 挂载是异步的，未就绪时 settings_display_app 内后台短轮询重试
    pcall(fskv.init)
    pcall(function() require("settings_display_app").restore() end)

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

    -- 5.5 音频 I2C 守护：setup 仅首次执行，音频入口调用后恢复 tp 总线配置
    pcall(guard_audio_init)

    -- 6. 其余初始化：与 logo 展示并行，批间让出循环保证 logo 刷新不卡
    ok, err = pcall(require, "app_main")
    if not ok then
        log.error("boot_ui", "app_main 加载失败", err)
    end
    ok, err = pcall(require, "ui_main")
    if not ok then
        log.error("boot_ui", "ui_main 加载失败", err)
    end

    -- 7. 主题恢复（原 init_ui_task 语义：app_main 已跑完、无页面构建，直接改令牌即可）
    pcall(function() require("ui_theme").restore() end)

    -- 8. 通知 welcome 进入 VIDEO 阶段
    _G.__boot_init_done = true
    sys.publish("BOOT_INIT_DONE")
end

sys.taskInit(boot_task)
