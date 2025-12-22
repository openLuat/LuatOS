--[[
@module  ble_packet_fota
@summary 蓝牙FOTA升级功能模块（分段写入方式）
@version 1.0
@date    2025.12.08
@author  孟伟
@usage
-- 蓝牙FOTA升级功能（分段写入方式）
-- 提供通过蓝牙低功耗(BLE)接收升级包数据进行固件升级的功能

本文件为FOTA业务逻辑处理模块，核心业务逻辑为：
1. 处理接收到的BLE写入请求数据
2. 实现FOTA升级流程的控制（分段写入方式）
3. 管理升级状态和分段数据操作

本文件的对外接口有1个：
1. ble_packet_fota.proc(service_uuid, char_uuid, data): 处理接收到的BLE写入请求数据

依赖模块:
- ble_main: 用于提供BLE服务和事件处理
]]

local ble_packet_fota = {}

-- 升级状态管理
local upgrade_state = {
    is_upgrading = false, -- 是否正在升级
    total_size = 0,       -- 总文件大小（字节）
    received_size = 0,    -- 已接收大小（字节）
    upgrade_packet = 0    -- 升级包计数器
}

-- 配置参数
local config = {
    service_uuid = "F000",   -- FOTA服务UUID（短格式）
    char_uuid_cmd = "F001",  -- 命令特征值UUID
    char_uuid_data = "F002", -- 数据特征值UUID
    max_packet_size = 200    -- BLE数据包最大长度（字节）
}
local function ble_reboot()
    -- 完成FOTA流程并重启
    fota.finish(true)
    log.info("FOTA_CMD", "正在重启设备...")
    rtos.reboot()
