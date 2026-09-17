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

    -- 充电电流档位白名单（键值一律取自扩展库常量，不写死字符串）
    --   扩展库 v1.4 起有效档位为 CCMIN/CCMID/CCMAX，v1.3 的旧档位名 "DEFAULT" 已失效；
    --   服务端下发合法档位则按档位生效，其余（未下发/旧值/任意非法字符串）一律回退 CCMIN。
    local i_charge_map = {
        [exs_yhm2712a.CCMIN] = exs_yhm2712a.CCMIN,  -- "MIN"  最小电流
        [exs_yhm2712a.CCMID] = exs_yhm2712a.CCMID,  -- "MID"  中等电流
        [exs_yhm2712a.CCMAX] = exs_yhm2712a.CCMAX,  -- "MAX"  最大电流
    }

    sys.taskInit(function()
        -- 默认最小电流(CCMIN)；服务端可通过 charge.i_charge 下发 MIN/MID/MAX 覆盖
        local i_charge = i_charge_map[cfg.I_CHARGE]
        if not i_charge then
            if cfg.I_CHARGE then
                log.warn("charge", "无效的充电电流档位:", tostring(cfg.I_CHARGE), "，已按最小电流处理")
            end
            i_charge = exs_yhm2712a.CCMIN
        end

        local setup_ok = exs_yhm2712a.setup({
            pin = cfg.CMD_PIN,
            v_battery = cfg.FLOAT_VOLTAGE_MV or 4200,
            cap_battery = cfg.CAP_BATTERY_MAH or 2000,
            i_charge = i_charge,
        })
        if setup_ok then
            log.info("charge", "YHM2712A 充电初始化成功，pin=", cfg.CMD_PIN,
                " v_battery=", cfg.FLOAT_VOLTAGE_MV, " cap_battery=", cfg.CAP_BATTERY_MAH, " i_charge=", i_charge)
            exs_yhm2712a.start()
        else
            log.error("charge", "YHM2712A 充电初始化失败")
        end
    end)
end

return charge
