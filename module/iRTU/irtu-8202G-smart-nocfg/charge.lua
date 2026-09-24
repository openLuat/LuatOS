local charge = {}

local config = require "config"

function charge.init()
    local cfg = config.CHARGE_CONFIG or {}
    if cfg.ENABLE ~= true then
        log.info("charge", "充电管理未开启，跳过初始化")
        return
    end
    if not cfg.CMD_PIN then
        log.warn("charge", "未配置 YHM2712A CMD 引脚，跳过充电初始化")
        return
    end

    local ok, exs_yhm2712a = pcall(require, "exs_yhm2712a")
    if not ok or not exs_yhm2712a then
        log.error("charge", "加载 exs_yhm2712a 库失败")
        return
    end

    sys.taskInit(function()
        local setup_ok = exs_yhm2712a.setup({
            pin = cfg.CMD_PIN,
            v_battery = cfg.FLOAT_VOLTAGE_MV or 4200,
            cap_battery = cfg.CAP_BATTERY_MAH or 2000,
            i_charge = cfg.I_CHARGE or exs_yhm2712a.CCDEFAULT,
        })
        if setup_ok then
            log.info("charge", "YHM2712A 充电初始化成功，pin=", cfg.CMD_PIN,
                " v_battery=", cfg.FLOAT_VOLTAGE_MV, " cap_battery=", cfg.CAP_BATTERY_MAH, " i_charge=", cfg.I_CHARGE)
            exs_yhm2712a.start()
        else
            log.error("charge", "YHM2712A 充电初始化失败")
        end
    end)
end

return charge
