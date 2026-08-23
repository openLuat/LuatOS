--[[
@module  mobile_apn_test
@summary APN配置演示模块
@version 1.0
@date    2026.07.23
@author  拓毅恒
@usage
本模块演示海外使用时如何正确配置APN。

海外与国内使用的核心区别：
1. 国内：公网卡通常不需要手动设置APN，专网卡才需要设置
2. 海外：不同国家和运营商的SIM卡需要配置对应的APN才能联网

APN配置有两种方式：

方式一（推荐）：使用 mobile.apnTableInit() + mobile.apnTableAdd() 预设APN列表
   系统会根据插入的SIM卡的MCC/MNC自动匹配并设置APN
   适合：大批量出货到不同国家，无需每台设备单独配置

方式二：使用 mobile.apn() 直接设置APN
   适合：已知具体运营商和APN信息，在代码中写死

注意事项：
1. APN 必须在入网前设置好，最好在 SIM 卡识别完成前（写在文件开头）
2. 如果使用方式一，需要在文件开头调用 mobile.apnTableInit() 和 mobile.apnTableAdd()
3. 海外运营商的MCC/MNC和APN信息，请向SIM卡供应商获取
4. 如果不确定APN，建议使用方式一预设多个运营商的APN，系统会自动匹配
]]

-- ====================== APN配置方式选择 ======================

-- 方式一：通过APN列表自动匹配（推荐海外使用）
-- 解除下面代码的注释即可启用

mobile.apnTableInit()
-- 添加不同国家的APN，格式：mobile.apnTableAdd(mcc, mnc, ip_type, protocol, apn_name, user_name, password)
-- 下面是一些示例，实际使用时请替换为真实运营商的APN信息

-- 中国移动（国内示例）
mobile.apnTableAdd(0x460, 0x00, 3, 0, "cmiot", "", "")

-- -- 海外示例（以下MCC/MNC为示意值，请向卡商获取真实值）
-- mobile.apnTableAdd(0x310, 0x410, 3, 0, "isp.att.com", "", "")   -- 美国 AT&T
-- mobile.apnTableAdd(0x310, 0x260, 3, 0, "vzwinternet", "", "")   -- 美国 Verizon
-- mobile.apnTableAdd(0x310, 0x120, 3, 0, "fast.t-mobile.com", "", "") -- 美国 T-Mobile
-- mobile.apnTableAdd(0x234, 0x10, 3, 0, "ibrowse.o2.co.uk", "", "")  -- 英国 O2
-- mobile.apnTableAdd(0x262, 0x01, 3, 0, "internet.telekom", "", "")  -- 德国 T-Mobile
-- mobile.apnTableAdd(0x208, 0x01, 3, 0, "orange.fr", "", "")        -- 法国 Orange
-- mobile.apnTableAdd(0x440, 0x10, 3, 0, "bmobile.jp", "", "")       -- 日本 b-mobile
-- mobile.apnTableAdd(0x450, 0x05, 3, 0, "internet", "", "")         -- 韩国 SK Telecom

-- 方式二：直接设置APN（适用于已知具体运营商的场景）
-- 解除下面代码的注释，替换为实际的APN信息
-- mobile.apn(0, 1, "your_apn_name", "user_name", "password", nil, 0)


-- ====================== 海外APN联网测试 ======================

-- SIM卡状态订阅
local function sim_status_handler(status, value)
    log.info("mobile_apn_test", "SIM状态:", status)
    if status == 'RDY' then
        log.info("mobile_apn_test", "SIM卡就绪")
    end
    if status == 'NORDY' then
        log.info("mobile_apn_test", "无SIM卡")
    end
    if status == 'GET_NUMBER' then
        log.info("mobile_apn_test", "手机号:", mobile.number(0))
    end
end
sys.subscribe("SIM_IND", sim_status_handler)

-- 网络状态监控任务
local function network_monitor_task()
    sys.wait(3000)

    while 1 do
        local status = mobile.status()
        local current_apn = mobile.apn()
        local imei = mobile.imei()
        local imsi = mobile.imsi()
        local csq = mobile.csq()
        local rssi = mobile.rssi()
        local rsrp = mobile.rsrp()
        local rsrq = mobile.rsrq()
        local snr = mobile.snr()
        local sim_id = mobile.simid()

        log.info("mobile_apn_test", "==================== 网络状态 ====================")
        log.info("mobile_apn_test", "IMEI:", imei)
        log.info("mobile_apn_test", "IMSI:", imsi)
        log.info("mobile_apn_test", "当前APN:", current_apn)
        log.info("mobile_apn_test", "网络状态:", status, "(0=未注册,1=已注册,2=搜索中)")
        log.info("mobile_apn_test", "信号强度 CSQ:", csq, "RSSI:", rssi, "dBm")
        log.info("mobile_apn_test", "信号质量 RSRP:", rsrp, "dBm RSRQ:", rsrq, "dB SNR:", snr, "dB")
        log.info("mobile_apn_test", "当前SIM卡槽:", sim_id)
        log.info("mobile_apn_test", "==================================================")

        -- 检查联网状态
        if status == 1 then
            log.info("mobile_apn_test", "网络注册成功，APN:", current_apn)
        else
            log.info("mobile_apn_test", "网络未注册，等待注册...")
        end

        sys.wait(15000)
    end
end

sys.taskInit(network_monitor_task)

log.info("mobile_apn_test", "海外APN配置演示模块加载完成")
