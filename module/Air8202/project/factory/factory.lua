--[[
@module  factory
@summary Air8202 出厂固件产测模块（指令/管脚对齐同事 Air8202C 已验证产测代码，V3 fskv+OTP 分流）
@version 1.0
@date    2026.10.20
@usage
本模块为 Air8202 出厂固件的产测模式，V3 启动分流由 main.lua 完成（fskv 返工标记 → OTP1 判空）。
产测通过 USB 虚拟串口 uart.VUART_0 收发指令，波特率 115200，指令以 # 结尾、逗号分隔。
- 首次产测：MODEL/HVERSION 写号入 OTP1，TEST_DONE 校验 OTP1 非空后重启进正常模式
- 返工产测：fskv 有 model_retest 标记，TEST_DONE 删除标记（不动 OTP1）后重启进正常模式
- 返工指令 MODEL_RETEST#CONFIRM / MODEL_RETEST? 由 retest 模块在 proc 前拦截

指令集（严格对齐同事 Air8202C 产测代码）：
  VERSION / LED / IMEI / IMSI / ICCID / CSQ / MUID / VBAT / ECNPICFG
  GPSTEST(内置GNSS透传) / LSENSE(光敏防拆ADC0) / GS_STATE(DA221加速度ID)
  CHG_TEST(yhm2712a单总线) / WD_TEST(153c看门狗) / FLYMODE
  MODEL/MODEL?(OTP PROD) / HVERSION(OTP PCB) / META?
  RST / TEST_DONE / PCBA_TEST_DONE

管脚（主控 Air780EGP/Air780EGG，EC7xx，与同事 Air8202C 产测代码及 board.lua 双重核对一致）：
  GPIO26 蓝色LED / GPIO27 红色LED（LED 指令双灯同控）
  GPIO24 153c 看门狗喂狗脚（NPN 反相）
  GPIO28 光敏防拆供电，ADC 通道 0
  GPIO23 SIM 上拉 / GNSS Vref / 内置 G-Sensor 供电（保持常开）
  GPIO25 yhm2712a 充电单总线 CMD（空闲保持高）
  GPIO21 内置 GNSS 供电使能
  I2C1  0x27 内置 DA221 加速度（ID 寄存器 0x01，期望 0x13）
  UART2 内置 GNSS 串口

看门狗：与正常模式 air153c_wdt.lua 同路径，统一使用 script/libs 官方新版 exair153x_wdt
（GPIO 空闲低/WTDOG 常态高，2000/250/200ms 喂狗波形），不再使用同事产测固件自带的旧版库。
]]

local factory = {}

local prodmeta = require("prodmeta")
-- V3 返工标记（fskv model_retest）：区分首测/返工，返工通过后删标记
local retest = require("retest")
local isRetest = retest.is_set()
log.info("测试模式", "本次产测类型:", isRetest and "返工产测（不动OTP1）" or "首次产测（写号入OTP1）")

-- 153c 外置硬件看门狗：与正常模式共用 script/libs 官方新版库（缺库时 WD_TEST 返回 ERROR）
local ok_wdt, exair153x_wdt = pcall(require, "exair153x_wdt")
-- 内置 GNSS（pcall 守卫，缺库不崩）
local ok_exgnss, exgnss = pcall(require, "exgnss")

log.info("测试模式", "启动中 版本:", PROJECT, VERSION)

-- ============================================================
-- 硬编码管脚定义（主控 Air780EGP，与 Air8202C 产测代码一致）
-- ============================================================
local BLUE_LED_PIN = 26        -- 蓝色LED
local RED_LED_PIN = 27         -- 红色LED
local WD_FEED_PIN = 24         -- 153c 看门狗喂狗脚（NPN 反相）
local LSENSE_POWER_PIN = 28    -- 光敏防拆供电
local LSENSE_ADC_CH = 0        -- 光敏检测 ADC 通道
local SIM_VREF_PIN = 23        -- SIM 上拉 / GNSS Vref / G-Sensor 供电，保持常开
local CHG_CMD_PIN = 25         -- yhm2712a 充电单总线 CMD，空闲保持高
local GNSS_POWER_PIN = 21      -- 内置 GNSS 供电使能
local GSENSOR_I2C_ID = 1       -- 内置 DA221 加速度 I2C
local GSENSOR_I2C_ADDR = 0x27

