--[[
@module  aircloud_ctrl
@summary 下行控制处理（AirCloud 控制命令 → Modbus 写寄存器）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
依据 network-communication-protocol.md 10.3 与 excloud demo 约定：
1. 订阅 AIRCLOUD_CMD（由 excloud_app 从 CONTROL_COMMAND(19) 解析得到）；
2. 命令 value 为 JSON 字符串（顶层裸数组）：
   [{"field_meaning":1550,"data_type":0,"value":1}]   -- 1=开机，0=关机
3. 执行：写变频器寄存器 0x2000 = 1(开机) / 6(关机)；
4. 逐条收集结果并发布 CTRL_RESULT，由 excloud_app 回复 CONTROL_RESPONSE(20)。
本模块无对外接口，直接 require "aircloud_ctrl" 即加载运行。
]]

local config_app    = require("config_app")
local msg_bus       = require("msg_bus")
local modbus_map    = require("modbus_map")
local modbus_master = require("modbus_master")
local oam_logger    = require("oam_logger")

-- 结果码（与 excloud demo 约定一致）
local CMD_OK        = 0 -- 成功
local CMD_UNKNOWN   = 3 -- 未知字段
local CMD_EXEC_ERR  = 4 -- 执行出错

-- 处理单条控制命令
local function exec_one(item)
    local fm  = item.field_meaning
    local val = item.value

    if fm == config_app.FIELD.ctrl_switch then
        -- 开关机：1=开机 → 写 1；其它(0)=关机 → 写 6
        local reg_val = (val == 1) and modbus_map.ctrl_on or modbus_map.ctrl_off
        local ok = modbus_master.write_reg(modbus_map.ctrl_reg, reg_val)
        oam_logger.log("ctrl", "switch", val, ok and "ok" or "fail")
        if ok then
            return { field_meaning = fm, result = CMD_OK, value = val, msg = "成功" }
        end
        return { field_meaning = fm, result = CMD_EXEC_ERR, value = val, msg = "写入变频器失败" }
    end

    return { field_meaning = fm, result = CMD_UNKNOWN, value = val, msg = "未知字段" }
end

-- 控制命令统一入口
local function handle_command(cmd_value)
    log.info("aircloud_ctrl", "收到控制命令", cmd_value)

    local ok, arr = pcall(json.decode, cmd_value)
    if not ok or type(arr) ~= "table" or #arr == 0 then
        log.warn("aircloud_ctrl", "控制命令非合法JSON数组，忽略", cmd_value)
        return
    end

    local results = {}
    for _, item in ipairs(arr) do
        results[#results + 1] = exec_one(item)
    end

    -- 发布执行结果，交由 excloud_app 回复控制回应
    sys.publish(msg_bus.CTRL_RESULT, { results = results })
end

-- 控制命令处理协程：在独立协程中执行（允许 sys.wait / sys.waitUntil 等挂起操作）
local function cmd_worker(cmd_value)
    handle_command(cmd_value)
end

-- 订阅下行命令
-- ⚠️ sys.subscribe 回调运行在消息分发现场（非协程），不能直接调用会挂起的接口
--    （如 modbus_master.write_reg 内部的 sys.wait），否则报错
--    "attempt to yield from outside a coroutine" 并触发系统重启。
--    因此此处只投递一个任务，由独立协程执行真正的处理逻辑。
local function on_cloud_cmd(payload)
    if payload and payload.data then
        sys.taskInit(cmd_worker, payload.data)
    end
end

sys.subscribe(msg_bus.AIRCLOUD_CMD, on_cloud_cmd)
