_G.SIP_DIAG_QUIET_CALL = true -- CALL-LUA-QUIET1: defer call summaries until bridge stops
--[[
@module  boot_ui
@summary 开机快速点亮 + 延迟初始化编排：display就绪→logo+背光→核心批→直接进桌面
@version 2.0
@date    2026.10.16
@author  江访

=== 执行流程 ===

require "boot_ui" 即启动 boot_task 协程（main.lua 阶段4）：

  0. fskv 初始化（挂载是异步的，未就绪时 settings_display_app 内后台短轮询重试）
  1. lcd_drv.hw_init()          → display 硬件初始化（FrameBuffer 分配、RGB 时序/IC 序列）
  2. lcd_drv.airui_init()       → airui.init 引擎初始化（旋转/尺寸/密度，不含字体）
  3. logo_show()                → 裸 airui 形状画黑底 + 合宙 logo（128×128 居中）
  4. restore_brightness()       → 恢复背光亮度写回配置表（backlight_on 点亮取该值）
  5. sys.wait(背光余量) → backlight_on() → 首帧上屏后延时开背光：
     10寸 100ms / 7寸 200ms（防闪屏，见 BOOT_BACKLIGHT_DELAY_BY_SIZE）

  —— 显示完成，以下全部在 logo 展示期间进行 ——

  6. exwin/exapp 加载（窗口管理 + 应用沙箱；exapp 会扫描各存储应用列表）
  7. 等 POWER_ON_DONE → tp_drv.init()（失败 200ms 重试一次）
  8. 启动可选批 optional_task（音量恢复/网络/音频/SD/NES/UVC/HID 等，独立协程并行）
  9. lcd_drv.airui_core_init()  → 字体加载等核心初始化（读字库建 cache，最重的一步）
 10. 分批 require app_main.core() / ui_main.core() → 桌面与核心设置窗口（批间 sys.wait(0)）
 11. ui_theme.restore() → publish OPEN_IDLE_WIN → 销毁 logo 形状
     （FB 里仍是 logo 帧，桌面首帧覆盖即完成交接，不闪屏）

订阅: POWER_ON_DONE（platform_loader 上电序列完成）
发布: OPEN_IDLE_WIN（核心批就绪进桌面；可选批仍在后台加载）

=== 关键设计 ===

1. 首亮关键路径只剩：display 硬件初始化 + airui.init + logo 一帧 + 背光余量
   （10寸 100ms / 7寸 200ms）。字体（airui_core_init 读字库）与几十个模块
   require 全部与 logo 展示并行

2. logo 用裸 airui 形状绘制：不建 exwin 窗口、不依赖字体（图片渲染与字体无关）、
   不依赖 welcome 页面。资源缺失只显示黑底

3. OPEN_IDLE_WIN 只等核心批（桌面 + 核心设置可用），可选批（网络/音频/云/外设）
   独立协程后台加载。入口图标只看 project_config，窗口与业务层成对同批加载

4. app_main / ui_main 的 require 是源码文本中的静态语句，编译系统文本扫描即可打包
   （与 features 门控里的 require "llm_chat" 同一机制），无需登记 platform_loader
   编译清单；清单已包进永不调用的函数，登记也不会再被提前执行

5. 全链 pcall 装甲：任何一段抛错都只丢该段（log.error），不拖垮后续
   （tp/字体/分批加载/进桌面仍会执行）——单点异常不再表现为"触摸死了/进不了桌面"

6. 触摸初始化以 POWER_ON_DONE 为门：I2C 总线上未上电的设备会钳住 SDA/SCL，
   GT911 电源未稳时 tp.init 会软失败（只 log 一行），静默变成"触摸完全失灵"。
   门内 1s 兜底超时防 power_on 异常时永久卡在 logo；GT911 自身上电余量由失败重试兜底

7. 启动顺序原则：点亮前的关键路径只保留「引脚 / 上电 / fskv / display+logo+背光」，
   其余一切（exwin/exapp、音频、网络、字体、各业务模块）全部在显示完成之后进行
]]