local usbTrans = uart.VUART_0
local gnssUartId = 2

-- 初始化变量
local usbRxCache = ""
local cacheTable = {}
local gnssTransFlag = false

local blueLed = gpio.setup(BLUE_LED_PIN, 0)
local redLed = gpio.setup(RED_LED_PIN, 0)

-- SIM 卡上拉 / GNSS Vref / G-Sensor 供电：保持常开
gpio.setup(SIM_VREF_PIN, 1)
-- yhm2712a 充电总线：空闲保持高，避免 CMD 长时间拉低触发芯片看门狗复位
gpio.setup(CHG_CMD_PIN, 1)
-- 默认关闭 GNSS 供电（由 GPSTEST 指令控制）
gpio.setup(GNSS_POWER_PIN, 0)
-- 光敏防拆供电默认关闭
gpio.setup(LSENSE_POWER_PIN, 0)

-- 153c 外置看门狗：自动喂狗，周期 180s（与正常模式 air153c_wdt.lua 一致）
if exair153x_wdt then
    exair153x_wdt.init({ wdt_pin = WD_FEED_PIN, auto_feed_period_s = 180 })
else
    log.error("测试模式", "未找到 exair153x_wdt 库，看门狗相关指令将返回 ERROR")
end

-- ============================================================
-- 通用辅助函数
-- ============================================================
local function send_response(transId, data)
    table.insert(cacheTable, { transId = transId, data = data })
    sys.publish("DATA_SEND")
end

-- GNSS 电源控制
local function gnssPower(onoff)
    gpio.setup(GNSS_POWER_PIN, onoff and 1 or 0)
end

-- ============================================================
-- 异步事件处理任务（含 sys.wait 的测试不能在 uart 回调里执行）
-- ============================================================
sys.taskInit(function()
    while true do
        local result, param1, param2 = sys.waitUntil("CONTROL")
        log.info("CONTROL", param1)
        if param1 == "GNSS" then
            -- GNSS 重新上电
            gnssPower(false)
            sys.wait(10)
            gnssPower(true)
        elseif param1 == "LSENSE" then
            -- 光敏防拆测试：开供电，稳定后读 adc0 电压值（上位机亮光/遮光各发一次对比）
            gpio.setup(LSENSE_POWER_PIN, 1)
            sys.wait(100)
            adc.open(LSENSE_ADC_CH)
            local vadc = adc.get(LSENSE_ADC_CH)
            adc.close(LSENSE_ADC_CH)
            if vadc then
                send_response(param2, vadc .. "#")
            else
                send_response(param2, "ERROR#")
            end
        elseif param1 == "ECNPICFG" then
            -- RF 校准标志位：mobile.ecnpicfg() 返回布尔
            local response = mobile.ecnpicfg()
            log.info("ecnpicfg: ", response)
            if response == true then
                send_response(param2, "true#")
            elseif response == false then
                send_response(param2, "false#")
            else
                send_response(param2, "ERROR#")
            end
        end
    end
end)

