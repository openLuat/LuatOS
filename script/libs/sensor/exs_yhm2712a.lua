--[[
@module exs_yhm2712a
@summary exs_yhm2712a扩展库
@version 1.1
@date    2026.07.20
@author  王世豪
@usage
-- 应用场景
本扩展库适用于集成了YHM2712A充电IC的设备，使用前需要手动配置YHM2712A的CMD引脚。

-- 用法实例
本扩展库对外提供了以下7个接口：
1）初始化YHM2712A通信引脚并设置参数 exs_yhm2712a.setup(init_cfg)
2）开启充电 exs_yhm2712a.start()
3）关闭充电 exs_yhm2712a.stop()
4）获取充电系统状态信息 exs_yhm2712a.status()
5）注册事件回调函数 exs_yhm2712a.on(func)
6）进入船运模式 exs_yhm2712a.ship_mode()
7）获取库版本信息 exs_yhm2712a.version()

-- 版本更新说明
-- 版本号：202607201900
-- 1、更新时间：2026-07-20 19:00
-- 2、更新内容
--    实现 YHM2712A 充电管理芯片的完整驱动功能
--    提供充电状态查询、事件回调、船运模式等功能
--    新增 exs_yhm2712a.version() 接口，提供库版本查询功能


其中，开启充电 exs_yhm2712a.start() 和 关闭充电 exs_yhm2712a.stop() 默认自动执行，用户可以不用操作；
当碰到某些需要手动关闭或开启充电功能的场景时，大家可以自行控制，当前仅为预留；

以下为exs_yhm2712a扩展库函数的详细说明及代码实现：

1、开启充电
必须在task中运行，最大阻塞时间大概为700ms, 阻塞主要由sys.waitUntil("YHM27XX_REG", 500)和sys.wait(200)产生。
@api exs_yhm2712a.start()
@return boolean: true=成功, false=失败

2、关闭充电
必须在task中运行，最大阻塞时间大概为700ms, 阻塞主要由sys.waitUntil("YHM27XX_REG", 500)和sys.wait(200)产生。
@api exs_yhm2712a.stop()
@return boolean: true=成功, false=失败

3、初始化YHM2712A充电管理芯片
必须在task中运行,最大阻塞时间大概为700ms, 阻塞主要由sys.waitUntil("YHM27XX_REG", 500)和sys.wait(200)产生。
@api exs_yhm2712a.setup(init_cfg)
@param init_cfg table 初始化配置表
    pin:number, YHM2712A CMD引脚，必选
    v_battery:number, 电池充电截止电压, 取值范围：4200或4350可选, 单位(mV), 必须传入
    cap_battery:number, 电池容量, 取值范围：>= 100, 单位(mAh)，必须传入。
    i_charge:string, 充电电流, 取值范围：exs_yhm2712a.CCMIN(最小电流) 或 exs_yhm2712a.CCDEFAULT(默认电流) 或 exs_yhm2712a.CCMAX(最大电流)，三个可选参数，不传入时默认值为exs_yhm2712a.CCDEFAULT。
@return boolean 成功返回true，失败返回false
@usage
local setup_ok = exs_yhm2712a.setup({
    pin = 25,
    v_battery = 4200,
    cap_battery = 400,
    i_charge = exs_yhm2712a.CCMIN
})
if setup_ok then
    log.info("exs_yhm2712a", "传感器初始化成功")
end

4、获取充电系统状态信息
必须在task中运行，最大阻塞时间(包括超时重试时间)大概为20s。
该函数用于获取当前充电系统的完整状态，包括电池电压、充电阶段、充电状态、电池在位状态、充电器在位状态以及IC过热状态等信息。
其中充电器是否在位，中断触发，触发回调事件为CHARGER_STATE_EVENT，附带的参数 true表示充电器在位，false表示充电器不在位。
@api exs_yhm2712a.status()
@return table 状态信息表
{
    result = boolean,       -- true: 成功, false: 失败
    vbat_voltage = number,  -- 电池电压值（单位：mV），特殊值含义：
                            -- -1: 当前阶段不需要测量
                            -- -2: 电压测量失败
                            -- -3: 仅充电器就绪（无电池）
    charge_stage = number,  -- 当前充电阶段描述，可能值：
                            -- 0 : 放电模式
                            -- 1 : 预充电模式    
                            -- 2 : 涓流充电     
                            -- 3 : 恒流快速充电
                            -- 4 : 预留状态     
                            -- 5 : 恒压快速充电 
                            -- 6 : 预留状态    
                            -- 7 : 充电完成  
                            -- 8 : 未知状态
    charge_complete = boolean, -- true: 充电完成, false: 充电未完成
    battery_present = boolean, -- true: 电池在位, false: 电池不在位
    charger_present = boolean, -- true: 充电器在位, false: 充电器不在位
    ic_overheat = boolean     -- true: 充电IC过热, false: 充电IC未过热
}

5、注册事件回调函数
@api exs_yhm2712a.on(func)
@function: 回调方法，回调时传入参数有exs_yhm2712a.OVERHEAT, exs_yhm2712a.CHARGER_IN, exs_yhm2712a.CHARGER_OUT, exs_yhm2712a.SHIPPING_MODE
@return nil 无返回值
@usage
local function exs_yhm2712a_callback(event)
    if event == exs_yhm2712a.OVERHEAT then
        log.info("警告：设备温度过高！")
    elseif event == exs_yhm2712a.CHARGER_IN then
        log.info("充电器已插入")
    elseif event == exs_yhm2712a.CHARGER_OUT then
        log.info("充电器已拔出")
    elseif event == exs_yhm2712a.SHIPPING_MODE then
        log.info("已进入船运模式")
    end
end
-- 注册回调
exs_yhm2712a.on(exs_yhm2712a_callback)

6、进入船运模式
必须在task中运行，最大阻塞时间大概为2200ms, 阻塞主要由sys.wait(2000)和sys.waitUntil("YHM27XX_REG", 500)产生。
在船运模式下，电池FET断开，设备仅消耗约150nA电流，适用于产品运输和存储。
@api exs_yhm2712a.ship_mode()
@return boolean: true=成功, false=失败
@usage
exs_yhm2712a.ship_mode() -- 进入船运模式

7、获取库版本信息
获取exs_yhm2712a扩展库的版本号，用于版本管理和兼容性检查。
@api exs_yhm2712a.version()
@return string: 库版本号，格式为"年月日"
@usage
log.info("exs_yhm2712a", "version:", exs_yhm2712a.version())
]]
local exs_yhm2712a = {}