-- logo 尺寸（1:1 居中显示，不缩放）
local LOGO_SIZE = 128
local sip_isolation = _G.SIP_ISOLATION_TEST == true
local recovery_stage = _G.SIP_RECOVERY_STAGE or "R0"
if sip_isolation and recovery_stage ~= "R0" and recovery_stage ~= "R1" and recovery_stage ~= "R2" and recovery_stage ~= "R3" and recovery_stage ~= "R4" and (recovery_stage ~= "R5" and (recovery_stage ~= "R6" and recovery_stage ~= "R7")) then
    log.error("sip_isolation", "UNSUPPORTED_STAGE", recovery_stage)
    error("SIP recovery stage not implemented: " .. tostring(recovery_stage))
end

-- logo 首帧上屏余量：airui 首帧刷新是异步的，RGB 帧缓冲跨热复位不清屏，
-- 背光早于首帧会把上一次会话的残留画面闪给用户（闪屏）。
-- 按屏幕尺寸取值：10寸 100ms、7寸 200ms；未列尺寸默认 100ms，真机闪屏时按表补
local BOOT_BACKLIGHT_DELAY_BY_SIZE = {
    [10] = 100,
    [7]  = 200,
}

local bg_shape
local logo_img

-- 画开机 logo：黑色全屏背景 + logo 图居中（裸 airui 形状，零字体/主题依赖）
local function logo_show()
    bg_shape = airui.shape({
        x = 0, y = 0, w = _G.screen_w, h = _G.screen_h,
        items = {
            { type = "rect", x = 0, y = 0, w = _G.screen_w, h = _G.screen_h,
              fill = true, fill_color = 0x000000, color = 0x000000 },
        },
    })

    -- logo 居中 1:1 显示；资源缺失只显示黑底
    local logo_path = nil
    for _, p in ipairs({ "/luadb/logo.png", "/logo.png" }) do
        if io.exists(p) then
            logo_path = p
            break
        end
    end
    if logo_path then
        logo_img = airui.image({
            x = math.floor((_G.screen_w - LOGO_SIZE) / 2),
            y = math.floor((_G.screen_h - LOGO_SIZE) / 2),
            w = LOGO_SIZE, h = LOGO_SIZE,
            src = logo_path,
        })
        log.info("boot_ui", "LOGO 显示", logo_path)
    else
        log.warn("boot_ui", "logo 资源缺失，仅显示黑底")
    end
end

-- 销毁 logo 形状释放资源（FB 保留 logo 帧，桌面首帧自然覆盖）
local function logo_hide()
    if logo_img then
        pcall(logo_img.destroy, logo_img)
        logo_img = nil
    end
    if bg_shape then
        pcall(bg_shape.destroy, bg_shape)
        bg_shape = nil
    end
end

-- 可选批：独立协程与字体/核心批并行加载（功能开关门控，见 app_main.optional）
local function optional_task()
    -- 媒体音量恢复（含 exaudio 懒加载，显示之后才进入音频域）
    pcall(function() require("settings_display_app").restore_volume() end)
    local ok, err = pcall(function() require("app_main").optional() end)
    if not ok then
        log.error("boot_ui", "可选业务批加载失败", err)
    end
    sys.wait(0)
    ok, err = pcall(function() require("ui_main").optional() end)
    if not ok then
        log.error("boot_ui", "可选窗口批加载失败", err)
    end
end

