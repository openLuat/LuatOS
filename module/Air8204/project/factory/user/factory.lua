--[[
@module  factory
@summary Air8204 产测功能模块（产测 + 出货合一中的产测模式）
@version 1.0
@date    2026.09.28
@usage
由 boot.lua 在「未完成产测」时 require（或 BOOT_MODE=factory 强制调试时）。
Air8204 是智能录音工牌（主控 Air780EGH），出货模式是 card_main（air_card 录音定位应用）。外设：
  - WS2812 状态灯 ×2（GPIO27/28）+ RGB 灯 R 路（GPIO25，高电平亮；G/B 由充电芯片控制不测）
  - ES7243E 录音 ADC（供电 GPIO32；I2C1 器件 0x10；I2S0 音频数据）
  - TF 卡（SPI0，CS=GPIO8 软件 CS，使能 GPIO1）
  - DA221 加速度传感器（I2C0 器件 0x27，使能 GPIO20，芯片ID 0x13）
  - 内置 GNSS（Air780EGH，exgnss 库，UART2 默认）
  - 录音模式开关 GPIO22（输入，低=录音）+ VREF GPIO23（开机拉高，见 boot.lua）
  - 电池电压 adc.CH_VBAT（读 mV）
产测指令：基础信息 + LED + RECORD(ES7243E) + SD_TEST + GS_STATE + GPSTEST + 校准位(ECNPICFG)
+ 飞行模式(FLYMODE) + 写号(MODEL/HVERSION/MODEL?) + 系统控制(RST/TEST_DONE/PCBA_TEST_DONE)。
写号使用 prodmeta 库写入 OTP（key: PROD=工业型号, PCB=硬件版本）；校准位用 mobile.ecnpicfg() 只读。
RECORD/SD_TEST 含 sys.wait，走 CONTROL 事件模式异步执行。
]]

local factory = {}

log.info("测试模式", "启动中")

local prodmeta = require "prodmeta"
local exgnss = require "exgnss"

-- ================= 硬编码管脚定义（主控 Air780EGH） =================
local LED1_PIN = 27        -- LED1 状态灯（WS2812）
local LED2_PIN = 28        -- LED2 录音灯（WS2812）
local RGB_R_PIN = 25       -- RGB 灯 R 路，高电平亮（G/B 由充电芯片控制，产测不测）

local ES7243E_PWR_PIN = 32 -- ES7243E 供电使能，高=使能（不是复位脚）
local ES7243E_I2C_ID = 1   -- ES7243E 配置总线 I2C1
local ES7243E_ADDR = 0x10  -- ES7243E I2C 器件地址

local REC_SW_PIN = 22      -- 录音模式开关（输入，低=录音；一端 GND 一端 GPIO23/VREF）
local VREF_PIN = 23        -- VREF，开机拉高保持（录音开关高电平源，全原理图仅此作用）

local DA221_I2C_ID = 0     -- DA221 通信总线 I2C0
local DA221_ADDR = 0x27    -- DA221 I2C 器件地址
local DA221_EN_PIN = 20    -- DA221 使能，高=使能
-- DA221 中断脚 WAKEUP0 仅运动检测用，产测只读芯片ID，不用中断

local TF_PWR_PIN = 1       -- TF 卡使能，高=使能
local TF_SPI_ID = 0        -- TF 卡数据总线 SPI0
local TF_CS_PIN = 8        -- TF 卡片选（软件 CS）

-- ================= 初始化变量 =================
local usbTrans = uart.VUART_0
local usbRxCache = ""
local cacheTable = {}

-- ================= WS2812 状态灯 =================
local led1 = ws2812.create(ws2812.GPIO, 1, LED1_PIN)
ws2812.args(led1, 0, 40, 35, 14, 8)
local led2 = ws2812.create(ws2812.GPIO, 1, LED2_PIN)
ws2812.args(led2, 0, 40, 35, 14, 8)

-- RGB 灯 R 路（普通 GPIO，高电平亮），初始关
gpio.setup(RGB_R_PIN, 0)

-- VREF 开机拉高保持；录音开关作为输入（低=录音）
gpio.setup(VREF_PIN, 1)
gpio.setup(REC_SW_PIN, nil)

-- DA221 使能（开机常开，GS_STATE 读芯片ID 时无需再等待上电）
gpio.setup(DA221_EN_PIN, 1)

