--[[
@module  excloud_cmd
@summary 服务器控制命令解析与执行（按字段消息tag路由）
@version 2.0.0
@date    2026.08.30
@author  LuatOS 嵌入式软件设计开发
@usage
本模块实现“云平台服务器下发控制命令 → 模组解析 → 按字段消息tag路由 → 执行 → 回传结果”的完整链路。

【命令协议约定】
服务器通过 CONTROL_COMMAND 字段（FIELD_MEANINGS.CONTROL_COMMAND = 19）下发控制命令，
其 value 采用 JSON 字符串承载，顶层为【裸数组】（无 fields 外壳），格式如下：
    [{"field_meaning":775,"data_type":0,"value":1}, ...]
其中：
    field_meaning —— 消息tag（字段含义编号，取值来自 excloud.FIELD_MEANINGS）
    data_type     —— 数据类型（excloud.DATA_TYPES.* 中的取值）
    value         —— 该字段要设置的数值（类型由 data_type 决定）
示例：
    [{"field_meaning":775,"data_type":0,"value":1}]         -- 控制 GPIO 电平
    [{"field_meaning":800,"data_type":0,"value":12}]        -- 设置电压
    [{"field_meaning":775,"data_type":0,"value":1},
     {"field_meaning":800,"data_type":0,"value":12}]        -- 一次下发多条控制

【执行结果回传】
命令执行完毕后，通过 CONTROL_RESPONSE 字段（FIELD_MEANINGS.CONTROL_RESPONSE = 20）上行回传结果，
value 采用 JSON 字符串（顶层为裸数组），逐条对应下发的字段：
    [{"field_meaning":775,"result":0,"value":1,"msg":"成功"}, ...]
其中：
    field_meaning —— 本条结果对应下发的消息tag
    result        —— 0 表示成功，非 0 表示失败（错误码，见 CMD_CODE）
    value         —— 执行后回读/回显的数值
    msg           —— 描述性信息

【设计要点】
1. 字段路由表：一个“field_meaning 消息tag → 处理函数”的映射表，新增字段控制只需注册一个处理器。
2. 防呆处理：进入执行链路的字段若消息tag未知 / 未注册处理器 / 参数错误 / 执行异常，都会回传对应错误码，避免云端一直等待；
   整个 value 非合法 JSON 数组（如仅下发单字符 "1"）时视为误下发，仅记录日志、不执行、不回传。
3. 设备端不校验字段上下行属性，上下行识别与过滤由平台端在下发前完成。
   本模块只校验 field_meaning 是否存在于 FIELD_MEANINGS 中，再交由已注册的处理器执行。
4. 本示例中的执行动作为模拟动作，不操作真实外设，仅用于演示路由与回传链路。
]]

-- 依赖库
local excloud = require("excloud")

-- 业务配置
local config = require("config")

-- 本模块对外导出的表
local M = {}

-- 日志辅助
local log_tag = config.log_tag
local function log_info(...) log.info(log_tag, ...) end
local function log_warn(...) log.warn(log_tag, ...) end
local function log_error(...) log.error(log_tag, ...) end

-- =========================================================================
-- 统一错误码定义（用于回传 result 字段）
-- =========================================================================
local CMD_CODE = {
    OK = 0,              -- 成功
    PARAM_ERROR = 1,     -- 参数错误（字段缺键/数据类型不符）
    UNKNOWN_FIELD = 2,   -- 未知消息tag（不在 FIELD_MEANINGS 中）
    UNREGISTERED = 3,    -- 该字段存在但未注册处理器
    EXEC_ERROR = 4,      -- 执行过程出错
}

-- =========================================================================
-- 字段路由表：field_meaning 消息tag(数字) → 处理函数
-- 处理函数签名：function(value, data_type) -> code, msg, data
--   value     —— 该字段要设置的数值
--   data_type —— 数据类型（excloud.DATA_TYPES.*）
--   code      —— 错误码（0=成功）
--   msg       —— 描述信息
--   data      —— 可选，回传给云端的结果数据（table）
-- 新增字段控制：向 field_handlers 注册一个处理函数即可。
-- =========================================================================
local field_handlers = {}

-- =========================================================================
-- 工具函数：由字段数字反查常量名（便于日志观察）
-- =========================================================================
local function field_name_of(field)
    for k, v in pairs(config.FIELD_MEANINGS) do
        if v == field then
            return k
        end
    end
    return tostring(field)
end

-- =========================================================================
-- 回传控制响应：把逐条执行结果上行发送给云平台
-- @param results  数组，每项：{ field_meaning, result, value, msg }
-- =========================================================================
local function send_command_response(results)
    -- 若未产生任何结果（理论上不会发生），则给出一个占位项
    if type(results) ~= "table" or #results == 0 then
        results = { { field_meaning = 0, result = CMD_CODE.PARAM_ERROR, value = nil, msg = "无执行结果" } }
    end

    local value = json.encode(results)
    log_info("回传控制响应", value)

    -- 通过 CONTROL_RESPONSE 字段上行回传（need_reply=false，不需要云端再次回复）
    local ok, err = excloud.send({
        {
            field_meaning = config.FIELD_MEANINGS.CONTROL_RESPONSE,
            data_type = config.DATA_TYPES.UNICODE,
            value = value,
        }
    }, false)

    if not ok then
        log_warn("回传控制响应失败:", err)
    end