-- yhm2712 cmd引脚, 需要用户初始化时配置
local gpio_pin = nil

--yhm2712芯片地址
local sensor_addr = 0x04
--电压控制寄存器地址
local V_ctrl_register = 0x00    -- read/write
--电流控制寄存器地址
local I_ctrl_register = 0x01    -- read/write
--模式寄存器地址
local mode_register = 0x02      -- read/write
--配置寄存器，默认为0x00
local config_register = 0x03    -- read/write
--状态寄存器
local status1_register = 0x05   -- read only
local status2_register = 0x06   -- read only
--id寄存器
local id_register = 0x08        -- read only

--充电电压参数,默认门限电压为4.35V
local set_4V2   = 0x04       --4.2V
local set_4V35  = 0x64       --4.35V
local set_4V    = 0xE4       --4V

--充电电流参数，默认充电电流为175mA，即0.5倍*250=175mA
local set_0I2 = 0x20        --0.2倍，0.2*250=50mA
local set_0I5 = 0x00        --0.5倍，0.5*250=125mA
local set_0I7 = 0x40        --0.7倍，0.7*250=175mA
local set_0I9 = 0x60        --0.9倍，0.9*250=225mA
local set_I = 0x80          --  1倍，1.0*250=250mA
local set_1I5 = 0xA0        --1.5倍，1.5*250=375mA
local set_2I = 0xC0         --  2倍，2.0*250=500mA
local set_3I = 0xE0         --  3倍，3*250=750mA

-- 实际电流值(mA)到十六进制参数的映射
local current_to_register = {
    [50] = set_0I2,
    [125] = set_0I5,
    [175] = set_0I7,
    [225] = set_0I9,
    [250] = set_I,
    [375] = set_1I5,
    [500] = set_2I,
    [750] = set_3I
}

-- 检测USB状态,测VBUS脚（即gpio.WAKEUP1）
local vbus_pin = gpio.WAKEUP1 
-- 是否正在充电
local is_charge = false
-- 是否仅充电器在位
local charger_only = false
-- 电池电压采样值数组
local nochg_t = {}
-- nochg_t 最大长度限制
local AVR_MAX = 10
local callback = nil
-- 充电门限电压设置，默认4.35V
local voltage_setting = set_4V35

-- 充电电流常量
exs_yhm2712a.CCMIN = "MIN"     -- 恒流充电MIN电流模式
exs_yhm2712a.CCMAX = "MAX"    -- 恒流充电MAX电流模式
exs_yhm2712a.CCDEFAULT = "DEFAULT" -- 恒流充电默认电流模式，电流大小处于Min和Max之间
-- 定义事件常量
exs_yhm2712a.OVERHEAT = 1      -- 温度过热事件
exs_yhm2712a.CHARGER_IN = 2    -- 充电器插入事件
exs_yhm2712a.CHARGER_OUT = 3   -- 充电器拔出事件
exs_yhm2712a.SHIPPING_MODE = 4 -- 进入船运模式事件

