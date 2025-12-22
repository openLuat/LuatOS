--[[
@module  ble_fota_main
@summary 蓝牙FOTA升级功能模块
@version 1.0
@date    2025.01.20
@author  孟伟
@usage
-- 蓝牙FOTA升级功能
-- 提供通过蓝牙低功耗(BLE)接收升级包数据进行固件升级的功能

用法:
1. 先把脚本和固件烧录到Air8000模块中，并确认设备正常启动
2. 模块启动后会自动开启BLE广播，广播名称为"Air8000_FOTA"
3. 在电脑端操作：运行ble_test.py脚本连接设备并发送升级固件
   注意：确保升级文件名为正确格式，并且与ble_test.py在同一目录下
4. 观察日志输出确认升级进度
5. 模块接收并验证固件成功后，会自动重启并应用新固件

BLE通讯过程说明
蓝牙FOTA升级通过BLE特征值进行命令控制和数据传输：
协议流程：
1. 上位机通过BLE扫描并连接名为"Air8000_FOTA"的设备
2. 上位机向命令特征值(F001)发送开始升级命令(0x01)和固件大小
3. 设备初始化FOTA功能并准备接收数据
4. 上位机向数据特征值(F002)分包发送固件数据
5. 设备接收并保存数据到临时文件
6. 上位机发送结束升级命令(0x02)
7. 设备验证固件完整性并执行FOTA升级流程
8. 升级成功后设备自动重启

注意:
- 本demo使用特定的服务UUID(F000)和特征值UUID(F001/F002)进行通信
- 升级过程中如果连接断开，设备会自动终止升级并清理临时文件
- 升级包大小不能超过设备的存储空间
- 本文件没有对外接口,直接在main.lua中require "ble_fota_main"就可以加载运行；
]]

-- 配置参数
local config = {
    device_name = "Air8000_FOTA", -- 设备广播名称
    service_uuid = "F000",        -- FOTA服务UUID（短格式）
    char_uuid_cmd = "F001",       -- 命令特征值UUID
    char_uuid_data = "F002",      -- 数据特征值UUID
    max_packet_size = 20          -- BLE数据包最大长度（字节）
}

-- 升级状态管理
local upgrade_state = {
    is_upgrading = false,          -- 是否正在升级
    ble_connected = false,         -- 是否已连接蓝牙设备
    total_size = 0,                -- 总文件大小（字节）
    received_size = 0,             -- 已接收大小（字节）
    upgrade_file = "/ble_fota.bin" -- 临时升级文件路径
}

-- GATT服务数据库定义
-- 这里定义了BLE设备提供的服务和特征值
-- GATT数据库定义
local att_db = {
    string.fromHex(config.service_uuid), -- Service UUID
    {
        string.fromHex(config.char_uuid_cmd),
        ble.WRITE | ble.WRITE_CMD
    },
    {
        string.fromHex(config.char_uuid_data),
        ble.WRITE | ble.WRITE_CMD
    },
    -- Characteristic 3: Status (Notify + Read)
    -- {
    --     string.fromHex(config.char_uuid_status),
    --     ble.NOTIFY | ble.READ
    -- }
}

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
                if fota.wait() then
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
                    log.error("FOTA_CMD", "FOTA底层准备失败")
                    fota.finish(false)
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
                log.info("FOTA_CMD", "2秒后设备将自动重启...")

                -- 延迟2秒后重启设备
                sys.timerStart(function()
                    -- 完成FOTA流程并重启
                    fota.finish(true)
                    log.info("FOTA_CMD", "正在重启设备...")
                    rtos.reboot()
                end, 2000)
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

