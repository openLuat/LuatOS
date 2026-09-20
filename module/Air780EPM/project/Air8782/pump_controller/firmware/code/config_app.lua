--[[
@module  config_app
@summary 全局业务配置（引脚 / 串口 / 采集上报周期 / 看门狗 / AirCloud 参数）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
本模块集中管理泵控制器工程的全局配置，其它模块通过 require("config_app") 读取，便于统一维护。
依据：
- requirement.md（5.2 采集、5.3 上报、5.5 云服务、5.6 OTA、5.7/5.8 看门狗、5.9 485）
- inter-device-communication-protocol.md（串口参数、从站地址）
- network-communication-protocol.md（AirCloud 参数、TLV 字段编号）
- 嵌入式软件总体设计.md（模块与参数）
本模块有对外接口，末尾 return M。
]]

-- excloud 扩展库：用于读取 DATA_TYPES / FIELD_MEANINGS 常量与运维日志写入方式常量
local excloud = require("excloud")

-- 对外导出的配置表
local M = {}

-- =========================================================================
-- 〇、运行环境判定（在 sim_identity 覆盖 rtos.bsp 之前捕获，供各模块统一使用）
--   注意：sim_identity 会覆盖全局 rtos.bsp（用于让 excloud 以 4G 真机身份接入），
--         因此其它模块判断“是否 PC 模拟器”请统一用本常量 M.is_pc，勿直接用 rtos.bsp()。
-- =========================================================================
M.is_pc = (rtos.bsp() == "PC")

-- =========================================================================
-- 一、硬件引脚（依据 Air8782P2 官方硬件：485=UART2，方向 GPIO31，供电使能 GPIO26）
-- =========================================================================
M.pin_485_pwr = 26   -- 485 收发器供电使能 LDO 控制脚（高电平使能，必须开机拉高）
M.pin_485_dir = 31   -- 485 半双工方向控制脚
M.pin_wdt     = 24   -- Air153C 硬件看门狗喂狗信号脚

-- =========================================================================
-- 二、串口 / Modbus（依据 inter-device-communication-protocol.md）
-- =========================================================================
M.uart_id       = 2       -- 485 使用 UART2
M.baud_rate     = 115200  -- 115200-8-N-1
M.data_bits     = 8
M.stop_bits     = 1
M.slave_id      = 1       -- 变频器从站地址 01
M.modbus_timeout = 1000   -- 单帧请求超时（ms）
M.modbus_retry   = 2      -- 单项读取失败重试次数
-- 485 方向脚"接收态"电平（0/1）。
-- 说明：现场真机 485"能发不能收"。实测改成 1 后连发送都失败 → 确认标准极性
--       （发送态=1 / 接收态=0），必须保持 0；问题在"发送后未切回接收态"（见 modbus_master）。
M.rs485_dir_rx_level = 0
-- 是否打印 Modbus 原始收发帧（modbus_master 内 TX/RX 日志）。默认关闭（调试期可临时开启）。
M.modbus_debug   = false
-- 485 方向控制方式：
--   "manual" = 由 modbus_master 手动控制 GPIO31（发送前拉高、发送完成回调立即拉低）；
--   "auto"   = 交由 uart.setup 的硬件自动换向（rs485_gpio / rs485_level）。
-- 现场结论：本模组（Air8782P2）auto（框架自动换向）工作正常，采用 auto。
M.rs485_dir_mode = "auto"

-- =========================================================================
-- 三、采集与上报（依据 requirement.md 5.2 / 5.3）
-- =========================================================================
M.collect_ms   = 600   -- 采集周期 600ms（一轮 15 项）
M.report_cycle = 10    -- 心跳上报周期 10s（无变化时周期上报）
M.log_tag      = "pump_ctrl"