-- 使用表格存储不同容量和模式下的电流值
local current_table = {
    [100] = {[exs_yhm2712a.CCMIN] = 50, [exs_yhm2712a.CCDEFAULT] = 50, [exs_yhm2712a.CCMAX] = 50},
    [200] = {[exs_yhm2712a.CCMIN] = 50, [exs_yhm2712a.CCDEFAULT] = 125, [exs_yhm2712a.CCMAX] = 125},
    [300] = {[exs_yhm2712a.CCMIN] = 50, [exs_yhm2712a.CCDEFAULT] = 175, [exs_yhm2712a.CCMAX] = 175},
    [400] = {[exs_yhm2712a.CCMIN] = 50, [exs_yhm2712a.CCDEFAULT] = 225, [exs_yhm2712a.CCMAX] = 225},
    [500] = {[exs_yhm2712a.CCMIN] = 50, [exs_yhm2712a.CCDEFAULT] = 250, [exs_yhm2712a.CCMAX] = 250},
    [600] = {[exs_yhm2712a.CCMIN] = 50, [exs_yhm2712a.CCDEFAULT] = 250, [exs_yhm2712a.CCMAX] = 375},
    [700] = {[exs_yhm2712a.CCMIN] = 50, [exs_yhm2712a.CCDEFAULT] = 375, [exs_yhm2712a.CCMAX] = 500},
    [800] = {[exs_yhm2712a.CCMIN] = 50, [exs_yhm2712a.CCDEFAULT] = 375, [exs_yhm2712a.CCMAX] = 500},
    [900] = {[exs_yhm2712a.CCMIN] = 50, [exs_yhm2712a.CCDEFAULT] = 375, [exs_yhm2712a.CCMAX] = 500},
    [1000] = {[exs_yhm2712a.CCMIN] = 50, [exs_yhm2712a.CCDEFAULT] = 500, [exs_yhm2712a.CCMAX] = 750}
}

--[[
注册exs_yhm2712a事件回调
@api exs_yhm2712a.on(func)
@function 回调方法，回调时传入参数有exs_yhm2712a.OVERHEAT, exs_yhm2712a.CHARGER_IN, exs_yhm2712a.CHARGER_OUT
@return nil 无返回值
@usage
local function exs_yhm2712a_callback(event)
    if event == exs_yhm2712a.OVERHEAT then
        log.info("警告：设备温度过高！")
    elseif event == exs_yhm2712a.CHARGER_IN then
        log.info("充电器已插入")
    elseif event == exs_yhm2712a.CHARGER_OUT then
        log.info("充电器已拔出")
    end
end
-- 注册回调
exs_yhm2712a.on(exs_yhm2712a_callback)
--]]
function exs_yhm2712a.on(cb)
    callback = cb
end

-- 内部事件触发函数
local function notify_event(event)
    if callback then
        callback(event)
    end
end

-- 查找最接近的电池容量标准值（最小100mAh），使用四舍五入规则
local function get_closest_capacity(capacity)
    -- 四舍五入到最近的100的倍数
    local rounded = math.floor(capacity / 100 + 0.5) * 100
    -- 确保结果不小于100mAh
    rounded = math.max(100, rounded)
    return rounded
end

