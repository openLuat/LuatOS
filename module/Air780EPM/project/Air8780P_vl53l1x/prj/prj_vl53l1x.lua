--[[
@module  prj_vl53l1x
@summary Air8780P VL53L1X激光测距传感器低功耗数据采集与上报项目编排模块
@version 2.0
@date    2026.07.23
@author  江访
@usage
本文件为项目主业务编排模块，负责协调各功能模块完成完整业务流程。

三层架构说明：
  drv/     硬件驱动层 — 通过 sys.subscribe 注册，事件驱动
            drv_led      → LED_SET_HIGH / LED_SET_LOW
            drv_psm      → DRV_SET_PSM

  app/     应用功能层 — return table，直接调用
            sensor_vl53l1x — 传感器驱动封装
            aircloud       — 云平台数据上报
            fota_mgr       — FOTA远程升级管理

  prj/     项目编排层 — 本文件，协调业务流程

完整业务流程：
   ① 发布LED_SET_HIGH → drv_led点亮LED
   ② 检查FOTA首次启动（fota_mgr.check_first_boot）
   ③ 初始化传感器（sensor_vl53l1x.init）
   ④ 采集传感器数据（sensor_vl53l1x.collect_data）
   ⑤ 关闭传感器（sensor_vl53l1x.close）
   ⑥ 等待4G网络就绪
   ⑦ 初始化excloud连接（aircloud.init）
   ⑧ 双通道上报（aircloud.report_excloud + report_mqtt）
   ⑨ FOTA升级检查（fota_mgr.check_and_upgrade）
   ⑩ 关闭传感器 + 发布LED_SET_LOW → drv_led熄灭LED
   ⑪ 发布DRV_SET_PSM → drv_psm进入PSM+

消息协议（发布/订阅）:
  发布: LED_SET_HIGH(gpio)      → drv_led: 拉高LED
  发布: LED_SET_LOW(gpio)       → drv_led: 拉低LED
  发布: DRV_SET_PSM(sleep_min)  → drv_psm: 进入PSM+模式

本文件没有对外接口，require "prj_vl53l1x"即可加载运行
]]

-- ==================== 加载应用功能模块（app层，return table直接调用） ====================

-- sensor_vl53l1x: VL53L1X传感器驱动封装，提供init/collect_data/close接口
local sensor_vl53l1x = require "sensor_vl53l1x"

-- aircloud: 云平台数据上报，封装excloud和MQTT双通道上报
local aircloud = require "aircloud"

-- fota_mgr: FOTA远程升级管理，含版本文件管理和首次启动检测
local fota_mgr = require "fota_mgr"

-- ==================== 加载硬件驱动模块（drv层，事件订阅，不返回接口表） ====================

-- drv_led: LED指示灯控制，订阅LED_SET_HIGH/LED_SET_LOW消息
--           通过sys.publish("LED_SET_HIGH", gpio)控制LED点亮
--           通过sys.publish("LED_SET_LOW", gpio)控制LED熄灭
require "drv_led"

-- drv_psm: PSM+低功耗模式驱动，订阅DRV_SET_PSM消息
--           通过sys.publish("DRV_SET_PSM", sleep_min)进入PSM+模式
--           进入前需要先关闭外设和熄灭LED
require "drv_psm"

-- ==================== 可配置参数 ====================
-- 用户可根据项目需求修改以下参数
-- 这些参数决定了设备的工作行为和功耗表现

local CFG = {
    -- PSM+休眠时间（分钟）
    -- 唤醒后重新开始完整的数据采集和上报循环
    -- 合宙IoT平台建议最多10分钟请求一次，建议≤10
    psm_sleep_min_s   = 15,

    -- 开机到进入PSM+的超时上限（秒）
    -- 到时间后不管任务2是否完成，都强制进入PSM+
    psm_entry_max_s   = 90,

    -- FOTA等待最长时间（秒）
    -- 超时说明网络不好，进入PSM+下次再试
    fota_wait_max_s   = 600,

    -- 每次唤醒后采集传感器的次数
    -- 多次采集取平均值可以降低单次测量误差
    sensor_samples    = 3,

    -- 测距模式
    -- "short" — 短距离（~1.36m），抗环境光能力强
    -- "standard" — 标准距离（~2.9m），通用场景
    -- "long" — 长距离（~4.6m），需较好的环境光条件
    sensor_range_mode = "standard",

    -- I2C引脚定义（软件I2C模式）
    gpio_i2c_scl      = 1,      -- I2C SCL（GPIO1）
    gpio_i2c_sda      = 2,      -- I2C SDA（GPIO2）
    gpio_led_ctrl     = 27,     -- LED指示灯，高电平点亮，PSM+前熄灭

    -- MQTT配置（使用合宙测试服务器）
    mqtt_broker       = "lbsmqtt.airm2m.com",
    mqtt_port         = 1884,
}

-- ==================== 网络等待工具函数 ====================