end

-- =========================================================================
-- 执行单个字段控制动作（core）
-- @param one     { field_meaning=, data_type=, value= }
-- @return result 单条结果 { field_meaning, result, value, msg }
-- =========================================================================
local function exec_one_field(one)
    -- 1. 基本结构与数据类型校验
    local fm = one.field_meaning
    local dt = one.data_type
    local val = one.value
    if type(fm) ~= "number" then
        return { field_meaning = 0, result = CMD_CODE.PARAM_ERROR, value = val, msg = "字段缺少合法field_meaning" }
    end
    if type(dt) ~= "number" then
        return { field_meaning = fm, result = CMD_CODE.PARAM_ERROR, value = val, msg = "字段缺少合法data_type" }
    end

    -- 2. 消息tag必须存在于 FIELD_MEANINGS 中（代码里有多少就是多少，不支持自定义）
    if field_name_of(fm) == tostring(fm) then
        log_warn("未知消息tag:", fm)
        return { field_meaning = fm, result = CMD_CODE.UNKNOWN_FIELD, value = val, msg = "未知消息tag" }
    end

    -- 3. 查找处理器（设备端不做上下行校验，平台端已在下发前识别）
    local handler = field_handlers[fm]
    if not handler then
        log_warn("字段未注册处理器:", fm, field_name_of(fm))
        return { field_meaning = fm, result = CMD_CODE.UNREGISTERED, value = val, msg = "该字段未注册处理器" }
    end

    -- 4. 调用处理器，捕获异常以保证必回传
    local ok_call, code, msg, data = pcall(handler, val, dt)
    if not ok_call then
        log_error("字段执行异常:", fm, field_name_of(fm), code)
        return { field_meaning = fm, result = CMD_CODE.EXEC_ERROR, value = val, msg = "执行异常: " .. tostring(code) }
    end

    -- 回读值：默认取原值，若处理器返回 data（table）则尝试从中取回读值
    local back_val = val
    if type(data) == "table" and data.value ~= nil then
        back_val = data.value
    end

    return { field_meaning = fm, result = code, value = back_val, msg = msg }
end