--[[
初始化YHM2712A充电管理芯片,必须在task中运行,最大阻塞时间大概为700ms, 阻塞主要由sys.waitUntil("YHM27XX_REG", 500)和sys.wait(200)产生。
@api exs_yhm2712a.setup(init_cfg)
@param init_cfg table 初始化配置表
    pin:number, YHM2712A CMD引脚，必选
    v_battery:number, 电池充电截止电压, 取值范围：4200或4350可选, 单位(mV), 必须传入
    cap_battery:number, 电池容量, 取值范围：>= 100, 单位(mAh)，必须传入。
    i_charge:string, 充电电流, 取值范围：exs_yhm2712a.CCMIN(最小电流) 或 exs_yhm2712a.CCDEFAULT(默认电流) 或 exs_yhm2712a.CCMAX(最大电流)，三个可选参数，不传入时默认值为exs_yhm2712a.CCDEFAULT。
@return boolean 成功返回true，失败返回false
@usage
local setup_ok = exs_yhm2712a.setup({
    pin = 152,
    v_battery = 4200,
    cap_battery = 400,
    i_charge = exs_yhm2712a.CCMIN
})
if setup_ok then
    log.info("exs_yhm2712a", "传感器初始化成功")
end
]]
function exs_yhm2712a.setup(init_cfg)
    if type(init_cfg) ~= "table" then
        log.error("exs_yhm2712a", "参数必须为表")
        return false
    end

    if not init_cfg.pin then
        log.error("exs_yhm2712a", "引脚参数为必填项")
        return false
    end

    gpio_pin = init_cfg.pin
    sensor_addr = 0x04
    voltage_setting = set_4V35
    is_charge = false
    charger_only = false
    nochg_t = {}

    -- 检测芯片是否存在
    local result, data = pm.chgcmd(gpio_pin, sensor_addr, id_register)
    if not result then
        log.error("exs_yhm2712a", "无法读取芯片ID，通信失败")
        return false
    end

    log.debug("exs_yhm2712a", "芯片ID:", string.format("0x%02X", data))
    
    -- 设置充电参数
    local v_battery = init_cfg.v_battery
    local cap_battery = init_cfg.cap_battery
    local i_charge = init_cfg.i_charge or exs_yhm2712a.CCDEFAULT

    -- 验证电池电压
    if v_battery ~= 4200 and v_battery ~= 4350 then
        log.error("exs_yhm2712a", "无效的电池电压，必须是 4200 (4.20V) 或 4350 (4.35V)")
        return false
    end

    -- 验证电池容量范围
    if cap_battery and (type(cap_battery) ~= "number" or cap_battery < 100) then
        log.error("exs_yhm2712a", "电池容量过低,小于100mAh")
        return false
    end

    -- 验证充电电流参数
    if i_charge ~= exs_yhm2712a.CCMIN and i_charge ~= exs_yhm2712a.CCDEFAULT and i_charge ~= exs_yhm2712a.CCMAX then
        log.error("exs_yhm2712a", "无效的充电电流参数，必须是 exs_yhm2712a.CCMIN、exs_yhm2712a.CCDEFAULT 或 exs_yhm2712a.CCMAX，已使用默认值")
        return false
    end

    -- 设置电池充电截止电压
    voltage_setting = v_battery == 4200 and set_4V2 or set_4V35
    result, data = pm.chgcmd(gpio_pin, sensor_addr, V_ctrl_register, voltage_setting)
    if not result then
        log.error("exs_yhm2712a", "设置电池充电截止电压失败")
        return false
    end

    -- 获取电流值，如果容量超过1000mAh，则使用1000mAh的配置
    -- 根据实际电流值获取对应的十六进制参数
    if cap_battery then
        local closest_capacity = get_closest_capacity(cap_battery)
        local actual_capacity = math.min(closest_capacity, 1000)
        local actual_current = current_table[actual_capacity][i_charge]
        local current_register_value = current_to_register[actual_current]
        
        if not current_register_value then
            log.error("exs_yhm2712a", "未找到对应电流值的寄存器参数")
            return false
        end
        
        -- 设置充电电流
        result, data = pm.chgcmd(gpio_pin, sensor_addr, I_ctrl_register, current_register_value)
        if not result then
            log.error("exs_yhm2712a", "设置电池充电电流失败")
            return false
        end
    end

    sys.wait(200) -- 写入命令之后等待200ms再去读取寄存器数据，必须要等待，否则会有读取寄存器失败的可能。
    
    pm.chginfo(gpio_pin, sensor_addr)
    local reg_result, reg_data = sys.waitUntil("YHM27XX_REG", 500)
    if reg_result and reg_data then
        local V_value = reg_data:byte(1)
        if V_value == voltage_setting then
            log.info("exs_yhm2712a", "初始化完成，引脚:", gpio_pin)
            log.info("exs_yhm2712a", "充电电压:", v_battery, "mV")
            if cap_battery then
                log.info("exs_yhm2712a", "电池容量:", cap_battery, "mAh")
                log.info("exs_yhm2712a", "充电电流模式:", i_charge)
            end
            return true
        else
            log.warn("exs_yhm2712a.setup 未生效, 请检查是否支持yhm27xx")
            return false
        end
    else
        log.error("exs_yhm2712a.setup" .. "0x04寄存器数据获取失败")
        return false
    end
end

--[[
开始充电(必须在task中运行，最大阻塞时间大概为700ms, 阻塞主要由sys.waitUntil("YHM27XX_REG", 500)和sys.wait(200)产生。)
@api exs_yhm2712a.start()
@return boolean: true=成功, false=失败
@usage
exs_yhm2712a.start() -- 开始充电
]]
function exs_yhm2712a.start()
    if not gpio_pin then
        log.error("exs_yhm2712a.start", "YHM2712A未初始化，请先调用exs_yhm2712a.setup(init_cfg)")
        return false
    end
    -- 读取芯片ID，验证通信是否正常
    local result, data = pm.chgcmd(gpio_pin, sensor_addr, id_register)
    if not result then
        log.error("exs_yhm2712a", "无法读取芯片ID, 通信失败")
        return false
    end

    sys.wait(200) -- 写入命令之后等待200ms再去读取寄存器数据，必须要等待，否则会有读取寄存器失败的可能。

    -- 开启充电前先查询ic温度，如果过热，则不执行开启充电功能
    pm.chginfo(gpio_pin, sensor_addr)
    result, data = sys.waitUntil("YHM27XX_REG", 500)
    if not result or not data or #data < 6 then
        log.error("exs_yhm2712a.start1" .. "0x04寄存器数据获取失败")
        return false
    end
    
    -- 提取0x05寄存器的第3位(从0开始计数)
    -- 过热标志位为1，表示温度>120℃
    -- 过热标志位为0，表示温度<120℃
    local overheat = (data:byte(6) & 0x08) ~= 0
    if overheat then
        log.error("exs_yhm2712a.start" .. "ic温度过高,不执行充电功能")
        return false
    end

    -- 开始充电
    result = pm.chgcmd(gpio_pin, sensor_addr, mode_register, 0xA8)
    if not result then
        log.error("exs_yhm2712a.start", "开始充电失败")
        return false
    end

    sys.wait(200) -- 写入命令之后等待200ms再去读取寄存器数据，必须要等待，否则会有读取寄存器失败的可能。

    -- 请求寄存器数据
    pm.chginfo(gpio_pin, sensor_addr)
    local reg_result, reg_data = sys.waitUntil("YHM27XX_REG", 500)
    if reg_result and reg_data then
        if reg_data:byte(3) == 160 then
            log.info("exs_yhm2712a.start 生效")
            return true
        else
            log.warn("exs_yhm2712a.start 未生效, 请检查是否支持yhm27xx")
            return false
        end
    else
        log.error("exs_yhm2712a.start2" .. "0x04寄存器数据获取失败")
        return false
    end