--[[
等待4G网络就绪

通过socket.adapter判断默认网卡是否已获得IP地址。
每秒检查一次，同时等待IP_READY消息，兼顾即时性和兜底。

@param number timeout_s 等待超时时间（秒），默认120秒
@return boolean true=网络就绪，false=超时未就绪
]]
local function wait_network_ready(timeout_s)
    timeout_s = timeout_s or 120
    log.info("prj_vl53l1x", "等待4G网络就绪，最长" .. timeout_s .. "秒...")
    for i = 1, timeout_s do
        if socket.adapter(socket.dft()) then
            log.info("prj_vl53l1x", "4G网络已就绪，IP:", socket.localIP(socket.LWIP_GP))
            return true
        end
        log.warn("prj_vl53l1x", "等待IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    log.warn("prj_vl53l1x", "4G网络等待超时（未插卡或无信号），跳过联网操作")
    return false
end

-- ==================== 项目主任务 ====================

local function vl53l1x_task()
    log.info("prj_vl53l1x", "========== Air8780P VL53L1X 主任务启动 ==========")

    -- ==================== 第一步：LED点亮 ====================
    -- 通过事件驱动drv_led模块控制GPIO
    -- drv_led接收到LED_SET_HIGH消息后，将指定GPIO拉高
    sys.publish("LED_SET_HIGH", CFG.gpio_led_ctrl)

    -- ==================== 第二步：检查FOTA首次启动 ====================
    -- 比对版本标记文件中的版本号与当前运行版本号
    -- 如果版本不一致，说明经历了FOTA升级并重启
    -- 返回的字符串包含升级前后版本信息，需在上报时附带
    local fota_first_boot_info = fota_mgr.check_first_boot()
    if fota_first_boot_info then
        log.info("prj_vl53l1x", "FOTA升级后首次启动:", fota_first_boot_info)
    end

    -- ==================== 第三步：初始化传感器 ====================
    -- 配置I2C引脚并初始化VL53L1X传感器
    -- 如果初始化失败，跳过数据采集步骤
    local sensor_ok = sensor_vl53l1x.init(CFG.gpio_i2c_scl, CFG.gpio_i2c_sda, CFG.sensor_range_mode)

    -- ==================== 第四步：采集传感器数据 ====================
    -- 采集多次后取平均值，降低单次测量误差
    local sensor_data = nil
    if sensor_ok then
        sensor_data = sensor_vl53l1x.collect_data(CFG.sensor_samples)
        if sensor_data then
            log.info("prj_vl53l1x", string.format("测距结果 = %d mm (有效%d帧)",
                sensor_data.avg_distance, sensor_data.valid_count))
        else
            log.warn("prj_vl53l1x", "测距结果 = 无效（所有帧均未测到目标）")
        end
        -- 采集完成后立即关闭传感器，降低功耗
        sensor_vl53l1x.close()
    end

    -- ==================== 第五步：等待4G网络就绪 ====================
    -- 如果超时，跳过所有需要联网的操作
    local net_ok = wait_network_ready()

    if net_ok then
        -- ==================== 第六步：初始化excloud连接 ====================
        -- 连接到合宙IoT平台，等待认证完成
        aircloud.init({transport = "tcp", auto_reconnect = true, reconnect_interval = 10, max_reconnect = 3})

        -- ==================== 第七步：双通道数据上报 ====================
        -- 通过excloud（合宙IoT平台）和MQTT双通道同时上报
        local mqtt_topic = mobile.imei() .. "/vl53l1x/up"
        local mqtt_payload

        if fota_first_boot_info then
            -- FOTA升级后首次启动：上报升级信息+传感器数据
            local fota_msg = "FOTA升级成功: " .. fota_first_boot_info
            aircloud.report_excloud(sensor_data, fota_msg)
            mqtt_payload = aircloud.build_mqtt_payload(sensor_data, fota_msg)
            -- 上报完成后删除版本文件，避免下次重启再次上报
            fota_mgr.clear_version_file()
        else
            -- 正常启动：仅上报传感器数据
            aircloud.report_excloud(sensor_data, nil)
            mqtt_payload = aircloud.build_mqtt_payload(sensor_data, nil)
        end
        aircloud.report_mqtt(mqtt_topic, mqtt_payload, CFG.mqtt_broker, CFG.mqtt_port)

        -- ==================== 第八步：FOTA升级检查 ====================
        -- 非FOTA后首次启动才检查FOTA升级
        if not fota_first_boot_info then
            aircloud.report_fota_status("FOTA: 正在检查/升级中", sensor_data)
            local need_reboot = fota_mgr.check_and_upgrade(CFG.fota_wait_max_s)
            if need_reboot then
                aircloud.report_excloud(nil, "FOTA升级包下载成功, 升级前版本: " .. VERSION)
                sys.wait(1000)
                rtos.reboot()
            end
        end
    else
        -- 无网络：跳过所有联网操作，直接进入PSM+
        if fota_first_boot_info then
            fota_mgr.clear_version_file()
        end
        log.info("prj_vl53l1x", "无网络，跳过上报和FOTA检查")
    end

    -- ==================== 第九步：关闭外设并进入PSM+ ====================
    -- 关闭传感器
    sensor_vl53l1x.close()

    -- 熄灭LED（通过事件驱动drv_led）
    -- drv_led接收到LED_SET_LOW消息后，将指定GPIO拉低
    sys.publish("LED_SET_LOW", CFG.gpio_led_ctrl)

    log.info("prj_vl53l1x", "所有业务完成，准备进入PSM+模式，休眠" .. CFG.psm_sleep_min_s .. "分钟")

    -- 发布PSM+进入消息，通知drv_psm模块
    -- drv_psm接收到DRV_SET_PSM消息后，在独立协程中执行：
    --   1. 设置深度休眠定时器（dtimer）
    --   2. 调用pm.power(pm.WORK_MODE, 3)
    --   3. 等待80秒后如果未进入PSM+则强制重启
    -- drv_psm模块内部已有中断唤醒引脚和功能引脚的配置说明
    sys.publish("DRV_SET_PSM", CFG.psm_sleep_min_s)
end

-- ==================== 启动项目主任务 ====================

sys.taskInit(vl53l1x_task)