-- 模拟采集数据：现仅用于 PC 模拟器（无 485/UART2 外设）调试。
-- 现场已外接真实变频器：真机不再降级模拟（sim_fake_on_device=false），坚持真实采集。
M.sim_fake_collect        = true  -- 总开关：是否允许模拟采集（真机已关闭降级，仅 PC 模拟器调试时生效）
M.sim_fake_on_device      = false -- 真机变频器离线时是否也降级为模拟采集（false=真机只走真实采集；现场已接真实变频器）
M.sim_fake_fail_threshold = 1     -- 真实采集连续全失败多少轮后判定“变频器离线”并切模拟（600ms/轮）
M.sim_fake_recover_probe  = 100   -- 模拟模式下每多少轮探测一次变频器是否恢复在线（100×600ms≈60s）
M.sim_fake_raw = {               -- 模拟的寄存器“原始值”（键与 modbus_map.fields 的 key 一致；换算由 state_norm 完成）
    outHz    = 5000,        -- 运行频率 5000×0.01 = 50.00 Hz
    setHz    = 5000,        -- 设定频率 5000×0.01 = 50.00 Hz
    muV      = 5300,        -- 母线电压 5300×0.1  = 530.0 V
    outV     = 380,         -- 输出电压 380 V
    outA     = 25,          -- 输出电流 25×0.1   = 2.5 A
    outkw    = 95,          -- 输出功率 95×0.1   = 9.5 kW
    nbTemp   = 42,          -- 散热器温度 42 ℃
    H        = 1234,        -- 累计运行时间 1234 h
    devstate = 1,           -- 运行状态：1=正转运行
    oneHz    = 0, oneA = 0,
    twoHz    = 0, twoA = 0,
    threeHz  = 0, threeA = 0,
}
-- 模拟数据“动态变化”（模拟数据生效时）
M.sim_fake_dynamic          = true  -- 数值随采集轮次波动（不触发即时上报，仅令心跳数据有变化）
M.sim_fake_wave_percent     = 5     -- 数值波动幅度（±百分比）
-- devstate 轮转（默认关闭：避免频繁触发“状态变化/故障”即时上报，保证以 60s 心跳为主）
M.sim_fake_devstate_change  = false                                  -- 是否让 devstate 变化（开启后会触发即时上报）
M.sim_fake_devstate_seq     = { 1, 1, 1, 2, 1, 1, 3, 1, 1, 1, 5, 1 }  -- devstate 轮转序列（1正转/2反转/3停止/4调谐/5故障）
M.sim_fake_devstate_hold    = 100                                    -- 每个 devstate 值保持的采集轮数（100×600ms≈60s）

-- =========================================================================
-- 四、网络业务看门狗（依据 requirement.md 5.7）
-- =========================================================================
M.net_wdt_timeout = 240 -- 秒：超过该时长无网络收发则判定异常并恢复

-- =========================================================================
-- 五、硬件看门狗 Air153C（依据 requirement.md 5.8）
-- =========================================================================
-- exair153x_wdt 自动喂狗周期（秒），应远小于 Air153C 超时（约 240s）
M.wdt_feed_period = 60

-- =========================================================================
-- 六、FOTA 远程升级（方式 C：libfota3 + 合宙升级服务器，依据 requirement.md 5.6）
-- =========================================================================
M.fota_project_key = "REPLACE_WITH_REAL_PROJECT_KEY" -- 烧录前必须替换为真实项目 key
M.fota_script_name = "pump_controller"
M.fota_interval    = 12 * 3600 -- 自动检测间隔 12 小时

-- =========================================================================
-- 七、AirCloud 平台参数（依据 network-communication-protocol.md 第 3/6/7 章）
-- =========================================================================
M.cloud_transport          = "tcp" -- 承载通道：TCP
M.cloud_use_getip          = true  -- 合宙公有云：由 getip 动态获取服务器与鉴权参数
M.cloud_auto_reconnect     = true
M.cloud_reconnect_interval = 10    -- 秒
M.cloud_max_reconnect      = 3     -- 连续重连失败后重新 getip
M.cloud_debug              = false