end

--[[
停止充电(必须在task中运行，最大阻塞时间大概为700ms, 阻塞主要由sys.waitUntil("YHM27XX_REG", 500)和sys.wait(200)产生。)
@api exs_yhm2712a.stop()
@return boolean: true=成功, false=失败
@usage
exs_yhm2712a.stop() -- 停止充电
]]
function exs_yhm2712a.stop()
    if not gpio_pin then
        log.error("exs_yhm2712a.stop", "YHM2712A未初始化，请先调用exs_yhm2712a.setup(init_cfg)")
        return false
    end
    -- 读取芯片ID，验证通信是否正常
    local result = pm.chgcmd(gpio_pin, sensor_addr, id_register)
    if not result then
        log.error("exs_yhm2712a", "无法读取芯片ID, 通信失败")
        return false
    end
    result = pm.chgcmd(gpio_pin, sensor_addr, mode_register, 0xF8)
    if not result then
        log.error("exs_yhm2712a.stop", "停止充电失败")
        return false
    end
    sys.wait(200) -- 写入命令之后等待200ms再去读取寄存器数据，必须要等待，否则会有读取寄存器失败的可能。
    -- 请求寄存器数据
    pm.chginfo(gpio_pin, sensor_addr)
    local reg_result, reg_data = sys.waitUntil("YHM27XX_REG", 500)
    if reg_result and reg_data then
        if reg_data:byte(3) == 240 then
            log.info("exs_yhm2712a.stop 生效")
            return true
        else
            log.warn("exs_yhm2712a.stop 未生效, 请检查是否支持yhm27xx")
            return false
        end
    else
        log.error("exs_yhm2712a.stop" .. "0x04寄存器数据获取失败")
        return false
    end
end

--[[
进入船运模式(必须在task中运行，最大阻塞时间大概为2200ms, 阻塞主要由sys.waitUntil("YHM27XX_REG", 500)和sys.wait(2000)产生。)
@api exs_yhm2712a.ship_mode()
@return boolean: true=成功, false=失败
@usage
exs_yhm2712a.ship_mode() -- 进入船运模式
]]
function exs_yhm2712a.ship_mode()
    if not gpio_pin then
        log.error("exs_yhm2712a.ship_mode", "YHM2712A未初始化，请先调用exs_yhm2712a.setup(init_cfg)")
        return false
    end
    -- 读取芯片ID，验证通信是否正常
    local result, data = pm.chgcmd(gpio_pin, sensor_addr, id_register)
    if not result then
        log.error("exs_yhm2712a", "无法读取芯片ID, 通信失败")
        return false
    end
    
    -- 发送进入船运模式的命令（MODE寄存器地址0x02，值为0x18：MODE[3:0]=0001(SHIPPING)，M_SET=1）
    result = pm.chgcmd(gpio_pin, sensor_addr, mode_register, 0x18)
    if not result then
        log.error("exs_yhm2712a.shipMode", "发送船运模式命令失败")
        return false
    end
    
    -- 等待命令生效（至少2秒，根据数据手册tSMEN_DGL=2s）
    sys.wait(2000)
    
    -- 请求寄存器数据，验证是否进入船运模式
    pm.chginfo(gpio_pin, sensor_addr)
    local reg_result, reg_data = sys.waitUntil("YHM27XX_REG", 500)
    
    if reg_result and reg_data then
        -- 检查0x06寄存器（STATUS2）的FSM_MODE[3:0]是否为0001（SHIPPING）
        local status2 = reg_data:byte(7) -- status2_register是0x06，对应第7字节
        local fsm_mode = (status2 & 0xF0) >> 4
        if fsm_mode == 1 then
            log.info("exs_yhm2712a.shipMode 生效")
            notify_event(exs_yhm2712a.SHIPPING_MODE)
            return true
        else
            log.warn("exs_yhm2712a.shipMode 未生效, 当前FSM模式: " .. fsm_mode .. ", 请检查是否支持yhm27xx")
            return false
        end
    else
        log.warn("exs_yhm2712a.shipMode 未生效, 请检查是否支持yhm27xx")
        return false
    end
end

