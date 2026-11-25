--[[
@module  main
@summary 儿童房控制面板 · 启动编排（Air1603_A10 / Air8607 · 1024x600 / AirUI）
@version 2.0.1
@note 启动顺序固定：
        density_scale → wdt → 电源轨/GPIO 上电 → LCD(display) → airui.init → hzfont → 触摸
        → 挂 TF 卡（可选） → 建界面 → 首帧完成 → 点背光
      实际板型由 hardware 内的 rtos.bsp() 判断（Air1603_A10 与 Air8607 的电源轨/触摸复位脚不同）。
      必需步骤失败：log.error 出「阶段 + 原始错误」并终止（不点背光，屏幕保持可诊断的黑屏）；
      可选步骤失败：只记一次降级原因，界面继续（TF 卡、单张贴图、fskv 主题记忆、触摸）。
]]
PROJECT = "kid_room_panel"
VERSION = "2.0.1"

log.info("main", PROJECT, VERSION, "1024x600", (rtos and rtos.bsp and rtos.bsp()) or "unknown")

local hardware = require "hardware"

-- 界面模块加载前先确定密度缩放
hardware.init_density_scale()

if wdt then
    wdt.init(60000)
    sys.timerLoopStart(wdt.feed, 3000)
end

sys.taskInit(function()
    -- ① 必需：屏幕 + AirUI + 触摸
    local ok, err = pcall(hardware.init)
    if not (ok and err) then
        log.error("main", "硬件初始化失败（阶段=hardware.init）", tostring(err))
        return
    end
    hardware.init_density_scale()

    -- ② 可选：TF 卡（只影响贴图能否被用户替换，失败不阻断）
    if rtos and rtos.bsp and rtos.bsp() == "PC" then
        log.info("main", "PC 模拟器无 TF 卡，跳过挂载（贴图走内置 /luadb/）")
    else
        local sd_ok, sd_err = pcall(function()
            local sd = require "sd_card"
            return sd.mount()
        end)
        if not (sd_ok and sd_err) then
            log.warn("main", "TF 卡不可用，贴图走内置 /luadb/（降级）", tostring(sd_err))
        end
    end

    sys.wait(150)

    -- ③ 必需：首帧界面
    local cok, cerr = pcall(function()
        local shell = require "page_shell"
        shell.create()
        _G.__shell = shell
    end)
    if not cok then
        log.error("main", "界面创建失败（阶段=page_shell.create）", tostring(cerr))
        return
    end

    -- ④ 首帧已提交，点亮背光（避免上电花屏）
    pcall(hardware.backlight_on)
    log.info("main", "儿童房面板已启动", PROJECT, VERSION)

    -- ⑤ 值守循环：500ms 一跳，只改文字与颜色；单帧异常只记日志不退出
    while true do
        sys.wait(500)
        local tok, terr = pcall(_G.__shell.tick, 500)
        if not tok then
            log.error("main", "tick 异常", tostring(terr))
        end
    end
end)

sys.run()
