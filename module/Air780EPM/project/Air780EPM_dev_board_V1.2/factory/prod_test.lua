--[[
@module  prod_test
@summary Air780EPM V1.2 开发板产测程序（V3 出厂流程）
@version 1.0.0
@date    2026.10.19
@usage
进入本模式的条件（见 main.lua）：
  1. fskv 中存在 retest_flag（返工产测）
  2. OTP1 为空（首次产测）

产测通道：USB 虚拟串口 uart.VUART_0，115200 8N1
协议：命令# / 命令,数据#，成功回 OK#，失败回 ERROR#，查询类命令回 值#

指令表：
  VERSION                 查询固件版本 → PROJECT_VERSION#
  IMEI / IMSI / ICCID     查询模组信息
  CSQ                     查询信号强度
  MUID                    查询模组唯一 ID
  VBAT                    查询电池电压（mV）
  ECNPICFG                查询射频校准标志 → true#/false#
  LED,0|1                 LED（GPIO27）熄灭/点亮
  MODEL,型号#             写入 OTP1 的 PROD（工业型号），写后读回校验
  MODEL?                  读回 PROD
  HVERSION,版本#          写入 OTP1 的 PCB（硬件版本），写后读回校验
  HVERSION                读回 PCB
  MODEL_RETEST,CONFIRM#   写入返工标记并重启，进入产测模式
  MODEL_RETEST?           查询返工标记 → true#/false#
  RST                     重启设备
  TEST_DONE               产测完成：删除返工标记，3 秒后重启进入正常模式

485 独立测试（不走 USB）：
  上电后 485 常开（GPIO1 供电、GPIO23 vref、GPIO25 方向），PC 通过 USB 转 485
  发 U485_TEST，设备回 485TEST\r\n。
]]

local prodmeta = require("prodmeta")

log.info("prod_test", "进入产测模式", PROJECT, VERSION)

-- ==================== 板载外设引脚 ====================
local LED_PIN = 27              -- LED，高电平点亮
local U485_POWER_PIN = 1        -- RS485 芯片供电
local U485_VREF_PIN = 23        -- RS485 vref 拉高
local U485_DIR_PIN = 25         -- RS485 方向控制（0=接收，1=发送）
local U485_UART_ID = 1          -- RS485 使用 UART1，9600 8N1

local usbTrans = uart.VUART_0

-- ==================== 初始化外设 ====================
gpio.setup(LED_PIN, 0)          -- LED 默认熄灭
gpio.setup(U485_POWER_PIN, 1)   -- 485 供电常开
gpio.setup(U485_VREF_PIN, 1)    -- vref 拉高
gpio.setup(U485_DIR_PIN, 0)     -- 默认接收方向

-- ==================== 发送队列 ====================
local usbRxCache = ""
local cacheTable = {}

-- 异步结果回复：带 # 存入发送队列
local function send_response(transId, data)
    table.insert(cacheTable, { transId = transId, data = data })
    sys.publish("DATA_SEND")
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s*", ""):gsub("%s*$", ""))
end

-- ==================== 异步控制任务 ====================
-- 以下操作不能在 uart 接收回调里直接执行：
--   * mobile.flymode 是同步阻塞的 RPC 调用，在回调里调用会导致回调退不出、整机卡死
--   * prodmeta.set 内部会进入飞行模式并擦写 OTP，耗时较长
sys.taskInit(function()
    while true do
        local _, action, id, data = sys.waitUntil("CONTROL")
        if action == "MODEL" then
            local ok, err = prodmeta.set("PROD", data)
            if not ok then
                log.error("prod_test", "写入 PROD 失败", err)
            end
            if ok and prodmeta.get("PROD") == data then
                log.info("prod_test", "写入 PROD 成功", data)
                send_response(id, "OK#")
            else
                send_response(id, "ERROR#")
            end
        elseif action == "HVERSION" then
            local ok, err = prodmeta.set("PCB", data)
            if not ok then
                log.error("prod_test", "写入 PCB 失败", err)
            end
            if ok and prodmeta.get("PCB") == data then
                log.info("prod_test", "写入 PCB 成功", data)
                send_response(id, "OK#")
            else
                send_response(id, "ERROR#")
            end
        end
    end
end)

-- ==================== 485 常驻测试 ====================
-- PC 通过 USB 转 485 发 U485_TEST，设备切发送方向回 485TEST\r\n
sys.taskInit(function()
    sys.wait(50)                    -- 等 485 供电稳定
    uart.setup(U485_UART_ID, 9600)
    gpio.setup(U485_DIR_PIN, 0)     -- 接收方向

    -- 不能在 uart 回调里 sys.wait，匹配到测试指令后只发事件
    local rxBuf = ""
    uart.on(U485_UART_ID, "receive", function(id, len)
        local data = uart.read(U485_UART_ID, 128)
        if data and #data > 0 then
            rxBuf = rxBuf .. data
            if string.find(rxBuf, "U485_TEST", 1, true) then
                rxBuf = ""          -- 清空，避免重复触发
                sys.publish("U485_RECV")
            end
        end
    end)

    while true do
        sys.waitUntil("U485_RECV")
        gpio.setup(U485_DIR_PIN, 1)     -- 发送方向
        sys.wait(10)                    -- 等 DE 稳定
        uart.write(U485_UART_ID, "485TEST\r\n")
        sys.wait(20)                    -- 等本地 TX 发完（9 字节 @9600 约 10ms）
        gpio.setup(U485_DIR_PIN, 0)     -- 切回接收
    end
end)

