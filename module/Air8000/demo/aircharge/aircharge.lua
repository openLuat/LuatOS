-- 

--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.11.25
@author  王世豪
@usage
本demo为Air8000/8000G/8000XB/8000GB 的电池充电管理示例，演示的核心功能为：
使用exchg库管理Air8000系列内置的YHM2712充电IC，包括配置电池参数，注册事件回调，处理充电状态变化。

历史背景：
本demo原本是专为内置充电IC的Air8000/8000G/8000XB/8000GB所设计，但是Air8000系列内置充电IC会存在以下问题，故含有充电管理的型号已不再推荐：
1，内置的充电管理芯片，不仅只负责充电，也负责供电路径管理、供电短路保护等；
2，当大家使用的不是电池，而是由诸如充电器等类似电源供电时，如电路连接不当，非常容易造成给DCDC充电的效果，进而形成VBAT供电的混乱；
3，同时，如果快速的下电和上电，内置的充电管理芯片会根据电压的快速跌落而判断电源短路，继而把VBAT供电电路断开，造成的后果就是不能开机、无法下载、电脑无法识别USB等，本质都是充电管理芯片的主动保护造成的；
4，出现充电管理芯片的短路保护之后，一般要过一段时间等板子上电容的余电放光后，也就是充电管理芯片的保护功能失效后再上电开机，或者通过插入充电器(充电器接模组VCHG管脚的前提之下)来退出短路保护；
5，即便是电池供电，如果系统设计上增加了类似于拨动开关一类的上下电的复位设计，在含有充电管理的这些型号上，也需要在断电一段时间后(取决于板载电容的大小，电容越大，余电放电越慢，充电IC的保护作用就越长)再上电，
    否则仍然会有长时间无法开机的风险(快速的下电和上电，根据实测，大家在2分钟左右会恢复正常开机)；

适用场景：
本软件模块旨在对 Air8000 系列 已内置的 YHM2712 充电管理IC 进行功能管理与状态监控。
主要应用场景为标准的 “电池供电 + 需要通过VCHG引脚进行充电” 的应用。在此场景下，本模块提供以下核心功能：
1. 电池充电管理：用于管理Air8000系列内置的YHM2712充电IC，包括配置电池参数，注册事件回调，处理充电状态变化。
2. 电池过放保护：当电池电压快速下降到1V以下时，充电IC会触发过放保护，切断VBAT到系统内部供电的电路，防止电池过放。
3. 电池充电完成检测：充电IC会在电池充电完成后触发事件，用于检测充电是否完成。
4. 电池电压测量：充电IC可以测量电池电压，用于实时监控电池状态。

更详细的Air8000系列特别说明，请查看：https://docs.openluat.com/air8000/product/notice/
更多说明参考本目录下的readme.md文件
]]

local exchg = require("exchg")

-- 配置参数
local BATTERY_VOLTAGE = 4200                -- 电池充电截止电压(mV): 4200或4350
local BATTERY_CAPACITY = 400                -- 电池容量(mAh)，根据实际电池容量设置
local CHARGE_CURRENT_MODE = exchg.CCDEFAULT -- 充电电流模式: exchg.CCMIN/exchg.CCDEFAULT/exchg.CCMAX

-- 上次充电状态，用于状态变化检测
local last_charge_status = nil
local last_battery_voltage = 0
local last_charger_state = false

-- 充电状态描述映射
local charge_stage_map = {
    [0] = "放电模式",
    [1] = "预充电模式",
    [2] = "涓流充电",
    [3] = "恒流快速充电",
    [4] = "预留状态",
    [5] = "恒压快速充电",
    [6] = "预留状态",
    [7] = "充电完成",
    [8] = "未知状态"
}

-- 事件回调函数
local function exchg_event_callback(event)
    if event == exchg.OVERHEAT then
        log.info("充电管理", "警告: 设备温度过高！请暂停充电")
    elseif event == exchg.CHARGER_IN then
        log.info("充电管理", "充电器已插入")
    elseif event == exchg.CHARGER_OUT then
        log.info("充电管理", "充电器已拔出")
    end
end

-- 格式化电池电压显示
local function format_battery_voltage(voltage)
    if voltage < 0 then
        if voltage == -1 then return "当前阶段不需要测量" end
        if voltage == -2 then return "电压测量失败" end
        if voltage == -3 then return "仅充电器就绪（无电池）" end
        return "未知错误"
    end
    return string.format("%.2fV", voltage / 1000)
end