end
-- 处理FOTA命令
-- @param cmd_data 命令数据，格式：[命令码(1字节)] 或 [命令码(1字节) + 文件大小(4字节)]
local function handle_command(cmd_data)
    log.info("FOTA_CMD", "收到命令数据:", cmd_data:toHex(), "长度:", #cmd_data)

    -- 检查命令数据是否有效
    if #cmd_data < 1 then
        log.error("FOTA_CMD", "命令数据为空")
        return
    end

    -- 解析命令码（第一个字节）
    local cmd = cmd_data:byte(1)
    log.info("FOTA_CMD", "解析命令码:", cmd, string.format("(0x%02X)", cmd))

    -- 命令0x01：开始升级
    if cmd == 0x01 then
        log.info("FOTA_CMD", "处理开始升级命令")

        -- 检查命令格式：需要至少5字节（1字节命令码 + 4字节文件大小）
        if #cmd_data >= 5 then
            -- 解析文件大小（小端序，从第2字节开始）
            local total_size = string.unpack("<I4", cmd_data, 2)
            log.info("FOTA_CMD", "文件总大小:", total_size, "字节")

            -- 初始化FOTA子系统
            log.info("FOTA_CMD", "初始化FOTA子系统...")
            if fota.init() then
                log.info("FOTA_CMD", "FOTA初始化成功")

                -- FOTA底层已准备就绪，无需等待
                log.info("FOTA_CMD", "FOTA底层准备就绪")

                -- 更新升级状态
                upgrade_state.is_upgrading = true
                upgrade_state.total_size = total_size
                upgrade_state.received_size = 0
                upgrade_state.upgrade_packet = 0

                log.info("FOTA_CMD", "升级状态已设置",
                    "总大小:", upgrade_state.total_size)
                log.info("FOTA_CMD", "准备接收固件数据...")
            else
                log.error("FOTA_CMD", "FOTA初始化失败")
            end
        else
            log.error("FOTA_CMD", "开始命令格式错误，长度不足")
        end

        -- 命令0x02：结束升级（通知升级包发完）
    elseif cmd == 0x02 then
        log.info("FOTA_CMD", "处理结束升级命令")

        -- 检查是否处于升级状态
        if not upgrade_state.is_upgrading then
            log.warn("FOTA_CMD", "未处于升级状态，忽略结束命令")
            return
        end

        -- 验证文件完整性
        log.info("FOTA_CMD", "验证文件完整性...")
        log.info("FOTA_CMD", "已接收:", upgrade_state.received_size, "字节")
        log.info("FOTA_CMD", "应接收:", upgrade_state.total_size, "字节")

        if upgrade_state.received_size == upgrade_state.total_size then
            log.info("FOTA_CMD", "文件完整性验证通过")
            log.info("FOTA_CMD", "升级数据已全部接收，等待升级完成...")

            -- 等待底层校验结束
            local success = false
            for i = 1, 30 do -- 最多等待3秒
                sys.wait(100)
                local succ, fotaDone = fota.isDone()
                if not succ then
                    log.error("FOTA_CMD", "校验过程出错")
                    fota.finish(false)
                    upgrade_state.is_upgrading = false
                    break
                end
                if fotaDone then
                    log.info("FOTA_CMD", "FOTA升级成功！")

                    -- 延迟重启，给用户一些反应时间
                    log.info("FOTA_CMD", "2秒后设备将自动重启...，重启后通过日志判断最终是否升级成功")

                    -- 延迟2秒后重启设备
                    sys.timerStart(ble_reboot, 2000)
                    success = true
                    break
                end
            end

            if not success then
                log.error("FOTA_CMD", "校验超时")
                fota.finish(false)
                upgrade_state.is_upgrading = false
            end
        else
            log.error("FOTA_CMD", "文件不完整，升级失败")
            -- 清理升级状态
            upgrade_state.is_upgrading = false
            fota.finish(false)
        end

        log.info("FOTA_CMD", "结束升级命令处理完成")
    else
        log.warn("FOTA_CMD", "未知命令码:", cmd, string.format("(0x%02X)", cmd))
    end
end

-- 处理FOTA数据
-- @param data 固件数据块
local function handle_data(data)
    log.info("FOTA_DATA", "收到数据包，长度:", #data, "字节")

    -- 检查是否处于升级状态
    if not upgrade_state.is_upgrading then
        log.warn("FOTA_DATA", "未处于升级状态，忽略数据")
        return
    end

    -- 直接使用fota.run()处理分段数据，不写入文件
    log.info("FOTA_DATA", "处理分段数据，包序号:", upgrade_state.upgrade_packet)
    local result, isDone = fota.run(data)
    log.info("FOTA_DATA", "分段写入结果:", "result:", result, "isDone:", isDone)

    if result then
        -- 更新接收状态
        upgrade_state.received_size = upgrade_state.received_size + #data
        upgrade_state.upgrade_packet = upgrade_state.upgrade_packet + 1

        -- 计算并显示进度
        local progress = math.floor((upgrade_state.received_size / upgrade_state.total_size) * 100)

        -- 每50个数据包或完成时打印进度
        if upgrade_state.received_size % (config.max_packet_size * 50) == 0 or
            upgrade_state.received_size >= upgrade_state.total_size then
            log.info("FOTA_DATA", "升级进度:", progress, "%",
                "(", upgrade_state.received_size, "/", upgrade_state.total_size, ")")
        end

        log.info("FOTA_DATA", "数据写入成功，当前总计:", upgrade_state.received_size, "字节")

        -- 如果所有数据都已接收，检查升级是否完成
        if upgrade_state.received_size >= upgrade_state.total_size then
            log.info("FOTA_DATA", "所有数据已接收，等待升级完成...")
        end
    else
        log.error("FOTA_DATA", "分段写入失败")

        -- 分段写入失败，终止升级
        upgrade_state.is_upgrading = false
        fota.finish(false)
    end
end

-- 处理接收到的BLE写入请求数据
-- @param service_uuid 服务UUID
-- @param char_uuid 特征值UUID
-- @param data 写入的数据
function ble_packet_fota.proc(service_uuid, char_uuid, data)
    log.info("ble_packet_fota", "处理写入数据", service_uuid, char_uuid, data:toHex())

    -- 简化的UUID匹配逻辑：检查UUID是否包含我们的短UUID
    local is_service_match = string.find(service_uuid:lower(), config.service_uuid:lower())
    local is_cmd_match = string.find(char_uuid:lower(), config.char_uuid_cmd:lower())
    local is_data_match = string.find(char_uuid:lower(), config.char_uuid_data:lower())

    log.info("ble_packet_fota", "UUID匹配结果:",
        "服务匹配:", is_service_match,
        "命令匹配:", is_cmd_match,
        "数据匹配:", is_data_match)

    if is_service_match then
        if is_cmd_match then
            -- 命令特征值：处理FOTA命令
            log.info("ble_packet_fota", "命令特征值匹配，处理命令")
            handle_command(data)
        elseif is_data_match then
            -- 数据特征值：处理FOTA数据
            log.info("ble_packet_fota", "数据特征值匹配，处理数据")
            handle_data(data)
        else
            log.warn("ble_packet_fota", "未知的特征值UUID:", char_uuid)
        end
    else
        log.warn("ble_packet_fota", "未知的服务UUID:", service_uuid)
    end
end

-- 处理BLE连接断开事件
-- @return nil
function ble_packet_fota.proc_disconnect()
    log.info("ble_packet_fota", "处理连接断开事件")

    -- 如果正在升级，连接断开则终止升级
    if upgrade_state.is_upgrading then
        log.error("ble_packet_fota", "升级过程中连接断开，终止升级")
        upgrade_state.is_upgrading = false

        -- 结束FOTA流程
        fota.finish(false)
    end
end

return ble_packet_fota
