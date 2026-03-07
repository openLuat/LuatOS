
local airpower = {}                                            
--[[定义一个名为airpower的表,引入三个模块：
dnsproxy（DNS代理）、dhcpsrv（DHCP服务）
和httpplus（HTTP增强）。]] 
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")


local run_state = false  --[[定义一个名为run_state的变量，用于控制UI演示的运行状态，初始为false.
                             用于后续判断本UI DEMO 是否运行，如果运行，则不启动其他UI DEMO]]

local gpio_pin = 152--[[定义GPIO引脚号为152，用于与充电芯片通信]]
-- gpio.setup(gpio_pin, 1, gpio.PULLUP)

local sensor_addr = 0x04-- yhm2712芯片地址，默认为0x04,各位可自行上网查找该型号的设计手册。
-- 电压控制寄存器地址
local V_ctrl_register = 0x00
-- 电流控制寄存器地址
local I_ctrl_register = 0x01
-- 模式寄存器地址
local mode_register = 0x02
-- 配置寄存器，默认为0x00
local config_register = 0x03
-------------------注意：0x04寄存器无含义
-- 状态寄存器
local status1_register = 0x05 -- 只读
local status2_register = 0x06 -- 只读
local status3_register = 0x07 -- 只读
-- id寄存器
local id_register = 0x08 -- 只读
-- 充电电压常用参数,默认门限电压为4.35V
local set_4V = 0xE0 -- 4V
local set_4V1 = 0xF0 -- 4.1V
local set_4V2 = 0x00 -- 4.2V
local set_4V225 = 0x10 -- 4.225V
local set_4V25 = 0x20 -- 4.25V
local set_4V275 = 0x30 -- 4.275V
local set_4V3 = 0x40 -- 4.3V
local set_4V325 = 0x50 -- 4.325V
local set_4V35 = 0x60 -- 4.35V
local set_4V375 = 0x70 -- 4.375V
local set_4V4 = 0x80 -- 4.4V
local set_4V425 = 0x90 -- 4.425V
local set_4V45 = 0xA0 -- 4.45V
local set_4V475 = 0xB0 -- 4.475V
local set_4V5 = 0xC0 -- 4.5V
local set_4V525 = 0xD0 -- 4.525V

-- 充电电流常用参数，默认充电电流为250mA，即0.5倍*500=250mA
local set_0I2 = 0x22 -- 0.2倍，0.2*500=100mA
local set_0I5 = 0x02 -- 0.5倍，0.5*500=250mA
local set_0I7 = 0x42 -- 0.7倍，0.7*500=350mA
local set_0I9 = 0x62 -- 0.9倍，0.9*500=450mA
local set_I = 0x82 --  1倍，1.0*500=500mA
local set_1I5 = 0xA2 -- 1.5倍，1.5*500=750mA
local set_2I = 0xC2 --  2倍，2.0*500=1000mA
local set_3I = 0xE2 --  3倍，3.0*500=1500mA

local V_table = {                      --[[将电压设置表：（寄存器写入值）映射为可读的电压字符串。
                                            即224对应0xE0，即set_4V的值，表示4V。]]
    ["224"] = "4.0V",
    ["240"] = "4.1V",
    ["0"] = "4.2V",
    ["16"] = "4.225V",
    ["32"] = "4.25V",
    ["48"] = "4.275V",
    ["64"] = "4.3V",
    ["80"] = "4.325V",

    ["96"] = "4.35V",                  --[[是我们air8000的​门限电压:指的是充电过程控制的关键阈值电压，具体来说：
                                           充电控制器预设的电池最高允许充电电压是充电模式切换的关键判定值]]

    ["112"] = "4.375V",
    ["128"] = "4.4V",
    ["144"] = "4.425V",
    ["160"] = "4.45V",
    ["176"] = "4.475V",
    ["192"] = "4.5V",
    ["208"] = "4.525V"
}

local I_table={                        --电流设置值（十六进制 -> 电流值）
    ["1"] = "100mA",
    ["0"] = "250mA",
    ["2"] = "350mA",
    ["3"] = "450mA",
    ["4"] = "500mA",
    ["5"] = "750mA",
    ["6"] = "1000mA",
    ["7"] = "1500mA",                  --注意，这里是 yhm2712芯片最大可支持1500mA，请严格遵循各物料的规格书
    }