-- 计算电池电量百分比（简单估算）
local function calculate_battery_percentage(voltage)
    if voltage < 0 then return 0 end

    -- 简单的电压到百分比映射，实际应根据电池特性调整
    local min_voltage = 3300            -- 3.3V，电池最低电压
    local max_voltage = BATTERY_VOLTAGE -- 充电截止电压

    if voltage <= min_voltage then
        return 0
    elseif voltage >= max_voltage then
        return 100
    end

    -- 线性计算百分比（简单估算）
    local percentage = (voltage - min_voltage) / (max_voltage - min_voltage) * 100
    return math.floor(percentage)
end

-- 显示充电信息的函数
local function display_charge_info(status)
    if not status.result then
        log.error("充电管理", "获取充电状态失败")
        return
    end

    -- 计算电量百分比
    local percentage = calculate_battery_percentage(status.vbat_voltage)

    -- 格式化日志输出
    log.info("充电管理", string.format("电池电压: %s (%d%%)",
        format_battery_voltage(status.vbat_voltage), percentage))
    log.info("充电管理", string.format("充电阶段: %s",
        charge_stage_map[status.charge_stage] or "未知"))
    log.info("充电管理", string.format("充电完成: %s",
        status.charge_complete and "是" or "否"))
    log.info("充电管理", string.format("电池在位: %s",
        status.battery_present and "是" or "否"))
    log.info("充电管理", string.format("充电器在位: %s",
        status.charger_present and "是" or "否"))
    log.info("充电管理", string.format("IC过热: %s",
        status.ic_overheat and "是" or "否"))

    -- 检测并记录状态变化
    if last_charge_status ~= status.charge_stage then
        log.info("充电管理", string.format("状态变化: %s -> %s",
            charge_stage_map[last_charge_status] or "未知",
            charge_stage_map[status.charge_stage] or "未知"))
        last_charge_status = status.charge_stage
    end

    -- 检测电池电压变化超过100mV
    if math.abs(status.vbat_voltage - last_battery_voltage) > 100 and status.vbat_voltage > 0 then
        log.info("充电管理", string.format("电压变化显著: %.2fV", status.vbat_voltage / 1000))
        last_battery_voltage = status.vbat_voltage
    end

    -- 检测充电器状态变化
    if last_charger_state ~= status.charger_present then
        last_charger_state = status.charger_present
        log.info("充电管理", "充电器状态变化: " .. (status.charger_present and "连接" or "断开"))
    end
end

-- 电池管理任务
local function battery_management_task()
    log.info("充电管理", "初始化电池管理...")

    -- 注册事件回调
    exchg.on(exchg_event_callback)

    -- 设置电池参数
    log.info("充电管理", string.format("设置电池参数: %.2fV, %dmAh, %s",
        BATTERY_VOLTAGE / 1000, BATTERY_CAPACITY, CHARGE_CURRENT_MODE))

    local setup_result = exchg.setup(BATTERY_VOLTAGE, BATTERY_CAPACITY, CHARGE_CURRENT_MODE)
    if setup_result then
        log.info("充电管理", "电池参数设置成功")
    else
        log.error("充电管理", "电池参数设置失败，检查芯片是否支持")
        return
    end

    -- 启动充电（可选，根据exchg库说明，通常不需要手动调用）
    -- 但为了演示完整流程，这里包含调用示例
    log.info("充电管理", "尝试启动充电...")
    local start_result = exchg.start()
    if start_result then
        log.info("充电管理", "充电启动成功")
    else
        log.warn("充电管理", "充电启动失败或已自动启动")
    end

    log.info("充电管理", "开始监控电池状态...")

    -- 主循环，定期检查电池状态
    while true do
        -- 获取充电状态
        local status = exchg.status()
        if status then
            -- 显示充电信息
            display_charge_info(status)

            -- 如果电池充满电，可以添加相应处理
            if status.charge_complete and status.charger_present then
                log.info("充电管理", "电池已充满！")
            end

            -- 如果充电IC过热，采取保护措施
            if status.ic_overheat then
                log.warn("充电管理", "充电IC过热，正在暂停充电...")
                exchg.stop()
                log.info("充电管理", "充电已暂停，请等待设备降温")
                -- 等待一段时间后再次尝试
                sys.wait(60000) -- 等待60秒
                log.info("充电管理", "尝试恢复充电...")
                exchg.start()
            end
        else
            log.error("充电管理", "无法获取充电状态")
        end

        -- 根据状态调整检查频率
        if last_charger_state then
            -- 充电中，更频繁地检查
            sys.wait(20000) -- 20秒
        else
            -- 未充电，降低检查频率
            sys.wait(60000) -- 60秒
        end
    end
end

-- 系统初始化完成后执行
sys.taskInit(battery_management_task)