-- 检测电池是否在位
local function check_battery_exists()
    local switch_count = 0
    local last_status = nil
    local loop_count = 0
    local total_loops = 50  -- 50次循环, 每次循环至少100ms

    for loop_count = 1, total_loops do
        -- log.debug("当前循环", loop_count, "/", total_loops)
        -- 发送读取请求
        pm.chginfo(gpio_pin, sensor_addr)
        local result, data = sys.waitUntil("YHM27XX_REG", 200)
        -- 存储解析后的寄存器数据
        local Data_reg = {}

        if result and data then
            for i=1,9 do
                Data_reg[i] = data:byte(i)
            end
            -- 提取Data_reg[7](对应0x06寄存器)的7:4 位
            -- 1. 使用0xF0(二进制1111 0000)进行按位与操作，保留高4位
            -- 2. 右移4位将结果转换为十进制
            local current_status = (Data_reg[7] & 0xF0) >> 4
            -- log.debug("状态:", current_status)

            -- 只关注状态12(1100)和13(1101)
            if current_status == 12 or current_status == 13 then
                if last_status ~= nil and last_status ~= current_status then
                    switch_count = switch_count + 1
                    -- log.debug("状态切换", last_status, "->", current_status, "次数:", switch_count)

                    -- 达到切换阈值提前退出
                    if switch_count >= 2 then
                        -- log.info("电池判定", "不在位（频繁切换）")
                        return false
                    end
                end
                last_status = current_status
            else
                last_status = nil
            end
        else
            log.error("check_battery_exists", "0x04寄存器数据获取失败")
            last_status = nil
        end

        -- 确保每次循环间隔至少100ms
        if loop_count < total_loops then
            sys.wait(100) 
        end
    end

    -- log.debug("检测结束", "切换次数:", switch_count)
    if switch_count >= 2 then
        return false
    else
        return true
    end
end

--[[
获取当前的充电阶段状态
-- 充电状态说明:
--     0 (000): 放电模式
--     1 (001): 预充电模式     
--     2 (010): 涓流充电      
--     3 (011): 恒流快速充电 
--     4 (100): 预留状态      
--     5 (101): 恒压快速充电  
--     6 (110): 预留状态    
--     7 (111): 充电完成       
]]
local function get_charge_status()
    pm.chginfo(gpio_pin, sensor_addr)
    local result, data = sys.waitUntil("YHM27XX_REG", 500)

    -- 存储解析后的寄存器数据
    local Data_reg = {}
    if result and data then
        for i=1,9 do
            Data_reg[i] = data:byte(i)
        end
        -- 提取充电状态信息
        -- 充电状态位于0x05寄存器(对应Data_reg[6])的高3位(第7-5位)
        -- 1. 使用0xE0(二进制1110 0000)进行按位与操作，保留高3位
        -- 2. 右移5位，将高3位移到最低位
        local charge_status = (Data_reg[6] & 0xE0) >> 5
        return charge_status
    else
        log.error("get_charge_status", "0x04寄存器数据获取失败")
        return nil
    end
end


-- 查询充电ic是否过热
local overheat_check_timer = nil
local function check_over_heat()
    pm.chginfo(gpio_pin, sensor_addr)
    local result, data = sys.waitUntil("YHM27XX_REG", 500)
    
    if not result or not data or #data < 6 then
        log.error("check_over_heat", "0x04寄存器数据获取失败")
        return false
    end

    -- 提取0x05寄存器的第3位(从0开始计数)
    -- 过热标志位为1，表示温度>120℃
    -- 过热标志位为0，表示温度<120℃
    local overheat = (data:byte(6) & 0x08) ~= 0

    if overheat then
        -- 充电IC过热, 大于120℃, 停止充电！
        exs_yhm2712a.stop()
        notify_event(exs_yhm2712a.OVERHEAT)

        -- 如果已有定时器在运行，先停止
        if overheat_check_timer then
            sys.timerStop(overheat_check_timer)
            overheat_check_timer = nil
        end
        -- 启动定时器，10分钟后再次检查
        overheat_check_timer = sys.timerStart(check_over_heat, 10 * 60 * 1000)
    else
        -- 温度正常
        if overheat_check_timer then 
            -- 停止定时器（因为温度已恢复，不再需要检查）
            sys.timerStop(overheat_check_timer) 
            overheat_check_timer = nil 
            -- 重新启动充电
            exs_yhm2712a.start() 
        end 
    end
    
    return true, overheat
end