-- =========================================================================
-- 控制命令统一入口
-- @param cmd_value CONTROL_COMMAND 字段的 value（应为 JSON 字符串，顶层裸数组）
-- 协议：[{"field_meaning":..,"data_type":..,"value":..}, ...]
-- 防呆：value 非合法 JSON 数组（如仅下发单字符 "1"）时视为误下发，仅记录日志、不执行、不回传
-- =========================================================================
function M.handle_command(cmd_value)
    log_info("收到服务器控制命令，原始值:", cmd_value)

    -- 1. JSON 解析命令内容（期望顶层为裸数组）
    local ok, cmd_obj = pcall(json.decode, cmd_value)
    if not ok or type(cmd_obj) ~= "table" or #cmd_obj == 0 then
        -- 2. 防呆：单字符（如 "1"）、纯文本、空数组等非合法 JSON 数组，视为误下发，
        --    仅记录日志提示，不执行任何字段动作、不回传结果，避免误动作。
        log_warn("控制命令非合法JSON数组，视为误下发，忽略不执行:", cmd_value)
        return
    end

    log_info("控制命令字段数:", #cmd_obj)

    -- 3. 逐条按 field_meaning 路由执行，并收集结果
    local results = {}
    for _, one in ipairs(cmd_obj) do
        local result = exec_one_field(one)
        table.insert(results, result)
        if result.result == CMD_CODE.OK then
            log_info("字段执行成功:", result.field_meaning, result.msg, "值:", result.value)
        else
            log_warn("字段执行失败:", result.field_meaning, "错误码:", result.result, result.msg)
        end
    end

    -- 4. 回传结果（逐条回带 field_meaning）
    send_command_response(results)
end

-- =========================================================================
-- 下面对常用可控制字段进行注册。
-- 本示例中的执行动作为模拟动作，不操作真实外设，仅在日志中打印效果，便于演示路由与回传链路。
-- =========================================================================

-- =====================================================================
-- 字段控制 1：GPIO_LEVEL(775) —— 控制 GPIO 高低电平
-- 要求 data_type 建议为 INTEGER，value 为 0 或 1
-- =====================================================================
field_handlers[config.FIELD_MEANINGS.GPIO_LEVEL] = function(value, data_type)
    if data_type ~= config.DATA_TYPES.INTEGER then
        return CMD_CODE.PARAM_ERROR, "GPIO_LEVEL 建议使用 INTEGER 类型", nil
    end
    if value ~= 0 and value ~= 1 then
        return CMD_CODE.PARAM_ERROR, "GPIO_LEVEL 的 value 只能为 0 或 1", nil
    end

    log_info("[模拟] 控制 GPIO 电平", "电平:", value)
    return CMD_CODE.OK, "GPIO电平控制成功", { value = value }
end

-- =====================================================================
-- 字段控制 2：SET_VOLTAGE(800) —— 设置电压
-- 要求 data_type 建议为 INTEGER
-- =====================================================================
field_handlers[config.FIELD_MEANINGS.SET_VOLTAGE] = function(value, data_type)
    if data_type ~= config.DATA_TYPES.INTEGER then
        return CMD_CODE.PARAM_ERROR, "SET_VOLTAGE 建议使用 INTEGER 类型", nil
    end
    if type(value) ~= "number" then
        return CMD_CODE.PARAM_ERROR, "SET_VOLTAGE 的 value 必须为数字", nil
    end

    log_info("[模拟] 设置电压", "电压:", value)
    return CMD_CODE.OK, "设置电压成功", { value = value }
end

-- =====================================================================
-- 字段控制 3：WORK_STATUS(265) —— 设置工作状态
-- 要求 data_type 建议为 INTEGER
-- =====================================================================
field_handlers[config.FIELD_MEANINGS.WORK_STATUS] = function(value, data_type)
    if data_type ~= config.DATA_TYPES.INTEGER then
        return CMD_CODE.PARAM_ERROR, "WORK_STATUS 建议使用 INTEGER 类型", nil
    end

    log_info("[模拟] 设置工作状态", "状态值:", value)
    return CMD_CODE.OK, "工作状态设置成功", { value = value }
end

-- =====================================================================
-- 字段控制 4：SLEEP_MODE(778) —— 设置休眠模式
-- 要求 data_type 建议为 INTEGER；取值范围：0(正常)/1(轻休眠)/3(psm+深度休眠)
-- =====================================================================
field_handlers[config.FIELD_MEANINGS.SLEEP_MODE] = function(value, data_type)
    if data_type ~= config.DATA_TYPES.INTEGER then
        return CMD_CODE.PARAM_ERROR, "SLEEP_MODE 建议使用 INTEGER 类型", nil
    end
    if value ~= 0 and value ~= 1 and value ~= 3 then
        return CMD_CODE.PARAM_ERROR, "SLEEP_MODE 只能为 0/1/3", nil
    end

    log_info("[模拟] 设置休眠模式", "模式:", value)
    return CMD_CODE.OK, "休眠模式设置成功", { value = value }
end

-- =====================================================================
-- 字段控制 5：WAKE_INTERVAL(779) —— 设置定时唤醒间隔
-- 要求 data_type 建议为 INTEGER
-- =====================================================================
field_handlers[config.FIELD_MEANINGS.WAKE_INTERVAL] = function(value, data_type)
    if data_type ~= config.DATA_TYPES.INTEGER then
        return CMD_CODE.PARAM_ERROR, "WAKE_INTERVAL 建议使用 INTEGER 类型", nil
    end
    if type(value) ~= "number" then
        return CMD_CODE.PARAM_ERROR, "WAKE_INTERVAL 的 value 必须为数字", nil
    end

    log_info("[模拟] 设置唤醒间隔", "间隔:", value)
    return CMD_CODE.OK, "唤醒间隔设置成功", { value = value }
end

-- =====================================================================
-- 字段控制 6：NETWORK_TYPE(781) —— 设置/回读联网方式
-- 要求 data_type 建议为 INTEGER
-- =====================================================================
field_handlers[config.FIELD_MEANINGS.NETWORK_TYPE] = function(value, data_type)
    if data_type ~= config.DATA_TYPES.INTEGER then
        return CMD_CODE.PARAM_ERROR, "NETWORK_TYPE 建议使用 INTEGER 类型", nil
    end

    log_info("[模拟] 设置网络类型", "类型:", value)
    return CMD_CODE.OK, "网络类型设置成功", { value = value }
end

-- =====================================================================
-- 字段控制 7：BATTERY_LEVEL(771) —— 设置/回读电池电压参数
-- 要求 data_type 建议为 INTEGER
-- =====================================================================
field_handlers[config.FIELD_MEANINGS.BATTERY_LEVEL] = function(value, data_type)
    if data_type ~= config.DATA_TYPES.INTEGER then
        return CMD_CODE.PARAM_ERROR, "BATTERY_LEVEL 建议使用 INTEGER 类型", nil
    end

    log_info("[模拟] 电池参数控制", "值:", value)
    return CMD_CODE.OK, "电池参数处理成功", { value = value }
end

-- 说明：以上为示例中实现的具体字段处理器；其余字段若未注册处理器，会返回 UNREGISTERED 错误码。

-- 导出本模块
return M
