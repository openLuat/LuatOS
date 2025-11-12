--[[
@module  mobile_test
@summary Air8000 mobile功能测试模块
@version 1.0
@date    2025.10.21
@author  拓毅恒
@usage
本文件为 Air8000 开发板演示移动网络功能的代码示例，核心业务逻辑包括：
1. SIM卡管理和选择（自动选卡功能）
2. 基站数据查询（订阅式和轮询式两种方式）
3. 频段（Band）测试和修改
4. 移动网络信息获取（IMEI、IMSI、信号强度等）
5. SIM卡状态监控
]]

-- 对于双卡的设备, 可以设置为自动选sim卡
-- 但是SIM1所在管脚就强制复用为SIM功能, 占用4个IO口(gpio4/5/6/23)，不可以再复用为GPIO
-- mobile.simid(2)
mobile.simid(2,true)--优先用SIM0

-- 设置默认APN
-- 注意：APN 必须在入网前就设置好；在国内公网卡基本上都不需要设置APN, 专网卡才需要设置
mobile.apn(0,1,"","","",nil,0)

-- 基站数据的查询
-- 订阅式, 模块本身会周期性查询基站信息,但通常不包含临近小区
local function sub_cell_info_task()
    log.info("cell", json.encode(mobile.getCellInfo()))
end

sys.subscribe("CELL_INFO_UPDATE", sub_cell_info_task)

-- 轮询式, 包含临近小区信息，这是手动搜索，和上面的自动搜索冲突，开启一个就行
local function get_cell_info_task()
    sys.wait(5000)
	mobile.config(mobile.CONF_SIM_WC_MODE, 2)
    while 1 do
        mobile.reqCellInfo(10)
        sys.wait(11000)
        log.info("cell", json.encode(mobile.getCellInfo()))
		mobile.config(mobile.CONF_SIM_WC_MODE, 2)
    end
end

-- 获取sim卡的状态
local function get_sim_status_task(status, value)
    log.info("sim status", status)
    if status == 'RDY' then
        log.info("sim", "sim OK", value)
    end
    if status == 'NORDY' then
        log.info("sim", "NO sim", value)
    end
    if status == 'GET_NUMBER' then
        log.info("number", mobile.number(0))
    end
	if status == "SIM_WC" then
        log.info("sim", "write counter", value)
    end
end

sys.subscribe("SIM_IND", get_sim_status_task)

-- SIM 卡热插拔功能，通过gpio中断通过上下边沿电平触发中断
-- 设置防抖，使用wakeup6脚，常量为gpio.WAKEUP6
-- 自己设计其他gpio热插拔只需要替换对应的gpio即可
gpio.debounce(gpio.WAKEUP6,500)
-- 设置中断触发，拔卡进入飞行模式，插卡进出飞行模式，val值为上升沿或者下降沿触发0/1
local function sim_hot_plug(val)
    if val==0 then
        log.info("插卡")
        mobile.flymode(0,true)
        mobile.flymode(0,false)
    else
        log.info("拔卡")
        mobile.flymode(0,true)
    end
end

gpio.setup(gpio.WAKEUP6,sim_hot_plug)

-- 定义测试band和移动网络信息的函数
local function mobileinfo_task()
    -- 开启SIM暂时脱离后自动恢复，30秒搜索一次周围小区信息
    mobile.setAuto(10000,30000, 5) -- 此函数仅需要配置一次

    log.info("************开始测试band************")
    local band = zbuff.create(40)
    local band1 = zbuff.create(40)
    mobile.getBand(band)
    log.info("当前使用的band:")
    for i=0,band:used()-1 do
        log.info("band", band[i])
    end
    band1[0] = 38
    band1[1] = 39
    band1[2] = 40
    mobile.setBand(band1, 3)    --改成使用38,39,40
    band1:clear()
    mobile.getBand(band1)
    log.info("修改后使用的band:")
    for i=0,band1:used()-1 do
        log.info("band", band1[i])
    end
    mobile.setBand(band, band:used())    --改回原先使用的band，也可以下载的时候选择清除fs

    mobile.getBand(band1)
    log.info("修改回默认使用的band:")
    for i=0,band1:used()-1 do
        log.info("band", band1[i])
    end
    log.info("************band测试完毕************")

	log.info("status", mobile.status())
    sys.wait(2000)
    while 1 do
        log.info("imei", mobile.imei())
        log.info("imsi", mobile.imsi())
        log.info("apn", mobile.apn()) -- 获取当前APN
        log.info("status", mobile.status())
        log.info("iccid", mobile.iccid())
        log.info("csq", mobile.csq()) -- 4G模块的CSQ并不能完全代表强度
        log.info("rssi", mobile.rssi()) -- 需要综合rssi/rsrq/rsrp/snr一起判断
        log.info("rsrq", mobile.rsrq())
        log.info("rsrp", mobile.rsrp())
        log.info("snr", mobile.snr())
        log.info("simid", mobile.simid()) -- 这里是获取当前SIM卡槽
        log.info("apn", mobile.apn(0,1))
        -- sys内存
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        sys.wait(15000)
    end
end

-- 轮询式查找小区, 包含临近小区信息，与上面订阅式搜索冲突，开启一个就行
-- sys.taskInit(get_cell_info_task)
-- 启动测试任务
sys.taskInit(mobileinfo_task)