-- ============================================================
-- 指令表
-- ============================================================
local procTable = {
    ["VERSION"] = function(id, findCom, data)
        return PROJECT .. "_" .. VERSION
    end,
    ["LED"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        blueLed(onoff)
        redLed(onoff)
        return "OK"
    end,
    ["IMEI"] = function(id, findCom, data)
        local v = mobile.imei()
        if not v or v == "" then return "ERROR" end
        return v
    end,
    ["IMSI"] = function(id, findCom, data)
        local v = mobile.imsi()
        if not v or v == "" then return "ERROR" end
        return v
    end,
    ["ICCID"] = function(id, findCom, data)
        local v = mobile.iccid()
        if not v or v == "" then return "ERROR" end
        return v
    end,
    ["CSQ"] = function(id, findCom, data)
        local v = mobile.csq()
        if v == nil then return "ERROR" end
        return v
    end,
    ["MUID"] = function(id, findCom, data)
        local v = mobile.muid()
        if not v or v == "" then return "ERROR" end
        return v
    end,
    ["GPSTEST"] = function(id, findCom, data)
        if not ok_exgnss or not libgnss then
            log.error("GPSTEST", "固件无 libgnss（LUAT_USE_LIBGNSS）或 exgnss 不可用")
            return "ERROR"
        end
        if data == "0" then
            gnssTransFlag = false
            exgnss.close_all()
            gnssPower(false)
            uart.on(gnssUartId, "receive")
            uart.close(gnssUartId)
        elseif data == "1" then
            gnssTransFlag = true
            local gnssotps = {
                gnssmode = 1,
                agps_enable = true,
                debug = true,
                uart = gnssUartId,
                uartbaud = 115200,
                bind = usbTrans,          -- NMEA 直接透传给 USB 上位机看定位
                auto_open = true,
                gnss_volgpio = GNSS_POWER_PIN
            }
            exgnss.setup(gnssotps)
            exgnss.open(exgnss.DEFAULT, { tag = "gpsTest", cb = function(tag)
                log.info("GPS测试", "GNSS回调", tag)
                local rmc = exgnss.rmc(2)
                if rmc and rmc.valid then
                    log.info("GPS定位成功", "纬度:", rmc.lat, "经度:", rmc.lng)
                end
            end })
            -- 提高 NMEA 输出频率，方便上位机快速看到定位
            sys.timerStart(uart.write, 500, gnssUartId, "$CFGTP,1000000,500000,7,0,800,0*7D\r\n")
        else
            return "ERROR"
        end
        return "OK"
    end,
    ["LSENSE"] = function(id, findCom, data)
        -- LSENSE,1# 开供电读 adc0 返回电压值；LSENSE,0# 关光敏供电
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        if onoff == 0 then
            gpio.setup(LSENSE_POWER_PIN, 0)
            return "OK"
        end
        sys.publish("CONTROL", "LSENSE", id)
        return
    end,
    ["GS_STATE"] = function(id, findCom, data)
        -- 内置 DA221 加速度：软复位后读芯片 ID（寄存器 0x01，期望 0x13），供电 GPIO23 已常开
        i2c.setup(GSENSOR_I2C_ID, i2c.SLOW)
        i2c.send(GSENSOR_I2C_ID, GSENSOR_I2C_ADDR, {0x00, 0x24}, 1) -- 软件复位
        i2c.send(GSENSOR_I2C_ID, GSENSOR_I2C_ADDR, 0x01, 1)         -- 读芯片 ID
        local chipid = i2c.recv(GSENSOR_I2C_ID, GSENSOR_I2C_ADDR, 1)
        i2c.close(GSENSOR_I2C_ID)
        if chipid and string.byte(chipid) == 0x13 then
            return "OK"
        else
            log.error("GSENSOR_TEST", "读取DA221芯片ID失败", chipid)
            return "ERROR"
        end
    end,
    ["CHG_TEST"] = function(id, findCom, data)
        -- yhm2712a 充电电路测试：单总线读芯片 ID，通信成功即认为充电 IC 在位且总线正常
        local result, chipid = pm.chgcmd(CHG_CMD_PIN, 0x04, 0x08)
        -- 通信结束后恢复空闲高电平
        gpio.setup(CHG_CMD_PIN, 1)
        if result then
            return "OK"
        else
            log.error("CHG_TEST", "读取yhm2712a芯片ID失败", result, chipid)
            return "ERROR"
        end
    end,
    ["WD_TEST"] = function(id, findCom, data)
        -- WD_TEST#:   触发看门狗强制复位（设备约1s内重启，上位机检测重启即PASS）
        -- WD_TEST,1#: 手动喂一次狗（恢复/维持喂狗）
        if not exair153x_wdt then return "ERROR" end
        if data == "" then
            exair153x_wdt.trigger_reset()
            return "OK"
        end
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        if onoff == 1 then exair153x_wdt.feed() end
        -- 新版库自动喂狗任务常驻，0 仅回包兼容上位机流程，不停止自动喂狗
        return "OK"
    end,
    ["ECNPICFG"] = function(id, findCom, data)
        -- RF 校准标志位：异步任务处理
        sys.publish("CONTROL", "ECNPICFG", id)
        return
    end,
    ["VBAT"] = function(id, findCom, data)
        -- 电池电压：读模组内部 VBAT 通道，返回值按 %.2f 输出
        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        if not vbat then
            return "ERROR"
        end
        log.info("vbat", vbat)
        return string.format("%.2f", vbat)
    end,
    ["FLYMODE"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        log.info("FLYMODE", onoff)
        if onoff == 1 then
            blueLed(0)
            redLed(0)
            gpio.setup(LSENSE_POWER_PIN, 0)
            gpio.setup(GNSS_POWER_PIN, 0)
            -- 注意：GPIO23(SIM上拉/Vref/G-Sensor供电)保持常开，GPIO25(充电总线)保持空闲高，看门狗持续喂狗
        end
        mobile.flymode(0, onoff == 1)
        return "OK"
    end,
    ["HVERSION"] = function(id, findCom, data)
        if not findCom then
            -- 查询硬件版本：读 OTP 的 PCB；未写返回 ERROR
            local pcb = prodmeta.get("PCB")
            return pcb or "ERROR"
        end
        -- 写硬件版本：写入 OTP 的 PCB key
        local ver = data:gsub("^%s*", ""):gsub("%s*$", "")
        if #ver == 0 then
            return "ERROR"
        end
        local ok, err = prodmeta.set("PCB", ver)
        if not ok then
            log.error("factory", "写PCB失败", err)
            return "ERROR"
        end
        log.info("factory", "硬件版本写入", ver)
        return "OK"
    end,
    ["MODEL"] = function(id, findCom, data)
        -- 写工业模组型号到 OTP PROD；硬件版本由 HVERSION,版本# 单独写 PCB
        log.info("factory", "MODEL 收到:", data, "findCom:", findCom)
        if not data or #data == 0 then
            return "ERROR"
        end
        local model = data:gsub("^%s*", ""):gsub("%s*$", "")
        if #model == 0 then
            return "ERROR"
        end
        local ok, err = prodmeta.set("PROD", model)
        if not ok then
            log.error("factory", "写PROD失败", err)
            return "ERROR"
        end
        log.info("factory", "写号成功", model)
        return "OK"
    end,
    ["MODEL?"] = function(id, findCom, data)
        -- 读回当前工业型号（OTP 的 PROD key）
        local v = prodmeta.get("PROD")
        return v or "ERROR"
    end,
    ["META?"] = function(id, findCom, data)
        -- 诊断：读 OTP 全部 key=value 内容（定位写号失败）
        local all = prodmeta.get_all()
        local parts = {}
        for k, v in pairs(all or {}) do
            table.insert(parts, k .. "=" .. v)
        end
        table.sort(parts)
        local s = table.concat(parts, ",")
        log.info("factory", "META? 内容:", s, "长度:", #s)
        if #s == 0 then
            return "EMPTY"
        end
        return s
    end,
    ["RST"] = function(id, findCom, data)
        -- 单独重启（RST#）：不写任何标记，500ms 延时确保 OK# 发出
        log.info("factory", "重启设备")
        sys.taskInit(function()
            sys.wait(500)
            pm.reboot()
        end)
        return "OK"
    end,
    ["TEST_DONE"] = function(id, findCom, data)
        log.info("factory", "TEST_DONE 开始，清理外设")
        -- 关 GNSS
        if gnssTransFlag then
            gnssTransFlag = false
            if ok_exgnss then pcall(exgnss.close_all) end
            pcall(uart.on, gnssUartId, "receive")
            pcall(uart.close, gnssUartId)
            log.info("factory", "TEST_DONE 已关 GPS")
        end
        -- 外设电源/io
        blueLed(0)
        redLed(0)
        pcall(gpio.setup, LSENSE_POWER_PIN, 0)
        pcall(gpio.setup, GNSS_POWER_PIN, 0)
        pcall(gpio.setup, CHG_CMD_PIN, 1)
        -- i2c
        pcall(i2c.close, GSENSOR_I2C_ID)
        log.info("factory", "TEST_DONE 外设清理完成")

        -- V3 收尾：返工删 fskv 标记（不动 OTP1）；首测校验 OTP1 已写号
        local function finish_and_reboot()
            if isRetest then
                local ok, err = retest.clear_flag()
                if not ok then
                    log.error("factory", "返工标记删除失败，不重启:", err)
                    return false
                end
                log.info("测试完成（返工），返工标记已删除，3秒后重启进正常模式")
            else
                -- 首次产测：型号/硬件版本已由 MODEL/HVERSION 写入 OTP1，此处校验非空
                local all = prodmeta.get_all()
                if type(all) ~= "table" or next(all) == nil then
                    log.error("factory", "OTP1 为空，未写号，禁止结束首测")
                    return false
                end
                -- 删除首测中途保护标记 model_firsttest（带读回校验，失败不重启，防重启后仍回产测）
                local fok, ferr = retest.first_clear()
                if not fok then
                    log.error("factory", "首测标记删除失败，不重启:", ferr)
                    return false
                end
                log.info("测试完成（首测），OTP1 写号已就绪，首测标记已删除，3秒后重启进正常模式")
            end
            if pm and pm.reboot then
                sys.timerStart(pm.reboot, 3000)
            else
                log.error("factory", "固件不支持 pm.reboot，请手动重启")
                return false
            end
            return true
        end

        if finish_and_reboot() then
            return "OK"
        end
        return "ERROR"
    end,
    ["PCBA_TEST_DONE"] = function(id, findCom, data)
        if not (pm and pm.shutdown) then
            log.error("factory", "固件不支持 pm.shutdown")
            return "ERROR"
        end
        sys.timerStart(pm.shutdown, 3000)
        return "OK"
    end,
}

-- ============================================================
-- 指令解析
-- ============================================================
local function proc(id, data)
    local h1, h2, cmd, findCom, text = nil, nil, nil, false, ""
    h1 = data:find("#")
    if not h1 then
        return false, data
    end
    text = data:sub(1, h1)
    h2 = string.find(text, ",")
    if h2 then
        cmd = string.sub(text, 1, h2 - 1)
        findCom = true
    else
        cmd = string.sub(text, 1, -2) -- 移除末尾的 #
    end
    -- 移除命令前后的空白字符（包括换行符、空格等）
    cmd = string.gsub(cmd, "^%s*", "")
    cmd = string.gsub(cmd, "%s*$", "")
    cmd = string.upper(cmd)
    log.info("cmd:", cmd, "text:", text)
    if procTable[cmd] then
        local reply = procTable[cmd](id, findCom, findCom and text:sub(h2 + 1, -2) or "")
        if reply then
            send_response(id, reply .. "#")
        end
    else
        send_response(id, "ERROR#")
    end
    return true, data:sub(h1 + 1)
end

-- ============================================================
-- V3 返工指令帧提取（命令内部含额外 #，会破坏 proc 解析，必须在 proc 前拦截）
-- 工厂工具帧以 # 结尾，只在收到完整帧（含尾 #）时提取，避免半截帧误判
-- @return string|nil frame, string|nil rest 命中返回帧文本与剩余缓存
-- ============================================================
local function extract_retest(cache)
    -- 查询帧：MODEL_RETEST?#
    local s, e = cache:find("^%s*MODEL_RETEST%?#")
    if s then
        return cache:sub(s, e), cache:sub(e + 1)
    end
    -- 设置帧：MODEL_RETEST#<参数>#（参数不含 #）
    s, e = cache:find("^%s*MODEL_RETEST#[^#]*#")
    if s then
        return cache:sub(s, e), cache:sub(e + 1)
    end
    return nil
end

-- ============================================================
-- 串口收发（USB 虚拟串口 VUART_0）
-- ============================================================
uart.setup(usbTrans, 115200)

uart.on(usbTrans, "receive", function(id, len)
    local result
    while 1 do
        local data = uart.read(usbTrans, 512)
        if not data or #data == 0 then
            break
        end
        usbRxCache = usbRxCache .. data
        -- V3：先拦截返工指令（首测/返工模式下均可响应，用于重新置位返工标记）
        while true do
            local frame, rest = extract_retest(usbRxCache)
            if not frame then break end
            usbRxCache = rest
            local reply = retest.on_data(frame)
            send_response(usbTrans, (reply or "ERROR") .. "#")
        end
        while true do
            result, usbRxCache = proc(usbTrans, usbRxCache)
            if not result then
                break
            end
        end
    end
end)

uart.on(usbTrans, "sent", function(id)
    sys.publish("USB_SENT_DONE")
end)

sys.taskInit(function()
    while true do
        if #cacheTable > 0 then
            local data = table.remove(cacheTable, 1)
            if data.transId == usbTrans then
                uart.write(usbTrans, data.data)
                sys.waitUntil("USB_SENT_DONE")
            end
        else
            sys.waitUntil("DATA_SEND")
        end
    end
end)

return factory