-- BLE事件回调函数
-- @param ble_dev BLE设备对象
-- @param event 事件类型
-- @param param 事件参数
local function ble_event_cb(ble_dev, event, param)
    log.info("BLE_EVENT", "收到BLE事件:", event)

    -- 根据LuatOS BLE事件枚举处理不同事件
    if event == ble.EVENT_CONN then
        -- 连接成功事件
        log.info("BLE_EVENT", "设备已连接", "地址:", param.addr and param.addr:toHex() or "未知")
        upgrade_state.ble_connected = true
    elseif event == ble.EVENT_DISCONN then
        -- 连接断开事件
        log.info("BLE_EVENT", "设备已断开连接", "原因:", param.reason or "未知")
        upgrade_state.ble_connected = false

        -- 如果正在升级，连接断开则终止升级
        if upgrade_state.is_upgrading then
            log.error("BLE_EVENT", "升级过程中连接断开，终止升级")
            upgrade_state.is_upgrading = false

            -- 删除临时文件
            if upgrade_state.upgrade_file then
                os.remove(upgrade_state.upgrade_file)
            end

            -- 结束FOTA流程
            fota.finish(false)
        end
    elseif event == ble.EVENT_WRITE then
        -- 写入事件 - 这是关键事件！
        log.info("BLE_EVENT", "处理写入事件")

        -- 检查参数是否完整
        if not param or not param.uuid_service or not param.uuid_characteristic or not param.data then
            log.error("BLE_EVENT", "写入事件参数不完整")
            return
        end

        -- 获取服务UUID和特征值UUID
        local service_uuid = param.uuid_service:toHex()
        local char_uuid = param.uuid_characteristic:toHex()
        local data = param.data

        log.info("BLE_EVENT", "服务UUID:", service_uuid)
        log.info("BLE_EVENT", "特征值UUID:", char_uuid)
        log.info("BLE_EVENT", "数据长度:", #data, "字节")

        -- 简化的UUID匹配逻辑：检查UUID是否包含我们的短UUID
        local is_service_match = string.find(service_uuid:lower(), "f000")
        local is_cmd_match = string.find(char_uuid:lower(), "f001")
        local is_data_match = string.find(char_uuid:lower(), "f002")

        log.info("BLE_EVENT", "UUID匹配结果:",
            "服务匹配:", is_service_match,
            "命令匹配:", is_cmd_match,
            "数据匹配:", is_data_match)

        if is_service_match then
            if is_cmd_match then
                -- 命令特征值：处理FOTA命令
                log.info("BLE_EVENT", "命令特征值匹配，处理命令")
                handle_command(data)
            elseif is_data_match then
                -- 数据特征值：处理FOTA数据
                log.info("BLE_EVENT", "数据特征值匹配，处理数据")
                handle_data(data)
            else
                log.warn("BLE_EVENT", "未知的特征值UUID:", char_uuid)
            end
        else
            log.warn("BLE_EVENT", "未知的服务UUID:", service_uuid)
        end
    elseif event == ble.EVENT_READ then
        -- 读取事件 - 外围设备收到主设备读请求
        log.info("BLE_EVENT", "处理读取事件")
    elseif event == ble.EVENT_READ_VALUE then
        -- 读取操作完成事件 - 中心设备读取特征值完成
        log.info("BLE_EVENT", "读取操作完成", "数据:", param.data and param.data:toHex() or "无数据")
    elseif event == ble.EVENT_SCAN_REPORT then
        -- 扫描报告事件 - 中心设备扫描到其他BLE设备
        log.info("BLE_EVENT", "扫描报告", "RSSI:", param.rssi, "地址:", param.adv_addr and param.adv_addr:toHex() or "未知")
    elseif event == ble.EVENT_SCAN_STOP then
        -- 扫描停止事件
        log.info("BLE_EVENT", "扫描停止")
    else
        -- 其他事件
        log.info("BLE_EVENT", "其他事件类型:", event)
        if param then
            -- 尝试打印参数的基本信息，避免直接打印table导致错误
            if type(param) == "table" then
                log.info("BLE_EVENT", "事件参数为table，包含字段:", #param)
                for k, v in pairs(param) do
                    if type(v) == "string" then
                        log.info("BLE_EVENT", "参数字段:", k, "值:", v:toHex())
                    else
                        log.info("BLE_EVENT", "参数字段:", k, "类型:", type(v))
                    end
                end
            else
                log.info("BLE_EVENT", "事件参数类型:", type(param))
            end
        end
    end
end

-- 初始化BLE功能
-- @return boolean 初始化是否成功
local function init_ble()
    log.info("BLE_INIT", "开始初始化BLE...")


    -- 初始化蓝牙核心
    local bt_dev = bluetooth.init()
    if not bt_dev then
        log.error("BLE_INIT", "蓝牙核心初始化失败")
        return false
    end
    log.info("BLE_INIT", "蓝牙核心初始化成功")

    -- 初始化BLE功能
    local ble_dev = bt_dev:ble(ble_event_cb)
    if not ble_dev then
        log.error("BLE_INIT", "BLE功能初始化失败")
        return false
    end
    log.info("BLE_INIT", "BLE功能初始化成功")

    -- 创建GATT服务
    local gatt_result = ble_dev:gatt_create(att_db)
    if not gatt_result then
        log.error("BLE_INIT", "GATT服务创建失败")
        return false
    end
    log.info("BLE_INIT", "GATT服务创建成功")

    -- 配置广播数据
    log.info("BLE_INIT", "配置广播数据...")
    local adv_result = ble_dev:adv_create({
        addr_mode = ble.PUBLIC,
        channel_map = ble.CHNLS_ALL,
        intv_min = 120,
        intv_max = 120,
        adv_data = {
            { ble.FLAGS,               string.char(0x06) },  -- BLE标志
            { ble.COMPLETE_LOCAL_NAME, config.device_name }, -- 设备名称
        }
    })

    if not adv_result then
        log.error("BLE_INIT", "广播配置失败")
        return false
    end
    log.info("BLE_INIT", "广播配置成功")

    -- 开始广播
    ble_dev:adv_start()
    log.info("BLE_INIT", " BLE广播已启动，设备名称:", config.device_name)

    return true
end

-- 主任务函数
sys.taskInit(function()

    -- 主循环
    while true do
        log.info("MAIN", "尝试初始化BLE...")
        -- 重置连接状态
        upgrade_state.ble_connected = false
        -- 初始化BLE
        if init_ble() then
            log.info("MAIN", "BLE初始化成功，进入主循环")

            -- BLE运行状态维护循环
            while true do
                -- 等待5秒
                sys.wait(5000)

                if upgrade_state.is_upgrading then
                    local progress = math.floor((upgrade_state.received_size / upgrade_state.total_size) * 100)
                    log.info("MAIN", "升级状态: 进行中",
                        progress, "%",
                        "(", upgrade_state.received_size, "/", upgrade_state.total_size, ")")
                end
            end
        else
            log.error("MAIN", "BLE初始化失败，5秒后重试...")
            sys.wait(5000) -- 等待5秒后重试
        end
    end
end)