-- ==================== 指令表 ====================
local procTable = {
    ["VERSION"] = function(id, findCom, data)
        return PROJECT .. "_" .. VERSION
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
    ["VBAT"] = function(id, findCom, data)
        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        if not vbat then return "ERROR" end
        log.info("prod_test", "vbat(mV)", vbat)
        return string.format("%.2f", vbat)
    end,
    ["ECNPICFG"] = function(id, findCom, data)
        -- 该接口受 LUAT_USE_MOBILE_ECNPICFG 宏控制，固件未开启时是 nil
        if type(mobile.ecnpicfg) ~= "function" then
            log.error("prod_test", "固件未开启 LUAT_USE_MOBILE_ECNPICFG 宏")
            return "ERROR"
        end
        local passed = mobile.ecnpicfg()
        log.info("prod_test", "ecnpicfg", passed)
        if passed == true then return "true" end
        if passed == false then return "false" end
        return "ERROR"
    end,
    ["LED"] = function(id, findCom, data)
        local onoff = tonumber(trim(data))
        if not onoff or (onoff ~= 0 and onoff ~= 1) then return "ERROR" end
        gpio.set(LED_PIN, onoff)
        return "OK"
    end,
    ["MODEL"] = function(id, findCom, data)
        -- 写入工业型号到 OTP1 的 PROD
        if not findCom then return "ERROR" end
        local model = trim(data)
        if #model == 0 or model:find("[,=]") then return "ERROR" end
        -- OTP 擦写耗时且需飞行模式，交给 CONTROL 协程执行
        sys.publish("CONTROL", "MODEL", id, model)
    end,
    ["MODEL?"] = function(id, findCom, data)
        local v = prodmeta.get("PROD")
        return v or "ERROR"
    end,
    ["HVERSION"] = function(id, findCom, data)
        -- 无参数：读回 PCB；带参数：写入 PCB
        if not findCom then
            local v = prodmeta.get("PCB")
            return v or "ERROR"
        end
        local ver = trim(data)
        if #ver == 0 or ver:find("[,=]") then return "ERROR" end
        sys.publish("CONTROL", "HVERSION", id, ver)
    end,
    ["MODEL_RETEST"] = function(id, findCom, data)
        -- V3 返工指令：MODEL_RETEST,CONFIRM# 写返工标记并重启
        if not findCom then
            log.error("prod_test", "MODEL_RETEST 缺少魔法字")
            return "ERROR"
        end
        local magic = trim(data)
        if magic ~= "CONFIRM" then
            log.error("prod_test", "MODEL_RETEST 魔法字错误:", magic)
            return "ERROR"
        end
        fskv.set("retest_flag", true)
        log.info("prod_test", "写入返工标记，重启进入返工产测")
        sys.timerStart(pm.reboot, 500)
        return "OK"
    end,
    ["MODEL_RETEST?"] = function(id, findCom, data)
        return fskv.get("retest_flag") and "true" or "false"
    end,
    ["RST"] = function(id, findCom, data)
        log.info("prod_test", "重启设备")
        sys.timerStart(pm.reboot, 500)
        return "OK"
    end,
    ["TEST_DONE"] = function(id, findCom, data)
        if fskv.get("retest_flag") then
            fskv.del("retest_flag")
            log.info("prod_test", "返工产测完成，删除返工标记，3 秒后重启")
        else
            log.info("prod_test", "首次产测完成，3 秒后重启进入正常模式")
        end
        sys.timerStart(pm.reboot, 3000)
        return "OK"
    end,
}

-- ==================== 指令解析 ====================
local function proc(id, data)
    local h1 = data:find("#")
    if not h1 then
        return false, data
    end
    -- text 含结尾的 #
    local text = data:sub(1, h1)
    local h2 = text:find(",")
    local cmd, findCom
    if h2 then
        cmd = text:sub(1, h2 - 1)
        findCom = true
    else
        cmd = text:sub(1, -2)
    end
    cmd = trim(cmd):upper()
    log.info("prod_test", "cmd:", cmd, "text:", text)

    if procTable[cmd] then
        local reply = procTable[cmd](id, findCom, findCom and text:sub(h2 + 1, -2) or "")
        if reply then
            table.insert(cacheTable, { transId = id, data = reply .. "#" })
            sys.publish("DATA_SEND")
        end
    else
        table.insert(cacheTable, { transId = id, data = "ERROR#" })
        sys.publish("DATA_SEND")
    end
    return true, data:sub(h1 + 1)
end

-- ==================== USB 虚拟串口接收 ====================
uart.setup(usbTrans, 115200)

uart.on(usbTrans, "receive", function(id, len)
    while true do
        local data = uart.read(usbTrans, 512)
        if not data or #data == 0 then break end
        usbRxCache = usbRxCache .. data
    end
    while true do
        local result
        result, usbRxCache = proc(usbTrans, usbRxCache)
        if not result then break end
    end
end)

-- ==================== USB 虚拟串口发送 ====================
uart.on(usbTrans, "sent", function(id)
    sys.publish("USB_SENT_DONE")
end)

sys.taskInit(function()
    while true do
        if #cacheTable > 0 then
            local item = table.remove(cacheTable, 1)
            uart.write(item.transId, item.data)
            -- 等发送完成；超时兜底，避免 sent 事件丢失后发送任务永久卡死
            sys.waitUntil("USB_SENT_DONE", 1000)
        else
            sys.waitUntil("DATA_SEND")
        end
    end
end)