-- 启用或禁用SYS_TRACK电压跟随功能 0x01寄存器
function set_sys_track(enable)
    if type(enable) ~= "boolean" then
        log.error("set_sys_track: 无效的enable参数，必须是布尔值")
        return false
    end

    local reg_addr = 0x01 -- SYS_TRACK所在寄存器地址
    local reg_value = 0x00 -- 初始值
    local max_retry = 3 -- 最大重试次数
    local retry_count = 0 -- 重试计数

    -- 读取当前寄存器值
    while retry_count <= max_retry do
        pm.chginfo(gpio_pin, sensor_addr)
        local result, data = sys.waitUntil("YHM27XX_REG", 500)
        local Data_reg={}

        if result then
            -- 将data按字节解析到Data_reg数组
            for i=1, #data do
                Data_reg[i] = data:byte(i)
            end
            reg_value = Data_reg[2]
            break
        else
            retry_count = retry_count + 1
            log.warn("set_sys_track: 读取寄存器失败，正在重试 (" .. retry_count .. "/" .. max_retry .. ")")
            if retry_count > max_retry then
                log.error("set_sys_track: 超过最大重试次数，读取寄存器失败")
                return false
            end
            sys.wait(100)
        end
    end

    -- 保存原始值，用于比较
    local original_value = reg_value

    -- 设置SYS_TRACK位 (bit 1)
    if enable then
        reg_value = reg_value | 0x02 -- 设置bit 1为1 (0x02 = 00000010)
    else
        reg_value = reg_value & 0xFD -- 设置bit 1为0 (0xFD = 11111101)
    end

    -- 如果值没有变化，不需要写入
    if reg_value == original_value then
        -- log.info("set_sys_track: SYS_TRACK" .. (enable and "启用" or "禁用") .. "状态已保持，无需写入")
        return true
    end

    -- log.info("set_sys_track: 修改后寄存器值", string.format("0x%02X", reg_value))

    -- 写入新值
    retry_count = 0
    while retry_count <= max_retry do
        local result, data = pm.chgcmd(gpio_pin, sensor_addr, reg_addr, reg_value)
        if result then
            -- log.info("set_sys_track: SYS_TRACK" .. (enable and "启用" or "禁用") .. "成功")
            return true
        else
            retry_count = retry_count + 1
            log.warn("set_sys_track: 写入寄存器失败，正在重试 (" .. retry_count .. "/" .. max_retry .. ")")
            if retry_count > max_retry then
                log.error("set_sys_track: 超过最大重试次数，写入寄存器失败")
                return false
            end
            sys.wait(100) -- 重试前等待100ms
        end
    end
end


-- 中断检测充电器是否在位（通过检测VBUS引脚的电平来判断充电器是否在位），并对外发布CHARGER_STATE_EVENT事件
local function check_charger()
    if gpio.get(vbus_pin) == 0 then
        if is_charge then
            is_charge = false
            notify_event(exs_yhm2712a.CHARGER_OUT)
        end
    else
        if not is_charge then
            is_charge = true
            notify_event(exs_yhm2712a.CHARGER_IN)
        end
    end
end
-- 初始化GPIO中断
gpio.debounce(vbus_pin, 500, 1)  -- 消抖
gpio.setup(vbus_pin, check_charger, gpio.PULLUP, gpio.BOTH) -- 上拉电阻+双沿触发
check_charger() -- 初始检测

-- 向滑动窗口数组添加新的电压采样值，并计算窗口内的平均值, 用于平滑电压采样数据
local function append_vadc(v)
    -- 如果窗口已满（达到最大长度 AVR_MAX）
    if #nochg_t >= AVR_MAX then
        -- 添加新值到窗口末尾
        table.insert(nochg_t, v)
        -- 移除窗口最前面的旧值
        table.remove(nochg_t, 1)
    else
        -- 窗口未满时，用当前值填充整个窗口
        -- 这确保初始化阶段也存在有效的平均值
        while #nochg_t < AVR_MAX do
            table.insert(nochg_t, v)
        end
    end
    -- 计算窗口内所有值的总和
    local totv = 0
    local min_val = nochg_t[1]
    local max_val = nochg_t[1]
    for i = 1, #nochg_t do
        totv = totv + nochg_t[i]
        if nochg_t[i] < min_val then
            min_val = nochg_t[i]
        end
        if nochg_t[i] > max_val then
            max_val = nochg_t[i]
        end
    end
    -- 计算平均值：去掉一个最大值和一个最小值
    local count = #nochg_t
    local avg
    -- 当窗口大小小于3时，无法去掉最大最小值
    if count < 3 then
        avg = totv // count
    else
        avg = (totv - min_val - max_val) // (count - 2)
    end
    log.info("append_vadc", totv, count, avg)
    return avg
end

-- 获取电池电压
local function check_battery(param)
    adc.open(adc.CH_VBAT) -- 打开ADC通道
    local vbat = adc.get(adc.CH_VBAT) -- 读取电压
    adc.close(adc.CH_VBAT) -- 关闭ADC通道
    -- -- 计算采集电压的平均值，去掉一个最大值和一个最小值
    -- vbat = append_vadc(vbat)
    if param then
        vbat = math.floor(vbat / param + 0.5)
    end

    return vbat
end