local charge_status_table = {          --[[在充电芯片（yhm2712）的状态寄存器（status1_register，地址0x05）中，
                                           有一个字段表示当前的充电状态。根据之前的代码，这个状态字段位于该寄存
                                           器的最高3位（bit7、bit6、bit5）。因此，通过读取寄存器0x05的值，然后
                                           将其与0xE0（二进制11100000）进行按位与操作，再右移5位，就可以得到一
                                           个0到7之间的整数，这个整数就代表当前充电状态。]]
    ["0"] = "放电模式",
    ["1"] = "预充电模式",
    ["2"] = "涓流充电",
    ["3"] = "恒流快速充电",
    ["4"] = "恒压快速充电",
    ["5"] = "恒压快速充电",
    ["6"] = "恒压快速充电",
    ["7"] = "充电完成"
}



-- 定义系统状态变量表，用于存储后续我们所需的系统状态信息
local system_state = {
    usb_connected = false, -- USB连接状态，初始状态为未连接
    battery_voltage = 0.0, -- 电池电压
    charge_status = "未知状态", -- 充电状态
    last_update = 0 -- 最后更新时间
}

local vbus_pin = gpio.WAKEUP1   --[[测试USB是否连接，就要测试VBUS脚是否有电，我们后续要用gpio中断来确认是否连接，
                                    而VBUS脚是gpio.WAKEUP1，所以这里我们定义vbus_pin为gpio.WAKEUP1]]

-- ：充电芯片初始化任务
local function yhm27xxx()
    sys.wait(1000)
    local result, data = yhm27xx.cmd(gpio_pin, sensor_addr, id_register)-- 读取芯片ID
    sys.wait(200)
    log.info("result", result, "data", data)
  
    result, data = sensor.yhm27xx(gpio_pin, sensor_addr, V_ctrl_register, set_4V35)-- 设置充电电压(4.35V)
    if result == true then
        log.info("yhm27xxx 设置电压成功")
    else
        log.info("yhm27xxx 设置电压失败")
    end
    sys.wait(200)

   
    result, data = yhm27xx.cmd(gpio_pin, sensor_addr, I_ctrl_register, set_I)-- 设置充电电流1倍(500mA)
    if result == true then
        log.info("yhm27xxx 设置电流成功")
    else
        log.info("yhm27xxx 设置电流失败")
    end

    log.info("读寄存器的值...")
    sys.wait(200)
    yhm27xx.reqinfo(gpio_pin, sensor_addr)
    local result, data = sys.waitUntil("YHM27XX_REG", 200)
    -- log.info("result",result,"data", data)
    local Data_reg = {}

    if result then
        for i = 1, 9 do
            Data_reg[i] = data:byte(i)
        end
        log.info("yhm27xxx 寄存器0x05 功能:充电状态寄存器(只读),读取数据为：",
            charge_status_table[tostring((Data_reg[6] & 0xE0) >> 5)])
    end
    log.info("yhm27xxx 寄存器0x00 功能:设置充电电压，   读取数据为：", V_table[tostring(Data_reg[1])])
    log.info("yhm27xxx 寄存器0x01 功能:设置充电电流， 读取数据为：", I_table[tostring((Data_reg[2] & 0xE0)>>5)])
    log.info("yhm27xxx 寄存器0x05 功能:充电状态寄存器(只读),读取数据为：",charge_status_table[tostring((Data_reg[6] & 0xE0) >> 5)])
end
local adc_pin = adc.CH_VBAT -- adc.CH_VBAT

-- 新增：电池状态监控任务
function battery_voltage()
    -- 初始化ADC0（管脚75） 
    adc.open(adc_pin)
    -- 获取ADC通道的值
    local vbat = adc.get(adc_pin)
    -- 打印ADC通道的值
    log.info("vbat", vbat)
    while true do
        -- 1. 读取电池电压
        local raw_value = adc.read(adc_pin) -- 读取ADC值
        -- 计算电池电压
        system_state.battery_voltage = (raw_value * 4) / 4096
        -- 打印原始值
        log.info("raw_value", raw_value)
        -- 打印电池电压
        log.info("battery_voltage", system_state.battery_voltage)
        sys.wait(3000) -- 每秒更新一次
         if not run_state then -- 等待结束，返回主界面
                return 
            end
    end