-- 运维日志（依据 requirement.md 5.5：必须启用；使用 4 个 block，直接追加写）
M.mtn_log_enabled          = true
M.mtn_log_blocks           = 4
M.mtn_log_write_way        = excloud.MTN_LOG_ADD_WRITE
M.aircloud_mtn_log_enabled = true
M.mtn_log_upload_cycle     = 300 -- 秒：每 5 分钟定时检查并上传一次运维日志

-- =========================================================================
-- 七.1 PC 模拟器虚拟设备参数（仅 rtos.bsp()=="PC" 时由 excloud_app 注入；真机忽略）
--   说明：excloud 库在 PC 模拟器上自动将设备类型判定为 9（虚拟设备），
--         此时必须提供 virtual_phone_number / virtual_serial_num，否则 excloud.setup 失败。
--   参考：module/Air780EPM/demo/aircloud/config.lua、excloud_main.lua
-- =========================================================================
M.cloud_virtual_phone_number = "13800138000" -- 虚拟设备手机号（11位，运行前须替换为本人已注册号码）
M.cloud_virtual_serial_num   = 1             -- 虚拟设备序列号（0~999，多个模拟器实例须不同）

-- =========================================================================
-- 七.2 模拟器“真机身份”适配（仅 PC 模拟器有效；真机忽略）
--   目标：模拟器使用模拟器网卡（socket.ETH0），但设备身份使用“真机 4G 参数”，
--         使 excloud 按 4G 设备（device_type=1，设备ID=IMEI）接入 AirCloud。
--   实现：sim_identity 模块在 rtos.bsp()=="PC" 时用下列参数覆盖 rtos.bsp / hmeta.model /
--         mobile.imei / mobile.muid；启用后七.1 的虚拟设备参数不再生效（互斥）。
--   前提：sim_real_imei / sim_real_muid 必须为“已归属你 IoT 账号项目”的真机参数，
--         否则平台仍会返回“未进项目及白名单”。
-- =========================================================================
M.sim_real_identity_enabled = true              -- 是否启用：模拟器下以真机(4G)身份接入
M.sim_real_model  = "Air780EPM"                 -- 设备机型（供 hmeta.model / rtos.bsp 返回）
M.sim_real_imei   = "868926081381037"           -- 15位 IMEI（须替换为已归属你账号的真机 IMEI）
M.sim_real_muid   = "REPLACE_WITH_REAL_MUID"    -- 真机 MUID（须替换为与该 IMEI 匹配且已归属的值）

-- =========================================================================
-- 八、AirCloud 上报 TLV 字段编号（依据 network-communication-protocol.md 9.3）
--   标准字段编号为 AirCloud 协议固定值，硬编码（避免 excloud 库版本差异导致常量缺失）；
--   变频器专有字段使用 1536~1548 号
-- =========================================================================
M.DATA_TYPES     = excloud.DATA_TYPES
M.FIELD_MEANINGS = excloud.FIELD_MEANINGS

M.FIELD = {
    outHz     = 1536, -- 运行频率
    setHz     = 1537, -- 设定频率
    muV       = 1538, -- 母线电压
    outV      = 1539, -- 输出电压
    outA      = 1540, -- 输出电流
    outkw     = 1541, -- 输出功率
    H         = 1542, -- 累计运行时间
    oneHz     = 1543, -- 第1次故障时频率
    oneA      = 1544, -- 第1次故障时电流
    twoHz     = 1545, -- 第2次故障时频率
    twoA      = 1546, -- 第2次故障时电流
    threeHz   = 1547, -- 第3次故障时频率
    threeA    = 1548, -- 第3次故障时电流
    -- 标准字段（编号为 AirCloud 协议固定值，硬编码避免 excloud 库版本差异）
    nbTemp    = 256,  -- 256 温度 TEMPERATURE（散热器温度）
    devstate  = 265,  -- 265 工作状态 WORK_STATUS
    timestamp = 1280, -- 1280 时间戳 TIMESTAMP
    -- 下行：泵开关机命令（Type=19 CONTROL_COMMAND 的 JSON 子字段）
    ctrl_switch = 1550,
}

return M
