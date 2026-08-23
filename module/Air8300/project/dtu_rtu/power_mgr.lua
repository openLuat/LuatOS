--[[
@module  power_mgr
@summary 功耗管理 v2（网口1不关，保证Web可用）
@version 2.0 / 2026.06.12
]]

local net_config = require("net_config")
local net_drv = require("net_drv")
local M = {}

-- 模块加载时立即确保网口1供电 + 清残留dtimer
gpio.setup(16, 1, gpio.PULLUP)
pm.dtimerStop(0)

local current_mode = "normal"
local lp_task_id = nil

local function peripherals_off()
    net_drv.wifi_off()
    net_drv.eth2_off()
    net_drv.rs485_off()
    log.info("power_mgr", "外设关（网口1保持）")
end
local function peripherals_on()
    net_drv.wifi_on()
    net_drv.eth2_on()
    net_drv.rs485_on()
    log.info("power_mgr", "外设开")
end

-- 常规模式（什么都不做，net_drv已管好）
local function enter_normal()
    current_mode = "normal"
    net_drv.rs485_on()
    net_drv.wifi_on()
    log.info("power_mgr", "常规模式")
end

-- 低功耗模式：全部外设周期开关（网口1保持）
local function enter_lowpower()
    current_mode = "lowpower"
    -- 初始关外设（不关网口2，CH390要求双网口同时供电）
    net_drv.wifi_off(); net_drv.rs485_off()
    log.info("power_mgr", "低功耗: WiFi关 RS485关 网口1/2保持")
    lp_task_id = sys.taskInit(function()
        local interval = (net_config.load().psm_interval or 300) * 1000
        if interval < 10000 then interval = 10000 end
        while current_mode == "lowpower" do
            -- 分段等待，每秒检查模式是否切换
            for _ = 1, interval / 1000 do
                if current_mode ~= "lowpower" then break end
                sys.wait(1000)
            end
            if current_mode ~= "lowpower" then break end
            -- 唤醒采集
            net_drv.rs485_on()
            log.info("power_mgr", ">>> 唤醒采集 <<<")
            sys.wait(6000)
            -- 休眠
            net_drv.rs485_off()
            log.info("power_mgr", "<<< 休眠省电 <<<")
        end
        log.info("power_mgr", "退出低功耗")
    end)
end

-- PSM+深度休眠（全关：网口+WiFi+4G+RS485）
local function enter_psm()
    current_mode = "psm"
    local cfg_iv = net_config.load().psm_interval or 300
    local interval = cfg_iv * 1000
    if interval < 20000 then interval = 20000 end
    log.info("power_mgr", "PSM+模式, 实:", interval / 1000, "秒")
    -- 先关所有外设（让后台任务自然阻塞）
    net_drv.wifi_off()
    net_drv.eth2_off()
    net_drv.rs485_off()
    gpio.setup(16, 0)
    sys.wait(2000)
    pm.power(pm.WIFI, 0)
    mobile.flymode(0, true)
    sys.wait(5000)
    -- 设置唤醒 + 进入深度休眠
    pm.dtimerStart(0, interval)
    sys.wait(5000)
    pm.power(pm.WORK_MODE, 3)
    sys.wait(20000)
    pm.dtimerStop(0)
    rtos.reboot()
end

-- 启动时检测唤醒原因
local reason, state = pm.lastReson()
log.info("power_mgr", "启动原因:", reason, state)
if reason == 1 and (state == 3 or state == 4) then
    -- dtimer 唤醒：正常启动，Web 可用，用户自行切回常规
    log.info("power_mgr", "PSM+ dtimer唤醒, 正常启动")
elseif reason == 1 then
    -- 非PSM+的dtimer唤醒，正常启动
    log.info("power_mgr", "dtimer唤醒, 正常启动")
else
    -- 上电/复位/其他：正常启动，不进 PSM+
    log.info("power_mgr", "上电启动, 常规模式")
end

function M.is_psm_skip() return false end
function M.get_mode() return current_mode end

function M.set_mode(mode)
    if mode == current_mode then return end
    current_mode = mode
    sys.taskInit(function()
        if mode == "normal" then enter_normal()
        elseif mode == "lowpower" then enter_lowpower()
        elseif mode == "psm" then enter_psm()
        end
    end)
    net_config.save({power_mode = mode})
end

-- 正常启动：不自动进入低功耗/PSM+，等待用户通过Web触发

sys.subscribe("NET_CONFIG_UPDATED", function(cfg)
    if cfg.power_mode and cfg.power_mode ~= current_mode then
        M.set_mode(cfg.power_mode)
    end
end)

return M