end

local function usb_connected()                          -- 2. 新增检测USB状态,测VBUS脚（即gpio.WAKEUP1）
    gpio.setup(vbus_pin, function(val)                  -- 判断VBUS脚是否有返回值
        log.info("USB状态变化", val == 1 and "插入" or "拔出")
        system_state.usb_connected = (val == 1)
    end, gpio.PULLUP, gpio.BOTH)                        -- 关键：上拉电阻+双沿触发
    gpio.debounce(vbus_pin, 500, 1)                     -- 添加消抖处理（500ms）

    system_state.usb_connected = (gpio.get(vbus_pin) == 1) -- 初始状态读取
    log.info("USB初始状态", system_state.usb_connected and "已连接" or "未连接")

end

local function charge_status()                 -- 3. 读取充电状态
    while true do
       
                                              -- 向传感器发送请求，获取传感器地址
        log.info("yhm27xx teeee", gpio_pin, sensor_addr)
        yhm27xx.reqinfo(gpio_pin, sensor_addr)
                                              -- 等待传感器返回数据，超时时间为3000毫秒
        local result, data = sys.waitUntil("YHM27XX_REG", 3000)
        -- 打印返回结果和返回数据
        -- log.info("result", result, "data", data)

        -- 如果result为真，则执行以下代码
        if result then
                                -- 定义一个空表Data_reg
            local Data_reg = {}
                                -- 循环读取data的前9个字节，并存储到Data_reg表中
            for i = 1, 9 do
                Data_reg[i] = data:byte(i)
            end
            -- 解析充电状态
            -- 从Data_reg表的第6个字节中取出高5位，右移5位，得到status_code
            local status_code = (Data_reg[6] & 0xE0) >> 5
            -- 将status_code转换为字符串，并从charge_status_table表中查找对应的充电状态，如果找不到，则默认为"未知状态"
            system_state.charge_status = charge_status_table[tostring(status_code)] or "未知状态"
            -- 打印充电状态
            log.info("充电状态", system_state.charge_status)
        end

        -- 4. 更新最后读取时间
        system_state.last_update = os.time()
            if not run_state then -- 等待结束，返回主界面
                return 
            end
        sys.wait(3000) -- 每秒更新
    end
end
-- 以下为UI运行函数（添加电池信息显示）
-- 电源管理测试函数
-- 电源管理测试函数
function airpower.run()
   
    -- 初始化电池电压
    sys.taskInit(battery_voltage)
    -- 初始化yhm27xxx
    sys.taskInit(yhm27xxx)
    sys.taskInit(charge_status)
    sys.taskInit(usb_connected)
   
        log.info("airpower.run")
        lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
        run_state = true
        -- 新增：电池信息显示
        while true do
        sys.wait(10)
        -- airlink.statistics()
        lcd.clear(_G.bkcolor)

        lcd.drawStr(0, 80, "电源管理测试")

        -- 新增电池信息显示 --
        -- USB状态
        lcd.drawStr(0, 120, "USB: " .. (system_state.usb_connected and "已连接" or "未连接"))

        -- 电池电压
        lcd.drawStr(0, 160, string.format("电压: %.2fV", system_state.battery_voltage))

        -- 充电状态
        lcd.drawStr(0, 200, "状态: " .. system_state.charge_status)

        lcd.showImage(100, 360, "/luadb/back.jpg")
        lcd.showImage(0, 448, "/luadb/Lbottom.jpg")
        lcd.flush()

            if not run_state then -- 等待结束，返回主界面
                gpio.setup(vbus_pin, nil)
                return true
            end
        end

end

-- 触摸屏事件处理函数
function airpower.tp_handal(x, y, event)
    if x > 100 and x < 180 and y > 360 and y < 440 then -- 返回主界面
        run_state = false
    end
end

return airpower