-- ================= ES7243E 寄存器配置（取自 air_card es7243e.lua） =================
local es7243e_reg = {
    {0x01, 0x3A}, {0x00, 0x80}, {0xF9, 0x00}, {0x04, 0x02}, {0x04, 0x01},
    {0xF9, 0x01}, {0x00, 0x1E}, {0x01, 0x00}, -- radio 256
    {0x03, 0x20}, {0x04, 0x01}, {0x0D, 0}, {0x05, 0x00}, {0x06, 4 - 1},
    {0x07, 0x00}, {0x08, 0xFF}, {0x02, (0x00 << 7) + 0}, {0x09, 0xCA},
    {0x0A, 0x85}, {0x0B, 0xC0 + 0x00 + (0x03 << 2)}, {0x0E, 191}, {0x10, 0x38},
    {0x11, 0x16}, {0x14, 0x0C}, {0x15, 0x0C}, {0x17, 0x02}, {0x18, 0x26},
    {0x0F, 0x80}, {0x19, 0x77}, {0x1F, 0x08 + (0 << 5) - 0x00}, {0x1A, 0xF4},
    {0x1B, 0x66}, {0x1C, 0x44}, {0x1E, 0x00}, {0x20, 0x10 + 14},
    {0x21, 0x10 + 14}, {0x00, 0x80 + (0 << 6)}, {0x01, 0x3A}, {0x16, 0x3F},
    {0x16, 0x00}, {0x0B, 0x00 + (0x03 << 2)}, {0x00, (0x80) + (1 << 6)}
}

-- 发送回复（CONTROL 事件任务里用）
local function send_response(id, data)
    table.insert(cacheTable, { transId = id, data = data })
    sys.publish("DATA_SEND")
end

-- ================= 录音测试（ES7243E，走 CONTROL 异步） =================
-- 验证：GPIO32 供电 + I2C1 通信 + ES7243E 寄存器配置 + I2S0 音频数据流（麦克风/ADC/I2S 全链路）
local function record_test()
    -- 1. ES7243E 供电使能
    gpio.setup(ES7243E_PWR_PIN, 1)
    sys.wait(50)

    -- 2. I2C1 初始化
    if i2c.setup(ES7243E_I2C_ID, i2c.FAST) == nil then
        log.error("RECORD", "I2C 初始化失败")
        gpio.setup(ES7243E_PWR_PIN, 0)
        return "ERROR"
    end

    -- 3. 写 ES7243E 寄存器配置（i2c.send 返回 true=成功，校验 I2C 通信/芯片在位）
    for i, v in ipairs(es7243e_reg) do
        if not i2c.send(ES7243E_I2C_ID, ES7243E_ADDR, v, 1) then
            log.error("RECORD", "ES7243E 寄存器写入失败 index=", i)
            i2c.close(ES7243E_I2C_ID)
            gpio.setup(ES7243E_PWR_PIN, 0)
            return "ERROR"
        end
    end

    -- 4. I2S 初始化 + 接收，回调里标记是否收到音频数据
    local got_data = false
    i2s.setup(0, 1, 8000, 16, 1, i2s.MODE_I2S)
    local rx_buff = zbuff.create(3200)
    i2s.on(0, function(id, buff)
        got_data = true
    end)
    i2s.recv(0, rx_buff, 3200)

    -- 5. 录音 3 秒（采集麦克风数据，期间可让产线操作员对麦克风说话增强验证）
    sys.wait(3000)

    -- 6. 判定：I2S 收到数据 = ES7243E ADC + I2S0 通路正常
    local result
    if got_data then
        log.info("RECORD", "I2S 已收到音频数据，录音链路正常")
        result = "OK"
    else
        log.error("RECORD", "3 秒内未收到 I2S 音频数据")
        result = "ERROR"
    end

    -- 7. 停止录音并释放资源：直接停 I2S + GPIO32 拉低断电停芯片，不再写停止寄存器。
    -- 说明：写 {0x00,0x80} 停止 ES7243E 会在芯片跑起来后 ACK 超时，C 层照样刷
    --       "i2c failed 140:i2c1从机地址10传输超时"（Lua 忽略返回值压不住这条底层日志），
    --       而 GPIO32 断电本身就把芯片停了，所以直接删掉这笔记，不留超时。
    i2s.stop(0)
    i2s.on(0)
    i2c.close(ES7243E_I2C_ID)
    gpio.setup(ES7243E_PWR_PIN, 0)
    return result
end

