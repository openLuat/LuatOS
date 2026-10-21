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
  7. 等 POWER_ON_DONE → tp_drv.init()（失败 200ms 重试一次）→ guard_audio_init
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

7. 音频 I2C 守护必须挂在所有业务模块（含可选批）加载之前：exaudio.setup 会
   i2c.setup 重置触摸总线（丢轮询设置），guard 包住 setup/播录入口后触摸总线才安全

8. 启动顺序原则：点亮前的关键路径只保留「引脚 / 上电 / fskv / display+logo+背光」，
   其余一切（exwin/exapp、音频、网络、字体、各业务模块）全部在显示完成之后进行
]]

-- logo 尺寸（1:1 居中显示，不缩放）
local LOGO_SIZE = 128

-- logo 首帧上屏余量：airui 首帧刷新是异步的，RGB 帧缓冲跨热复位不清屏，
-- 背光早于首帧会把上一次会话的残留画面闪给用户（闪屏）。
-- 按屏幕尺寸取值：10寸 100ms、7寸 200ms；未列尺寸默认 100ms，真机闪屏时按表补
local BOOT_BACKLIGHT_DELAY_BY_SIZE = {
    [10] = 100,
    [7]  = 200,
}

local bg_shape
local logo_img

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
        exapp = require "exapp"
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

    -- 8. 触摸初始化：失败 200ms 后重试一次（GT911 电源刚稳仍可能需要余量）
    local ok2, r = pcall(tp_drv.init)
    if not (ok2 and r) then
        log.warn("boot_ui", "tp 初始化未成功，200ms 后重试", ok2 and r or r)
        sys.wait(200)
        pcall(tp_drv.init)
    end

    -- 9. 音频 I2C 守护：必须先于所有业务模块（含可选批）加载
    pcall(guard_audio_init)

    -- 10. 可选批独立协程并行加载（音量恢复/网络/音频/SD/NES/UVC/HID，不阻塞进桌面）
    sys.taskInit(optional_task)

    -- 11. 字体加载等核心初始化（读字库建 cache，初始化中最重的一步，与可选批并行消化）
    ok, err = pcall(lcd_drv.airui_core_init)
    if not ok then
        log.error("boot_ui", "airui_core_init 失败", err)
    end

    -- 12. 核心批：桌面 + 核心设置窗口（批间让出循环保证 logo 刷新不卡）
    ok, err = pcall(function() require("app_main").core() end)
    if not ok then
        log.error("boot_ui", "核心业务批加载失败", err)
    end
    sys.wait(0)
    ok, err = pcall(function() require("ui_main").core() end)
    if not ok then
        log.error("boot_ui", "核心窗口批加载失败", err)
    end

    -- 13. 主题恢复（核心批已跑完、无页面构建，直接改令牌即可）
    pcall(function() require("ui_theme").restore() end)

    -- 14. 核心批就绪，直接进桌面；销毁 logo 形状（FB 保留 logo 帧直到桌面首帧覆盖）
    sys.publish("OPEN_IDLE_WIN")
    logo_hide()
    log.info("boot_ui", "核心批就绪，进入桌面")
end

sys.taskInit(boot_task)