--[[ 
获取充电系统状态信息(必须在task中运行，最大阻塞时间(包括超时重试时间)大概为20s)。该函数用于获取当前充电系统的完整状态，包括电池电压、充电阶段、充电状态、电池在位状态、充电器在位状态以及IC过热状态等信息。其中充电器是否在位，中断触发，触发回调事件为CHARGER_STATE_EVENT，附带的参数 true表示充电器在位，false表示充电器不在位。
@api exs_yhm2712a.status()
@return table 状态信息表，包含result字段指示操作是否成功
{
    result = boolean,       -- true: 成功, false: 失败
    vbat_voltage = number,  -- 电池电压值（单位：mV），特殊值含义：
                            -- -1: 当前阶段不需要测量
                            -- -2: 电压测量失败
                            -- -3: 仅充电器就绪（无电池）
    charge_stage = number,  -- 当前充电阶段描述，可能值：
                            -- 0 : 放电模式
                            -- 1 : 预充电模式    
                            -- 2 : 涓流充电     
                            -- 3 : 恒流快速充电
                            -- 4 : 预留状态     
                            -- 5 : 恒压快速充电 
                            -- 6 : 预留状态    
                            -- 7 : 充电完成  
                            -- 8 : 未知状态
    charge_complete = boolean, -- true: 充电完成, false: 充电未完成
    battery_present = boolean, -- true: 电池在位, false: 电池不在位
    charger_present = boolean, -- true: 充电器在位, false: 充电器不在位
    ic_overheat = boolean     -- true: 充电IC过热, false: 充电IC未过热
}
@usage
local status = exs_yhm2712a.status()
if status.result then
    log.info("电池电压:", status.vbat_voltage)
    log.info("充电阶段:", status.charge_stage)
    log.info("充电是否完成:", status.charge_complete)
    log.info("电池在位:", status.battery_present)
    log.info("充电器在位:", status.charger_present)
    log.info("IC过热:", status.ic_overheat)
else
    log.warn("exs_yhm2712a.status", "状态获取失败")
end 
--]]
function exs_yhm2712a.status()
    if not gpio_pin then
        log.error("exs_yhm2712a.status", "YHM2712A未初始化，请先调用exchk.setup(pin)")
        return {
            result = false,
            vbat_voltage = 0,
            charge_stage = 8,
            charge_complete = false,
            battery_present = false,
            charger_present = is_charge,
            ic_overheat = false,
        }
    end
    -- 初始化所有状态
    local status = {
        result = true,
        vbat_voltage = 0,
        charge_stage = 8,
        charge_complete = false,
        battery_present = false,
        charger_present = is_charge,
        ic_overheat = false,
    }
    
    -- 1. 检查电池是否在位
    status.battery_present = check_battery_exists()

    sys.wait(100) -- yhm27xx操作之间必须延时一段时间

    -- 2. 检查充电IC是否过热
    local overheat_success, overheat_temp = check_over_heat()
    if overheat_success then
        status.ic_overheat = overheat_temp
    else
        log.warn("充电IC温度检测失败")
        status.result = false
    end
    
    sys.wait(100) -- yhm27xx操作之间必须延时一段时间

    -- 3. 获取充电阶段
    local stage_temp = get_charge_status()
    if stage_temp then
        status.charge_stage = stage_temp
    else
        log.warn("充电阶段检测失败")
        status.result = false
    end
    
    -- 4. 在特定阶段测量电池电压
    if status.battery_present then
        if charger_only then
            local result = pm.chgcmd(gpio_pin, sensor_addr, V_ctrl_register, voltage_setting)
            charger_only = false
        end
        -- 预充电或涓流充电阶段不测量电压
        if status.charge_stage == 1 or status.charge_stage == 2 then
            -- 设置特殊电压值表示未测量
            status.vbat_voltage = -1
            log.info("当前阶段:", status.charge_stage, "当前电压过低，正在涓流充电阶段努力充电中..., 请保持充电器连接")

        -- 恒流/恒压阶段，打开电压跟随功能测量电池电压
        elseif status.charge_stage == 3 or status.charge_stage == 5  then
            -- 打开电压跟随功能
            local result = set_sys_track(true)
            if result then
                local vbat = check_battery(1.053)
                status.vbat_voltage = vbat
                sys.wait(100)
                set_sys_track(false) -- 测量完关闭电压跟随功能
            else
                log.warn("无法打开电压跟随功能")
                -- 测量失败
                status.vbat_voltage = -2
                status.result = false
            end
        -- 充电完成
        elseif status.charge_stage == 7 then
            local vbat = check_battery(1.03)
            status.vbat_voltage = vbat
        -- 放电模式
        elseif status.charge_stage == 0 then
            local vbat = check_battery()
            status.vbat_voltage = vbat
        else
            -- 只做提示，不测量电压
            status.vbat_voltage = -1
        end
    elseif status.charger_present then
        -- 充电器在位，电池不在位, Vreg设置为4V，这样Vsys=1.03*4.0V=4.1V, 在模组的电压舒适区
        local result = pm.chgcmd(gpio_pin, sensor_addr, V_ctrl_register, set_4V)
        if not result then
            log.warn("仅充电器在位时, Vreg设置为4V失败")
            status.result = false
        end
        -- 标记当前状态为"充电器在位但电池不在位"
        charger_only = true
        -- 更新状态值
        status.vbat_voltage = -3
        status.charge_stage = 8
        status.charge_complete = false
        status.battery_present = false
    end
    
    -- 5. 判断充电是否完成
    status.charge_complete = (status.charge_stage == 7)
    
    return status
end

--[[
获取库版本信息
@api exs_yhm2712a.version()
@return string 库版本号，格式：年月日时分
@usage
log.info("exs_yhm2712a", "version:", exs_yhm2712a.version())
]]
function exs_yhm2712a.version()
    return "202607201900"
end

-- sys.taskInit(function()
--     -- 连续ADC 电路稳定后，连续采集10次作为初始均值成员
--     for i = 1, AVR_MAX do
--         check_battery()
--         sys.wait(200)
--     end
-- end)

log.debug("exs_yhm2712a", "version -> " .. exs_yhm2712a.version())

return exs_yhm2712a