-- ================= TF 卡测试（走 CONTROL 异步） =================
local function sd_test()
    -- 1. TF 卡使能
    gpio.setup(TF_PWR_PIN, 1)
    sys.wait(50)

    -- 2. SPI 初始化 + 挂载（SPI0 软件 CS，先低速初始化再高速读写，参照 air_card sd_test.lua）
    spi.setup(TF_SPI_ID, nil, 0, 0, TF_CS_PIN, 400 * 1000)
    gpio.setup(TF_CS_PIN, 1)
    fatfs.mount(fatfs.SPI, "/sd", TF_SPI_ID, TF_CS_PIN, 24 * 1000 * 1000)

    -- 3. 写读对比（挂载失败时 io.open 返回 nil，一并判失败）
    local path = "/sd/factory_test.txt"
    local test_data = "Air8204-SDTest-1234567890"
    local f = io.open(path, "w")
    if not f then
        log.error("SD_TEST", "TF 卡挂载/写入失败")
        return "ERROR"
    end
    f:write(test_data)
    f:close()

    local read_data = io.readFile(path)
    local result
    if read_data == test_data then
        log.info("SD_TEST", "TF 卡读写一致")
        result = "OK"
    else
        log.error("SD_TEST", "TF 卡读写不一致")
        result = "ERROR"
    end

    os.remove(path)
    return result
end

