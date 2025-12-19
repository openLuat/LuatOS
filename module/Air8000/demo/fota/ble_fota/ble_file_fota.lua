--[[
@module  ble_file_fota
@summary 蓝牙FOTA升级功能模块（文件写入方式）
@version 1.0
@date    2025.12.08
@author  孟伟
@usage
-- 蓝牙FOTA升级功能（文件写入方式）
-- 提供通过蓝牙低功耗(BLE)接收升级包数据进行固件升级的功能

本文件为FOTA业务逻辑处理模块，核心业务逻辑为：
1. 处理接收到的BLE写入请求数据
2. 实现FOTA升级流程的控制
3. 管理升级状态和文件操作

本文件的对外接口有1个：
1. ble_file_fota.proc(service_uuid, char_uuid, data): 处理接收到的BLE写入请求数据

依赖模块:
- ble_main: 用于提供BLE服务和事件处理
]]

local ble_file_fota = {}

-- 升级状态管理
local upgrade_state = {
    is_upgrading = false,          -- 是否正在升级
    total_size = 0,                -- 总文件大小（字节）
    received_size = 0,             -- 已接收大小（字节）
    upgrade_file = "/ble_fota.bin" -- 临时升级文件路径
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

                -- 等待FOTA底层准备就绪
                log.info("FOTA_CMD", "等待FOTA底层准备...")
                -- 等待FOTA底层准备就绪，最多等待10秒
                local wait_count = 0
                local wait_ok = false
                while wait_count < 100 do -- 最多轮询100次，每次100ms，共10秒
                    if fota.wait() then
                        wait_ok = true
                        break
                    end
                    sys.wait(100)
                    wait_count = wait_count + 1
                end

                if wait_ok then
                    log.info("FOTA_CMD", "FOTA底层准备就绪")

                    -- 删除旧的临时文件（如果存在）
                    if os.remove(upgrade_state.upgrade_file) then
                        log.info("FOTA_CMD", "已清理旧临时文件")
                    end

                    -- 更新升级状态
                    upgrade_state.is_upgrading = true
                    upgrade_state.total_size = total_size
                    upgrade_state.received_size = 0

                    log.info("FOTA_CMD", "升级状态已设置",
                        "总大小:", upgrade_state.total_size,
                        "临时文件:", upgrade_state.upgrade_file)
                    log.info("FOTA_CMD", "准备接收固件数据...")
                else
                    log.error("FOTA_CMD", "FOTA底层准备超时")
                    fota.finish(false)
                    upgrade_state.is_upgrading = false
                end
            else
                log.error("FOTA_CMD", "FOTA初始化失败")
            end
        else
            log.error("FOTA_CMD", "开始命令格式错误，长度不足")
        end

        -- 命令0x02：结束升级
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

            -- 执行FOTA升级
            log.info("FOTA_CMD", "开始执行FOTA升级...")
            local result, isDone = fota.file(upgrade_state.upgrade_file)
            log.info("FOTA_CMD", "FOTA升级结果:", "result:", result, "isDone:", isDone)

            if result and isDone then
                log.info("FOTA_CMD", " FOTA升级成功！")

                -- 延迟重启，给用户一些反应时间
                log.info("FOTA_CMD", "2秒后设备将自动重启...，重启后通过日志判断最终是否升级成功")

                -- 延迟2秒后重启设备
                sys.timerStart(ble_reboot, 2000)
            else
                log.error("FOTA_CMD", "FOTA升级失败")
            end
        else
            log.error("FOTA_CMD", "文件不完整，升级失败")
        end

        -- 清理升级状态（无论成功还是失败）
        log.info("FOTA_CMD", "清理升级状态...")
        upgrade_state.is_upgrading = false

        -- 删除临时文件
        if upgrade_state.upgrade_file then
            if os.remove(upgrade_state.upgrade_file) then
                log.info("FOTA_CMD", "已删除临时文件")
            else
                log.warn("FOTA_CMD", "删除临时文件失败")
            end
        end

        -- 结束FOTA流程
        fota.finish(false)
        log.info("FOTA_CMD", "升级流程结束")
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

    -- 保存数据到临时文件
    log.info("FOTA_DATA", "写入文件:", upgrade_state.upgrade_file)
    local file = io.open(upgrade_state.upgrade_file, "ab")
    if file then
        -- 写入数据
        file:write(data)
        file:close()

        -- 更新接收状态
        upgrade_state.received_size = upgrade_state.received_size + #data

        -- 计算并显示进度
        local progress = math.floor((upgrade_state.received_size / upgrade_state.total_size) * 100)

        -- 每50个数据包或完成时打印进度
        if upgrade_state.received_size % (config.max_packet_size * 50) == 0 or
            upgrade_state.received_size >= upgrade_state.total_size then
            log.info("FOTA_DATA", "升级进度:", progress, "%",
                "(", upgrade_state.received_size, "/", upgrade_state.total_size, ")")
        end

        log.info("FOTA_DATA", "数据写入成功，当前总计:", upgrade_state.received_size, "字节")
    else
        log.error("FOTA_DATA", "打开文件失败:", upgrade_state.upgrade_file)

        -- 文件操作失败，终止升级
        upgrade_state.is_upgrading = false
        fota.finish(false)
    end
end

-- 处理接收到的BLE写入请求数据
-- @param service_uuid 服务UUID
-- @param char_uuid 特征值UUID
-- @param data 写入的数据
function ble_file_fota.proc(service_uuid, char_uuid, data)
    log.info("ble_file_fota", "处理写入数据", service_uuid, char_uuid, data:toHex())

    -- 简化的UUID匹配逻辑：检查UUID是否包含我们的短UUID
    local is_service_match = string.find(service_uuid:lower(), config.service_uuid:lower())
    local is_cmd_match = string.find(char_uuid:lower(), config.char_uuid_cmd:lower())
    local is_data_match = string.find(char_uuid:lower(), config.char_uuid_data:lower())

    log.info("ble_file_fota", "UUID匹配结果:",
        "服务匹配:", is_service_match,
        "命令匹配:", is_cmd_match,
        "数据匹配:", is_data_match)

    if is_service_match then
        if is_cmd_match then
            -- 命令特征值：处理FOTA命令
            log.info("ble_file_fota", "命令特征值匹配，处理命令")
            handle_command(data)
        elseif is_data_match then
            -- 数据特征值：处理FOTA数据
            log.info("ble_file_fota", "数据特征值匹配，处理数据")
            handle_data(data)
        else
            log.warn("ble_file_fota", "未知的特征值UUID:", char_uuid)
        end
    else
        log.warn("ble_file_fota", "未知的服务UUID:", service_uuid)
    end
end


function ble_file_fota.proc_disconnect()
    log.info("ble_file_fota", "处理连接断开事件")

    -- 如果正在升级，连接断开则终止升级
    if upgrade_state.is_upgrading then
        log.error("ble_file_fota", "升级过程中连接断开，终止升级")
        upgrade_state.is_upgrading = false

        -- 删除临时文件
        if upgrade_state.upgrade_file then
            os.remove(upgrade_state.upgrade_file)
        end

        -- 结束FOTA流程
        fota.finish(false)
    end
end



return ble_file_fota