local function boot_task()
    -- 0. fskv 初始化（挂载是异步的，未就绪时 settings_display_app 内后台短轮询重试）
    pcall(fskv.init)

    -- 1. display 硬件初始化（FrameBuffer 分配、RGB 时序/IC 序列）
    local ok, err = pcall(lcd_drv.hw_init)
    if not ok then
        log.error("boot_ui", "lcd_drv.hw_init 失败", err)
    end

    -- 2. airui.init 引擎初始化（旋转/尺寸/密度，不含字体）
    ok, err = pcall(lcd_drv.airui_init)
    if not ok then
        log.error("boot_ui", "airui_init 失败", err)
    end

    -- 3. 画开机 logo（裸 airui 形状，黑底 + logo 居中）
    ok, err = pcall(logo_show)
    if not ok then
        log.error("boot_ui", "logo 显示失败", err)
    end

    -- 4. 恢复背光亮度写回配置表（backlight_on 点亮取该值作占空比）
    pcall(function() require("settings_display_app").restore_brightness() end)

    -- 5. logo 首帧上屏后再开背光（余量按屏幕尺寸，防 RGB 残留闪屏）
    sys.wait(BOOT_BACKLIGHT_DELAY_BY_SIZE[_G.screen_size or 5.0] or 100)
    pcall(lcd_drv.backlight_on)

    -- 6. exwin/exapp 加载（显示之后的第一件事：exapp require 时会扫描各存储应用列表）
    ok, err = pcall(function()
        exwin = require "exwin"
        if not sip_isolation then exapp = require "exapp" end
    end)
    if not ok then
        log.error("boot_ui", "exwin/exapp 加载失败", err)
    end

    -- 7. 等上电序列全部完成（含 power_on 各步 delay 的电源稳定时间）再碰 I2C。
    --    粘性标记防事件早于订阅丢失；1s 兜底防 power_on 异常卡死
    if not _G.__power_on_done then
        sys.waitUntil("POWER_ON_DONE", 1000)
        if not _G.__power_on_done then
            log.warn("boot_ui", "POWER_ON 未在 1s 内完成，继续初始化触摸")
        end
    end

    -- 8. 触摸初始化：失败 200ms 后重试一次（GT911 电源刚稳仍可能需要余量）。
    --    tp_gt911.init 成功即封口（内核 tp 库一次上电只接受一次 tp.init），
    --    所以这里的重试只会在首次真的失败时发生，不会造成重复初始化
    local ok2, r = pcall(tp_drv.init)
    if not (ok2 and r) then
        log.warn("boot_ui", "tp 初始化未成功，200ms 后重试", ok2 and r or r)
        sys.wait(200)
        pcall(tp_drv.init)
    end

    -- 9. 可选批独立协程并行加载（音量恢复/网络/音频/SD/NES/UVC/HID，不阻塞进桌面）
    if not sip_isolation then sys.taskInit(optional_task) end

    -- 10. 字体加载等核心初始化（读字库建 cache，初始化中最重的一步，与可选批并行消化）
    ok, err = pcall(lcd_drv.airui_core_init)
    if not ok then
        log.error("boot_ui", "airui_core_init 失败", err)
    end

    if sip_isolation then
        log.warn("sip_isolation", "ENABLED", recovery_stage, _G.FACTORY_FULL_TEST and "R7 startup baseline; full peripheral tests on demand" or "SIP-only business startup; audio bridge v7 unchanged")
        -- 看门狗先启动；网络初始化可能等待 AirLink 对端就绪。
        local cfg = _G.project_config or {}
        if (cfg.features or {}).wdt then require "watchdog_app" end
        -- 保持原有音量/主题设置，避免对照时改变声音和绘制参数。
        pcall(function() require("settings_display_app").restore_volume() end)
        require "ui_theme_themes"
        pcall(function() require("ui_theme").restore() end)
        local net_manager = require "net_manager"
        require "net_init"
        local net_ok, net_err = pcall(net_manager.init, cfg)
        if not net_ok then log.error("sip_isolation", "network init failed", net_err) end
        -- 累加恢复已通过的分组，保留 R0 网络/音频初始化路径。
        local group_ok = net_ok
        local function load_member(name, loader)
            local loaded, load_err = pcall(loader)
            if loaded then
                log.info("sip_isolation", recovery_stage, "LOADED", name)
            else
                group_ok = false
                log.error("sip_isolation", recovery_stage, "LOAD_FAILED", name, load_err)
            end
            return loaded
        end
        if recovery_stage == "R1" or recovery_stage == "R2" or recovery_stage == "R3" or recovery_stage == "R4" or (recovery_stage == "R5" or (recovery_stage == "R6" or recovery_stage == "R7")) then
            load_member("status_provider_app", function() require "status_provider_app" end)
            load_member("wifi_app_real", function() require "wifi_app_real" end)
            load_member("ntp_app", function() require "ntp_app" end)
        end
        if recovery_stage == "R2" or recovery_stage == "R3" or recovery_stage == "R4" or (recovery_stage == "R5" or (recovery_stage == "R6" or recovery_stage == "R7")) then
            -- exapp 必须先成功，设置存储初始化依赖其 init 接口。
            if load_member("recovery_exapp", function() exapp = require "recovery_exapp" end) then
                if recovery_stage == "R4" or (recovery_stage == "R5" or (recovery_stage == "R6" or recovery_stage == "R7")) then
                    load_member("settings_iot_app", function() require "settings_iot_app" end)
                    load_member("iot_auto_login", function()
                        assert(type(exapp.iot_auto_login) == "function", "missing IoT login API")
                        sys.taskInit(function()
                            local ok, err = pcall(exapp.iot_auto_login)
                            if not ok then log.error("sip_isolation", recovery_stage, "INVALID_TEST", "iot_auto_login", err) end
                        end)
                    end)
                end
                load_member("settings_app", function() require "settings_app" end)
                load_member("file_manager_app", function() require "file_manager_app" end)
                load_member("settings_win", function() require "settings_win" end)
                load_member("app_store_win", function() require "app_store_win" end)
                load_member("file_manager_win", function() require "file_manager_win" end)
            else
                group_ok = false
                log.error("sip_isolation", recovery_stage, "DEPENDENCY_FAILED", "exapp; settings/files skipped")
            end
        end
        if recovery_stage == "R3" or recovery_stage == "R4" or (recovery_stage == "R5" or (recovery_stage == "R6" or recovery_stage == "R7")) then
            load_member("video_win", function() require "video_win" end)
            load_member("idle_win", function() require "idle_win" end)
        end
        if recovery_stage == "R4" or (recovery_stage == "R5" or (recovery_stage == "R6" or recovery_stage == "R7")) then
            local fe = cfg.features or {}
            if (type(cfg.network) == "table" and #cfg.network > 0) or fe.wifi or fe.net_4g or fe.ethernet then
                load_member("weather_app", function() require "weather_app" end)
            else
                log.info("sip_isolation", recovery_stage, "SKIPPED", "weather_app", "network disabled in config")
            end
            load_member("fota_app", function() require "fota_app" end)
        end
        if (recovery_stage == "R5" or (recovery_stage == "R6" or recovery_stage == "R7")) then
            local fe = cfg.features or {}
            if fe.aircloud then
                load_member("aircloud_app", function() require "aircloud_app" end)
                load_member("settings_report_win", function() require "settings_report_win" end)
            else
                log.info("sip_isolation", recovery_stage, "SKIPPED", "aircloud_app/settings_report_win", "feature disabled")
            end
            if fe.cloud_disk then
                if load_member("cloud_disk_app", function() require "cloud_disk_app" end) then
                    load_member("cloud_disk_win", function() require "cloud_disk_win" end)
                end
            else
                log.info("sip_isolation", recovery_stage, "SKIPPED", "cloud_disk_app/cloud_disk_win", "feature disabled")
            end
        end
        if (recovery_stage == "R6" or recovery_stage == "R7") then
            if (cfg.features or {}).file_transfer then
                if load_member("file_transfer_app", function() require "file_transfer_app" end) then
                    load_member("file_transfer_win", function() require "file_transfer_win" end)
                end
                log.info("sip_isolation", recovery_stage, "WAIT_SERVICE", "hzadb SERVICE_READY required before call test")
            else
                log.info("sip_isolation", recovery_stage, "SKIPPED", "file_transfer_app/file_transfer_win", "feature disabled")
            end
        end
        if recovery_stage == "R7" then
            local fe = cfg.features or {}
            -- AI 语音输入也依赖 factory_rec；显式加载后由 require 缓存共享。
            local rec_ok = true
            if fe.app_factory or fe.ai_chat then
                rec_ok = load_member("factory_rec", function() require "factory_rec" end)
            end
            if fe.app_factory then
                if rec_ok and load_member("factory_app", function() require "factory_app" end) then
                    load_member("factory_win", function() require "factory_win" end)
                end
            else
                log.info("sip_isolation", recovery_stage, "SKIPPED", "factory_app/factory_win", "feature disabled")
            end
            if fe.ai_chat then
                if rec_ok and load_member("llm_chat", function() require "llm_chat" end) then
                    load_member("llm_chat_win", function() require "llm_chat_win" end)
                end
            else
                log.info("sip_isolation", recovery_stage, "SKIPPED", "llm_chat/llm_chat_win", "feature disabled")
            end
            if cfg.hw and cfg.hw.audio then
                load_member("tts_app", function() require "tts_app" end)
            else
                log.info("sip_isolation", recovery_stage, "SKIPPED", "tts_app", "audio not configured")
            end
        end
        -- Single-action recovery on the verified R7 baseline.
        if recovery_stage == "R7" and _G.SIP_RECOVERY_STEP == "R7-S8L-RS485-LAZY" then
            log.info("sip_mem_diag", "S5-HISTORY-FIX", "BASELINE", "R7-S8L-RS485-LAZY")
            log.info("sip_isolation", "R7-S8L-RS485-LAZY", "BASELINE", "R7-S4-AUDIO")
            local usb_ok = load_member("usb_mode", function()
                local usb_mode = require "usb_mode"
                usb_mode.apply_boot(cfg)
                log.info("sip_isolation", "R7-S8L-RS485-LAZY", "USB_MODE_APPLIED", usb_mode.mode())
            end)
            if usb_ok then
                load_member("periph_loader", function()
                    local usb_mode = require "usb_mode"
                    assert(usb_mode.mode() == "uvc", "R7-S8L-RS485-LAZY requires UVC mode; test invalid")
                    local selected = {}
                    for _, p in ipairs(usb_mode.filter(cfg.peripherals) or {}) do
                        if p.type == "uvc" then
                            assert(not p.handle, "UVC already registered before S2")
                            selected[#selected + 1] = p
                        end
                    end
                    assert(#selected == 1, "R7-S8L-RS485-LAZY requires exactly one UVC entry")
                    require("periph_loader").init_all(selected)
                    local p = selected[1]
                    assert(p.handle, "UVC registration failed: " .. tostring(p.id))
                    log.info("sip_isolation", "R7-S8L-RS485-LAZY", "PERIPHERAL_READY", p.type, p.id)
                end)
            end
            if usb_ok and group_ok then
                load_member("rs485_registration", function()
                    local selected = {}
                    for _, p in ipairs(cfg.peripherals or {}) do
                        if p.type == "rs485" then
                            assert(not p.handle, "RS485 already registered before S3")
                            selected[#selected + 1] = p
                        end
                    end
                    assert(#selected == 1, "R7-S8L-RS485-LAZY requires exactly one RS485 entry")
                    require("periph_loader").init_all(selected)
                    local p = selected[1]
                    assert(p.handle, "RS485 registration failed: " .. tostring(p.id))
                    log.info("sip_isolation", "R7-S8L-RS485-LAZY", "PERIPHERAL_READY", p.type, p.id)
                end)
            end
            if usb_ok and group_ok then
                load_member("audio_registration", function()
                    assert(cfg.hw and cfg.hw.audio, "R7-S8L-RS485-LAZY requires hw.audio")
                    local selected = {}
                    for _, p in ipairs(cfg.peripherals or {}) do
                        if p.type == "audio" then
                            assert(not p.handle, "audio already registered before S4")
                            selected[#selected + 1] = p
                        end
                    end
                    assert(#selected == 1, "R7-S8L-RS485-LAZY requires exactly one audio entry")
                    require("periph_loader").init_all(selected)
                    local p = selected[1]
                    assert(p.handle, "audio registration failed: " .. tostring(p.id))
                    assert(p.handle.inited == false and p.handle.state == "idle", "audio must remain idle and uninitialized")
                    log.info("sip_isolation", "R7-S8L-RS485-LAZY", "PERIPHERAL_READY", p.type, p.id)
                end)
            end
            if usb_ok and group_ok then
                load_member("other_func_app", function()
                    assert(cfg.features and cfg.features.other_func, "S5 requires other_func enabled")
                    local list = require("usb_mode").filter(cfg.peripherals) or {}
                    local count = 0
                    for _, p in ipairs(list) do
                        assert(p.type == "uvc" or p.type == "rs485" or p.type == "audio", "S5 unexpected peripheral type")
                        assert(type(p.handle) == "table" and type(p.handle.status) == "function", "S5 requires existing S4 handles")
                        count = count + 1
                    end
                    assert(count == 3, "S5 requires exactly three registered peripherals")
                    require "other_func_app"
                    log.info("sip_isolation", "R7-S8L-RS485-LAZY", "BUSINESS_READY", "other_func_app", "existing_handles", count)
                end)
            end
            if usb_ok and group_ok then
                load_member("other_func_win", function() require "other_func_win" end)
                log.info("sip_isolation", "S8L-RS485-LAZY", "RS485_PAGE_DEFERRED")
                log.info("sip_isolation", "CALL-LUA-QUIET1", "Lua call summaries deferred; native logs unchanged")
                log.info("sip_isolation", "CALL-WINDOW-DIAG1", "last 60 ten-second windows buffered; output after stop; query counters retained")
                log.info("sip_isolation", "SIP-STOP-RECONNECT-FIX1", "stop checked before reconnect and late socket events")
                log.info("sip_isolation", "AUDIO-EXIT-TRACE-DIAG1", "CONTROL", "RS485 manual TX retained; audio init and MIC warmup enabled; record/play/stop enabled; Back waits for cleanup; detached exit result retained; MIC probe reports UART bytes and parser ownership; recovery and scheduling diagnostics retained")
            end
            log.info("sip_isolation", "S8L-RS485-LAZY", "BASELINE", "S8-RS485-PAGE", "RS485 page deferred until first click; no UART open/send/DE operations")
            if _G.FACTORY_FULL_TEST then
                log.info("factory_handoff", "FULL_TEST_ON_DEMAND", "485/face/audio controls enabled; keep R7 startup services")
            else
                log.info("sip_isolation", "R7-S8L-RS485-LAZY", "EXCLUDED", "peripheral start/record/play, HID service, UVC/RS485/audio test subpages")
            end
            if usb_ok and group_ok then
                log.info("sip_isolation", "R7-S8L-RS485-LAZY", "LOAD_COMPLETE")
            else
                log.error("sip_isolation", "R7-S8L-RS485-LAZY", "INVALID_TEST")
            end
        end
        if group_ok then
            log.info("sip_isolation", recovery_stage, "LOAD_COMPLETE", "hardware call test pending")
        else
            log.error("sip_isolation", recovery_stage, "INVALID_TEST", "startup load failed")
        end
        require "sip_test_win"
        logo_hide()
        if recovery_stage == "R3" or recovery_stage == "R4" or (recovery_stage == "R5" or (recovery_stage == "R6" or recovery_stage == "R7")) then
            if group_ok then
                sys.publish("OPEN_IDLE_WIN")
                log.info("sip_isolation", recovery_stage, "DESKTOP_READY", "open SIP from desktop; check stage service readiness; test idle resident services first")
            end
        else
            sys.publish("OPEN_SIP_TEST_WIN")
            log.info("sip_isolation", recovery_stage, "SIP page opened; desktop/cloud/OTA/weather/AI/hzadb not started")
        end
        return
    end

    -- 11. 核心批：桌面 + 核心设置窗口（批间让出循环保证 logo 刷新不卡）
    ok, err = pcall(function() require("app_main").core() end)
    if not ok then
        log.error("boot_ui", "核心业务批加载失败", err)
    end
    sys.wait(0)
    ok, err = pcall(function() require("ui_main").core() end)
    if not ok then
        log.error("boot_ui", "核心窗口批加载失败", err)
    end

    -- 12. 主题恢复（核心批已跑完、无页面构建，直接改令牌即可）
    pcall(function() require("ui_theme").restore() end)

    -- 13. 核心批就绪，直接进桌面；销毁 logo 形状（FB 保留 logo 帧直到桌面首帧覆盖）
    sys.publish("OPEN_IDLE_WIN")
    logo_hide()
    log.info("boot_ui", "核心批就绪，进入桌面")
end

sys.taskInit(boot_task)