local procTable = {
    ["VERSION"] = function(id, findCom, data)
        return PROJECT .. "_" .. VERSION
    end,
    ["LED"] = function(id, findCom, data)
        -- LED 测试：LED,1# 全部点亮（WS2812×2 + RGB 灯 R 路），LED,0# 全部熄灭
        -- 统一打开：LED1 红、LED2 绿、RGB-R 高电平（G/B 由充电芯片控制，不测）
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        if onoff == 1 then
            ws2812.set(led1, 0, 0x300000)
            ws2812.send(led1)
            ws2812.set(led2, 0, 0x003000)
            ws2812.send(led2)
            gpio.setup(RGB_R_PIN, 1)
        else
            ws2812.set(led1, 0, 0x000000)
            ws2812.send(led1)
            ws2812.set(led2, 0, 0x000000)
            ws2812.send(led2)
            gpio.setup(RGB_R_PIN, 0)
        end
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
    ["VBAT"] = function(id, findCom, data)
        -- 电池电压：读模组内部电池电压通道 adc.CH_VBAT，返回 mV，保留2位小数（全产品统一）
        if type(adc.open) ~= "function" then
            log.error("VBAT", "固件不支持 adc")
            return "ERROR"
        end
        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        if not vbat then
            log.error("VBAT", "读取电池电压失败")
            return "ERROR"
        end
        log.info("VBAT", "vbat(mV):", vbat)
        return string.format("%.2f", vbat)
    end,
    ["GS_STATE"] = function(id, findCom, data)
        -- DA221 加速度传感器测试（与 8201G/8201H/8202C/8202G/8203V 统一指令名 GS_STATE）
        -- 软复位后读芯片ID（寄存器0x01，期望0x13）；I2C0 通信，使能脚 GPIO20 开机已拉高
        i2c.setup(DA221_I2C_ID, i2c.SLOW)
        i2c.send(DA221_I2C_ID, DA221_ADDR, {0x00, 0x24}, 1) -- 软件复位
        i2c.send(DA221_I2C_ID, DA221_ADDR, 0x01, 1)         -- 读芯片ID
        local chipid = i2c.recv(DA221_I2C_ID, DA221_ADDR, 1)
        i2c.close(DA221_I2C_ID)
        if chipid and string.byte(chipid) == 0x13 then
            log.info("GS_STATE", "DA221 芯片ID 0x13，正常")
            return "OK"
        else
            log.error("GS_STATE", "读取 DA221 芯片ID 失败", chipid)
            return "ERROR"
        end
    end,
    ["GPSTEST"] = function(id, findCom, data)
        -- GNSS 测试（Air780EGH 内置 GNSS，exgnss 库，UART2 默认，无外部供电脚）
        -- GPSTEST,1#: 打开 GNSS 并把原始 NMEA 透传到 USB 虚拟串口（libgnss.bind 第二参数）
        -- GPSTEST,0#: 关闭 GNSS 并停止透传
        if data == "1" then
            if not libgnss then
                log.error("GPSTEST", "固件未集成 libgnss（内置 GNSS 不可用）")
                return "ERROR"
            end
            -- agps_enable=false：产测不依赖网络下载星历，冷启动仍会输出 NMEA（$GPGSV）
            exgnss.setup({ gnssmode = 1, agps_enable = false, bind = uart.VUART_0 })
            exgnss.open(exgnss.DEFAULT, { tag = "GPSTEST" })
            log.info("GPSTEST", "GNSS 已开启, NMEA 透传到虚拟串口(VUART_0)")
            return "OK"
        elseif data == "0" then
            exgnss.close_all()
            log.info("GPSTEST", "GNSS 已关闭")
            return "OK"
        end
        return "ERROR"
    end,
    ["RECORD"] = function(id, findCom, data)
        -- 录音测试：ES7243E 录音 3 秒，含 sys.wait，走 CONTROL 事件异步处理
        sys.publish("CONTROL", "RECORD", id)
        return
    end,
    ["SD_TEST"] = function(id, findCom, data)
        -- TF 卡测试：写读对比，含 sys.wait，走 CONTROL 事件异步处理
        sys.publish("CONTROL", "SD_TEST", id)
        return
    end,
    ["ECNPICFG"] = function(id, findCom, data)
        -- 检查 RF 校准标志位（同步只读接口）
        -- 注意：该接口在 C 层被 LUAT_USE_MOBILE_ECNPICFG 宏包着，固件没开宏时是 nil，
        --       直接调用会崩 Lua VM，所以先判类型
        if type(mobile.ecnpicfg) ~= "function" then
            log.error("ECNPICFG", "固件未开启 LUAT_USE_MOBILE_ECNPICFG 宏, mobile.ecnpicfg 不可用")
            return "ERROR"
        end
        local passed, status = mobile.ecnpicfg()
        log.info("ECNPICFG", "passed:", passed,
                 "rfCaliDone:", status and status.rfCaliDone,
                 "rfNSTDone:", status and status.rfNSTDone,
                 "rfCTDone:", status and status.rfCTDone)
        if passed == true then
            return "true"
        elseif passed == false then
            return "false"
        end
        return "ERROR"
    end,
    ["FLYMODE"] = function(id, findCom, data)
        -- 飞行模式开关：FLYMODE,1# 开，FLYMODE,0# 关（只操作主 LTE，adapter=0）
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        log.info("FLYMODE", onoff)
        mobile.flymode(0, onoff == 1)
        return "OK"
    end,
    ["HVERSION"] = function(id, findCom, data)
        -- 硬件版本：HVERSION,版本# 写 OTP PCB；HVERSION# 读回（未写返回 ERROR）
        if not findCom then
            local pcb = prodmeta.get("PCB")
            return pcb or "ERROR"
        end
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
        -- 只写工业模组型号到 OTP PROD；硬件版本由 HVERSION,版本# 单独写入 PCB
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
    ["RST"] = function(id, findCom, data)
        -- 单独重启（RST#）：不写 test_done，重启后仍进产测模式（用于验证写号掉电不丢）
        log.info("factory", "重启设备")
        sys.taskInit(function()
            sys.wait(500) -- 留足时间把 OK# 发出去再重启
            pm.reboot()
        end)
        return "OK"
    end,
    ["TEST_DONE"] = function(id, findCom, data)
        -- 测试完成：写 test_done，3 秒后重启（下次开机进"已完成"分支，不再进产测）
        fskv.set("test_done", true)
        log.info("测试完成，已保存状态，3秒后重启")
        sys.timerStart(pm.reboot, 3000)
        return "OK"
    end,
    ["PCBA_TEST_DONE"] = function(id, findCom, data)
        -- 测试完成关机（不写 test_done，仅下板用；出货请用 TEST_DONE#）
        log.info("PCBA 测试完成，3秒后关机")
        sys.timerStart(pm.shutdown, 3000)
        return "OK"
    end,
}

-- ================= CONTROL 事件任务（异步测试：RECORD / SD_TEST） =================
sys.taskInit(function()
    while true do
        local result, param1, param2 = sys.waitUntil("CONTROL")
        log.info("CONTROL", param1)
        if param1 == "RECORD" then
            send_response(param2, record_test() .. "#")
        elseif param1 == "SD_TEST" then
            send_response(param2, sd_test() .. "#")
        end
    end
end)

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

uart.setup(usbTrans, 115200)

uart.on(usbTrans, "receive", function(id, len)
    local result
    while 1 do
        local data = uart.read(usbTrans, 512)
        if not data or #data == 0 then
            break
        end
        usbRxCache = usbRxCache .. data
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
