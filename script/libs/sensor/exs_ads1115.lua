--[[
@module  exs_ads1115
@summary ADS1115 16位ADC驱动扩展库
@version(1.0)
@date    2026.08.24
@author  王城钧
@usage
本扩展库提供 TI ADS1115 16 位精密模数转换器（ADC）的 LuatOS 驱动，功能包括：
1、初始化（I2C 初始化/设备地址自动探测/配置加载/就绪确认）
2、数据读取（4 路单端或 2 路差分电压，返回物理电压值）

-- 加载扩展库
local exs_ads1115 = require "exs_ads1115"

-- 硬件 I2C 方式初始化（i2c_id 按模组硬件支持填写）
local ok = exs_ads1115.setup({i2c_id = 1})
if not ok then return end

-- 读取电压数据（单端输入返回 0~满量程 V，含校准）
local data = exs_ads1115.get_data()
if data then
    log.info("exs_ads1115", string.format("voltage:%.4fV raw:%d", data.voltage, data.raw))
end

对外接口 11 个：
- exs_ads1115.setup(config)：初始化
- exs_ads1115.get_data()：读取电压数据
- exs_ads1115.get_raw(channel)：读取指定通道原始码
- exs_ads1115.set_config(cfg)：动态修改通道/PGA/速率/模式
- exs_ads1115.set_threshold(lo_v, hi_v)：设置比较器阈值
- exs_ads1115.set_comparator(mode, queue, latch)：配置比较器
- exs_ads1115.get_alert()：查询报警状态
- exs_ads1115.set_offset(value)：零偏校准
- exs_ads1115.set_gain(value)：增益校准
- exs_ads1115.close()：释放资源
- exs_ads1115.version()：获取版本号

=== 版本更新说明 ===
-- 版本号：202608241540
-- 1、更新时间：2026-08-24
-- 2、更新内容：
--   - 初版实现
--   - 修复 build_config 的 MODE 位写反问题（导致连续模式失效、芯片停止转换）
--   - 连续模式读取前等待 2 个转换周期（避免 MUX 切换后读到旧通道残留值）
--   - I2C 读取失败自动重试并重建总线（防止 GPIO 中断打断 I2C 传输后总线卡死）
--   - 经 Air780EPM 核心板真机测试通过（含比较器中断双向触发验证）
]]

local exs_ads1115                          = {}

-- ==================== 寄存器地址 ====================

local REG_CONVERSION                       = 0x00  -- 转换结果寄存器（16位补码，大端序）
local REG_CONFIG                           = 0x01  -- 配置寄存器（默认 0x8583，含 MUX/PGA/DR/比较器位）
local REG_LO_THRESH                        = 0x02  -- 比较器低阈值寄存器（默认 0x8000，16位补码）
local REG_HI_THRESH                        = 0x03  -- 比较器高阈值寄存器（默认 0x7FFF，16位补码）

-- ==================== 配置参数 ====================

local PGA_FS_LIST                          = {6.144, 4.096, 2.048, 1.024, 0.512, 0.256}  -- PGA 码→满量程电压 V
local PGA_LIST                             = {0.667, 1, 2, 4, 8, 16}                     -- 支持的增益档位
local SPS_LIST                             = {8, 16, 32, 64, 128, 250, 475, 860}        -- 支持的数据速率
local MUX_SINGLE                           = {4, 5, 6, 7}                                -- 单端通道 0~3→MUX 码（AINx-GND）
local MUX_DIFF                             = {0, 3}                                      -- 差分通道 0/1→MUX 码（AIN0-AIN1/AIN2-AIN3）
local ADDR_LIST                            = {0x48, 0x49, 0x4A, 0x4B}                     -- 可探测的 I2C 地址（ADDR 引脚决定）

-- ==================== 内部状态 ====================

local g_i2c_id                             = nil    -- I2C 总线 id（硬件 id 或软件 I2C 对象）
local g_is_soft                            = false  -- 是否为软件 I2C
local g_addr                               = nil    -- I2C 设备地址（0x48~0x4B）
local g_ready                              = false  -- 是否初始化完成
local g_channel                            = 0      -- 当前通道号（单端 0~3，差分 0/1）
local g_diff                               = false  -- 是否差分输入模式
local g_pga_code                           = 1      -- PGA 码（0~5）
local g_fs                                 = 4.096  -- 当前满量程电压 V
local g_sps_code                           = 4      -- 数据速率码（0~7）
local g_sps                                = 128    -- 当前数据速率 SPS
local g_mode                               = 1      -- 工作模式：1=单次，0=连续
local g_comp_mode                          = 0      -- 比较器模式：0=传统，1=窗口
local g_comp_queue                         = 3      -- COMP_QUE：0/1/2=启用比较器，3=禁用（默认）
local g_comp_lat                           = 0      -- COMP_LAT：0=非锁存，1=锁存
local g_comp_pol                           = 0      -- COMP_POL：0=低有效，1=高有效
local g_alert_pin                          = nil    -- ALERT/RDY 引脚（get_alert 查询用）
local g_offset                             = 0      -- 零偏校准值 V
local g_gain                               = 1      -- 增益校准系数

-- ==================== I2C 操作 ====================

-- 写 2 字节寄存器：先写指针寄存器，再写数据高字节、低字节
-- reg：寄存器指针（0x00~0x03）；hi/lo：数据高/低字节
-- 返回 i2c.send 是否成功（boolean）
local function write_reg(reg, hi, lo)
    return i2c.send(g_i2c_id, g_addr, {reg, hi, lo})
end

-- 读 2 字节寄存器：先写指针寄存器指向目标寄存器，再读取
-- reg：寄存器指针（0x00~0x03）
-- 返回 数据高字节、低字节；失败返回 nil
-- 说明：读取失败时自动重试并重建 I2C 总线，防止 GPIO 中断打断 I2C 传输后总线卡死
local function read_reg(reg)
    -- 写指针寄存器指向目标寄存器
    i2c.send(g_i2c_id, g_addr, {reg})
    -- 读取 2 字节数据（失败返回空字符串）
    local data = i2c.recv(g_i2c_id, g_addr, 2)
    if data and #data == 2 then
        return data:byte(1), data:byte(2)
    end
    -- 首次失败：等待 10ms 后重试（GPIO 中断可能打断 I2C 传输，重试可恢复）
    sys.wait(10)  -- 等待总线稳定后重试
    i2c.send(g_i2c_id, g_addr, {reg})
    data = i2c.recv(g_i2c_id, g_addr, 2)
    if data and #data == 2 then
        return data:byte(1), data:byte(2)
    end
    -- 重试仍失败：重建 I2C 总线后最后尝试一次（清除总线卡死状态）
    if not g_is_soft then
        i2c.close(g_i2c_id)  -- 关闭硬件 I2C，释放总线
        i2c.setup(g_i2c_id, i2c.FAST)  -- 重新初始化硬件 I2C
        sys.wait(10)  -- 等待 I2C 重新初始化完成
        i2c.send(g_i2c_id, g_addr, {reg})
        data = i2c.recv(g_i2c_id, g_addr, 2)
        if data and #data == 2 then
            return data:byte(1), data:byte(2)
        end
    end
    return nil
end

-- 探测设备地址：依次写指针寄存器并读回，有应答即锁定
-- 返回地址 0x48~0x4B，全部无应答返回 nil
local function probe_addr()
    for i = 1, #ADDR_LIST do
        local addr = ADDR_LIST[i]
        -- 写指针寄存器指向 Config，测试设备是否应答
        i2c.send(g_i2c_id, addr, {REG_CONFIG})
        local data = i2c.recv(g_i2c_id, addr, 2)
        if data and #data == 2 then
            return addr  -- 有应答，锁定该地址
        end
    end
    return nil
end

-- 构建 Config 寄存器 16 位配置值
-- os_bit：1=启动单次转换，0=不启动
-- 位定义：bit15=OS，bit14:12=MUX，bit11:9=PGA，bit8=MODE，bit7:5=DR，bit4=COMP_MODE，
--         bit3=COMP_POL，bit2=COMP_LAT，bit1:0=COMP_QUE
-- 返回 16 位配置值
local function build_config(os_bit)
    local cfg = 0
    local mux = 0
    if g_diff then
        -- 差分模式：通道 0=AIN0-AIN1，通道 1=AIN2-AIN3
        mux = MUX_DIFF[g_channel + 1] or 0
    else
        -- 单端模式：通道 0~3 → AIN0~AIN3 对 GND
        mux = MUX_SINGLE[g_channel + 1] or 4
    end
    cfg = cfg | (os_bit << 15)          -- bit15 OS：启动单次转换
    cfg = cfg | (mux << 12)             -- bit14:12 MUX：输入选择
    cfg = cfg | (g_pga_code << 9)       -- bit11:9 PGA：增益设置
    cfg = cfg | (g_mode << 8)           -- bit8 MODE：0=连续，1=单次（g_mode 与芯片位定义一致）
    cfg = cfg | (g_sps_code << 5)       -- bit7:5 DR：数据速率
    cfg = cfg | (g_comp_mode << 4)      -- bit4 COMP_MODE：比较器模式
    cfg = cfg | (g_comp_pol << 3)       -- bit3 COMP_POL：报警极性
    cfg = cfg | (g_comp_lat << 2)       -- bit2 COMP_LAT：锁存
    cfg = cfg | (g_comp_queue & 0x03)   -- bit1:0 COMP_QUE：触发次数/禁用
    return cfg
end

-- 写配置寄存器并读回校验（比较时屏蔽 OS 位，因单次转换完成后 OS 自动清零）
-- os_bit：1=启动单次转换，0=不启动
-- 返回 true 校验通过，false 失败
local function write_config_checked(os_bit)
    local cfg = build_config(os_bit)
    local hi = (cfg >> 8) & 0xFF
    local lo = cfg & 0xFF
    if not write_reg(REG_CONFIG, hi, lo) then
        return false
    end
    -- 读回校验：屏蔽 bit15（OS 位）
    local rhi, rlo = read_reg(REG_CONFIG)
    if not rhi then
        return false
    end
    local read_back = (rhi << 8) | rlo
    return (read_back & 0x7FFF) == (cfg & 0x7FFF)
end

-- 等待单次转换完成：时长 = 1/数据速率 + 2ms 余量
local function wait_conversion()
    sys.wait(math.ceil(1000 / g_sps) + 2)  -- 等待转换完成：128SPS 约 10ms，8SPS 约 127ms
end

-- 读取 16 位转换结果（二进制补码转有符号）
-- 返回有符号数 -32768~32767，失败返回 nil
local function read_conversion()
    local hi, lo = read_reg(REG_CONVERSION)
    if not hi then
        return nil
    end
    local raw = (hi << 8) | lo
    if raw >= 0x8000 then
        raw = raw - 0x10000  -- 二进制补码转有符号数
    end
    return raw
end

-- 电压值 → 16 位补码（比较器阈值寄存器用），超出满量程自动钳位
-- volt：电压 V；返回 16 位补码（0x0000~0xFFFF）
local function volt_to_code(volt)
    local raw = math.floor(volt / g_fs * 32768 + 0.5)
    if raw > 32767 then
        raw = 32767  -- 钳位到正满量程
    elseif raw < -32768 then
        raw = -32768  -- 钳位到负满量程
    end
    if raw < 0 then
        raw = raw + 0x10000  -- 负值转补码
    end
    return raw
end

-- PGA 增益 → PGA 码（0~5），非法值自动裁剪到最近档位
-- pga：增益值；返回 PGA 码
local function pga_to_code(pga)
    local best_code = 1  -- 默认 ±4.096V
    local best_diff = math.abs(pga - PGA_LIST[2])
    for i = 1, #PGA_LIST do
        local diff = math.abs(pga - PGA_LIST[i])
        if diff < best_diff then
            best_diff = diff
            best_code = i - 1
        end
    end
    if best_diff > 0.01 then
        log.warn("exs_ads1115", "PGA 增益不支持（" .. pga .. "），已裁剪到 " .. PGA_LIST[best_code + 1])
    end
    return best_code
end

-- 数据速率 → DR 码（0~7），非法值自动裁剪到最近档位
-- sps：数据速率 SPS；返回 DR 码
local function sps_to_code(sps)
    local best_code = 4  -- 默认 128SPS
    local best_diff = math.abs(sps - SPS_LIST[5])
    for i = 1, #SPS_LIST do
        local diff = math.abs(sps - SPS_LIST[i])
        if diff < best_diff then
            best_diff = diff
            best_code = i - 1
        end
    end
    if best_diff > 0 then
        log.warn("exs_ads1115", "数据速率不支持（" .. sps .. "），已裁剪到 " .. SPS_LIST[best_code + 1])
    end
    return best_code
end

-- ==================== 对外 API ====================

--[[
初始化 ADS1115，完成 I2C 初始化、设备地址自动探测与默认配置加载

注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait()，在 task 外调用会报错）

@api exs_ads1115.setup(config)
@param table config
参数含义：初始化配置参数表
数据类型：table
取值范围：
{
    参数含义：硬件 I2C 总线编号（与 scl/sda 二选一，同时传优先硬件 I2C）
    数据类型：number
    取值范围：0 / 1，具体取决于模组硬件支持
    是否必选：否
    注意事项：Air780EPM 核心板使用 I2C1，对应 PIN66=SDA、PIN67=SCL
    参数示例：1
    config.i2c_id ,

    参数含义：软件 I2C SCL 引脚（与 i2c_id 二选一）
    数据类型：number
    取值范围：模组 GPIO 引脚编号
    是否必选：否
    注意事项：软件 I2C 速率约 100K，受网络业务影响，建议优先硬件 I2C
    参数示例：31
    config.scl ,

    参数含义：软件 I2C SDA 引脚（与 i2c_id 二选一）
    数据类型：number
    取值范围：模组 GPIO 引脚编号
    是否必选：否
    注意事项：与 scl 需同时传入
    参数示例：30
    config.sda ,

    参数含义：I2C 设备地址（可不传，自动探测）
    数据类型：number
    取值范围：0x48 / 0x49 / 0x4A / 0x4B（由 ADDR 引脚决定：接 GND=0x48，接 VDD=0x49，接 SDA=0x4A，接 SCL=0x4B）
    是否必选：否
    注意事项：不传时扩展库自动探测 0x48~0x4B 并锁定首个应答设备；接线改变后需重新上电
    参数示例：0x48
    config.addr ,

    参数含义：默认读取通道
    数据类型：number
    取值范围：0 / 1 / 2 / 3（单端模式）；差分模式 0 / 1
    是否必选：否
    注意事项：默认 0；差分模式需同时传 config.diff=true
    参数示例：0
    config.channel ,

    参数含义：是否差分输入模式
    数据类型：boolean
    取值范围：false（单端，默认）/ true（差分）
    是否必选：否
    注意事项：差分时通道 0=AIN0-AIN1，通道 1=AIN2-AIN3，电压可为负值
    参数示例：false
    config.diff ,

    参数含义：PGA 增益，决定满量程测量范围
    数据类型：number
    取值范围：0.667（满量程 ±6.144V，分辨率 187.5μV，适合 0~5V 电源监测）
             / 1（±4.096V，125μV，默认，适合 0~3.3V 信号）
             / 2（±2.048V，62.5μV）
             / 4（±1.024V，31.25μV）
             / 8（±0.512V，15.6μV）
             / 16（±0.256V，7.8μV，适合毫伏级小信号）
    是否必选：否
    注意事项：增益越高分辨率越高但满量程越小；信号幅度应尽量占满量程，默认 1
    参数示例：1
    config.pga ,

    参数含义：数据速率
    数据类型：number
    取值范围：8 / 16 / 32 / 64 / 128（默认，适合大多数监测场景）/ 250 / 475 / 860（单位 SPS）
    是否必选：否
    注意事项：速率越低噪声越小、转换等待时间越长；8SPS 时单次转换约 127ms
    参数示例：128
    config.sps ,

    参数含义：工作模式
    数据类型：number
    取值范围：1（单次模式，转换完成自动掉电，静态电流 0.5μA，默认）/ 0（连续模式，150μA）
    是否必选：否
    注意事项：单次模式读取时内部等待转换完成
    参数示例：1
    config.mode ,

    参数含义：ALERT/RDY 中断引脚编号（模组 GPIO）
    数据类型：number
    取值范围：根据模组 GPIO 引脚定义，如 22
    是否必选：否
    注意事项：传入后自动配置为输入上拉，get_alert() 可查询报警电平；中断回调请自行 gpio.setup 配置
    参数示例：22
    config.alert_pin ,
}
是否必选：是
@return boolean
含义说明：初始化是否成功
数据类型：boolean
取值范围：true（成功）/ false（失败，如 I2C 无应答、地址探测失败）
]]
function exs_ads1115.setup(config)
    if not config then
        log.error("exs_ads1115", "缺少配置参数 config")
        return false
    end
    -- I2C 初始化：硬件 I2C（i2c_id）或软件 I2C（scl/sda），同时传优先硬件 I2C
    g_is_soft = false
    if config.i2c_id then
        g_i2c_id = config.i2c_id
        local result = i2c.setup(g_i2c_id, i2c.FAST)  -- 初始化硬件 I2C，400kHz
        if result ~= 1 then
            log.error("exs_ads1115", "I2C 初始化失败，i2c_id =", g_i2c_id)
            return false
        end
    elseif config.scl and config.sda then
        g_is_soft = true
        g_i2c_id = i2c.createSoft(config.scl, config.sda, 5)  -- 创建软件 I2C，5us 半周期延时
    else
        log.error("exs_ads1115", "缺少 i2c_id 或 scl/sda 参数，请检查 setup(config)")
        return false
    end
    -- 设备地址：指定或自动探测
    g_addr = config.addr
    if not g_addr then
        g_addr = probe_addr()
        if not g_addr then
            log.error("exs_ads1115", "地址探测失败，检查接线: VCC=3.3V GND SCL SDA，ADDR 引脚不能悬空")
            return false
        end
        log.info("exs_ads1115", "自动探测地址", string.format("0x%02X", g_addr))
    end
    -- 解析默认配置
    g_diff = config.diff or false
    g_channel = config.channel or 0
    g_pga_code = pga_to_code(config.pga or 1)
    g_fs = PGA_FS_LIST[g_pga_code + 1]
    g_sps = config.sps or 128
    g_sps_code = sps_to_code(g_sps)
    g_sps = SPS_LIST[g_sps_code + 1]
    g_mode = (config.mode == 0) and 0 or 1
    -- 比较器默认禁用
    g_comp_mode = 0
    g_comp_queue = 3
    g_comp_lat = 0
    g_comp_pol = 0
    -- 校准默认值
    g_offset = 0
    g_gain = 1
    -- ALERT 引脚：配置为输入上拉
    g_alert_pin = config.alert_pin
    if g_alert_pin then
        gpio.setup(g_alert_pin, nil, gpio.PULLUP)  -- 输入模式 + 上拉，用于 get_alert 查询电平
    end
    -- 写配置并读回校验（单次模式顺带启动一次转换验证通信）
    if not write_config_checked(1) then
        log.error("exs_ads1115", "配置写入/校验失败，检查接线与地址")
        return false
    end
    wait_conversion()  -- 等待校验转换完成，确保芯片就绪
    g_ready = true
    log.info("exs_ads1115", "初始化成功，地址", string.format("0x%02X", g_addr),
             "满量程", g_fs, "V", "速率", g_sps, "SPS")
    return true
end

--[[
读取当前通道电压数据，返回电压值（V）、16 位原始码与当前通道号

注意事项：必须在 sys.taskInit() 创建的协程中调用（单次模式内部使用 sys.wait() 等待转换完成）

@api exs_ads1115.get_data()
@return table/nil
含义说明：读取结果，读取失败返回 nil
数据类型：table 或 nil
取值范围：
    data.voltage - 电压值，单位 V（单端 0~满量程 FS，差分 -FS~+FS，已套用校准）
    data.raw     - 16 位原始码，范围 -32768 ~ 32767
    data.channel - 当前通道号（单端 0~3，差分 0/1）
]]
function exs_ads1115.get_data()
    if not g_ready then
        log.warn("exs_ads1115", "未初始化，请先调用 setup()")
        return nil
    end
    if g_mode == 1 then
        -- 单次模式：写 OS=1 启动一次转换
        local cfg = build_config(1)
        if not write_reg(REG_CONFIG, (cfg >> 8) & 0xFF, cfg & 0xFF) then
            return nil
        end
        wait_conversion()  -- 等待转换完成，再读取结果
    else
        -- 连续模式：等待 2 个转换周期再读取
        -- 关键：MUX 切换后 Conversion 寄存器仍是旧通道残留值，必须等新转换完成
        -- 等待 2 个周期更保险，确保读到当前通道的最新转换结果（128SPS 约 16ms）
        local wait_ms = math.ceil(1000 / g_sps) * 2
        log.info("exs_ads1115", "连续模式等待", wait_ms, "ms")  -- 版本验证：新版才有此行
        sys.wait(wait_ms)  -- 等待当前通道转换完成，确保读到新数据
    end
    local raw = read_conversion()
    if not raw then
        log.warn("exs_ads1115", "读取转换结果失败")
        return nil
    end
    -- 电压换算：RAW × FS / 32768，再套用校准（零偏 + 增益）
    local voltage = raw * g_fs / 32768
    voltage = (voltage - g_offset) * g_gain
    return {voltage = voltage, raw = raw, channel = g_channel}
end

--[[
读取指定通道的 16 位原始码，不进行电压换算，用于校准与调试

注意事项：必须在 sys.taskInit() 创建的协程中调用（单次模式内部使用 sys.wait() 等待转换完成）

@api exs_ads1115.get_raw(channel)
@param number channel
参数含义：要读取的通道号
数据类型：number
取值范围：0 / 1 / 2 / 3（单端）；差分模式 0 / 1
是否必选：否
注意事项：不传时读取 setup 配置的默认通道
参数示例：0
@return number/nil
含义说明：16 位有符号原始码，读取失败返回 nil
数据类型：number 或 nil
取值范围：-32768 ~ 32767（二进制补码）
]]
function exs_ads1115.get_raw(channel)
    if not g_ready then
        log.warn("exs_ads1115", "未初始化，请先调用 setup()")
        return nil
    end
    channel = channel or g_channel
    if channel ~= g_channel then
        -- 通道切换：更新通道号并重写 Config（顺带启动转换）
        g_channel = channel
        local cfg = build_config(1)
        if not write_reg(REG_CONFIG, (cfg >> 8) & 0xFF, cfg & 0xFF) then
            return nil
        end
        wait_conversion()  -- 等待 MUX 切换与转换完成
    elseif g_mode == 1 then
        -- 通道未变，单次模式仍需启动转换
        local cfg = build_config(1)
        if not write_reg(REG_CONFIG, (cfg >> 8) & 0xFF, cfg & 0xFF) then
            return nil
        end
        wait_conversion()  -- 等待转换完成
    end
    return read_conversion()
end

--[[
动态修改通道、PGA 增益、数据速率与工作模式，无需重新 setup
@api exs_ads1115.set_config(cfg)
@param table cfg
参数含义：新配置参数表，仅需传入要修改的字段
数据类型：table
取值范围：
{
    参数含义：通道号
    数据类型：number
    取值范围：0 / 1 / 2 / 3（单端）；差分模式 0 / 1
    是否必选：否
    注意事项：不传则保持原配置
    cfg.channel ,

    参数含义：是否差分输入模式
    数据类型：boolean
    取值范围：false（单端）/ true（差分）
    是否必选：否
    cfg.diff ,

    参数含义：PGA 增益
    数据类型：number
    取值范围：0.667 / 1 / 2 / 4 / 8 / 16
    是否必选：否
    注意事项：修改后需重新调用 set_threshold() 设置比较器阈值
    cfg.pga ,

    参数含义：数据速率
    数据类型：number
    取值范围：8 / 16 / 32 / 64 / 128 / 250 / 475 / 860（单位 SPS）
    是否必选：否
    cfg.sps ,

    参数含义：工作模式
    数据类型：number
    取值范围：1（单次）/ 0（连续）
    是否必选：否
    cfg.mode ,
}
是否必选：是
@return boolean
含义说明：配置是否成功
数据类型：boolean
取值范围：true（成功）/ false（失败）
]]
function exs_ads1115.set_config(cfg)
    if not g_ready then
        log.warn("exs_ads1115", "未初始化，请先调用 setup()")
        return false
    end
    cfg = cfg or {}
    -- 更新通道与差分模式
    if cfg.channel ~= nil then
        g_channel = cfg.channel
    end
    if cfg.diff ~= nil then
        g_diff = cfg.diff
    end
    -- 更新 PGA 增益与满量程
    if cfg.pga ~= nil then
        g_pga_code = pga_to_code(cfg.pga)
        g_fs = PGA_FS_LIST[g_pga_code + 1]
    end
    -- 更新数据速率
    if cfg.sps ~= nil then
        g_sps_code = sps_to_code(cfg.sps)
        g_sps = SPS_LIST[g_sps_code + 1]
    end
    -- 更新工作模式
    if cfg.mode ~= nil then
        g_mode = (cfg.mode == 0) and 0 or 1
    end
    -- 重写配置并读回校验（不启动转换）
    return write_config_checked(0)
end

--[[
设置比较器低阈值与高阈值（输入电压值，单位 V），内部自动换算为 16 位补码写入芯片
电压低于 lo_v 或高于 hi_v 时 ALERT/RDY 引脚触发报警
@api exs_ads1115.set_threshold(lo_v, hi_v)
@param number lo_v
参数含义：比较器低阈值
数据类型：number
取值范围：-FS ~ +FS，单位 V，精度 1LSB 对应 FS/32768
是否必选：是
注意事项：需小于 hi_v；超过满量程的值自动钳位
参数示例：2.0
@param number hi_v
参数含义：比较器高阈值
数据类型：number
取值范围：-FS ~ +FS，单位 V，精度 1LSB 对应 FS/32768
是否必选：是
注意事项：需大于 lo_v；超过满量程的值自动钳位
参数示例：3.0
@return boolean
含义说明：阈值设置是否成功
数据类型：boolean
取值范围：true（成功）/ false（失败）
]]
function exs_ads1115.set_threshold(lo_v, hi_v)
    if not g_ready then
        log.warn("exs_ads1115", "未初始化，请先调用 setup()")
        return false
    end
    -- 电压 → 16 位补码
    local lo_code = volt_to_code(lo_v)
    local hi_code = volt_to_code(hi_v)
    -- 写低阈值寄存器（指针 0x02）
    if not write_reg(REG_LO_THRESH, (lo_code >> 8) & 0xFF, lo_code & 0xFF) then
        return false
    end
    -- 写高阈值寄存器（指针 0x03）
    if not write_reg(REG_HI_THRESH, (hi_code >> 8) & 0xFF, hi_code & 0xFF) then
        return false
    end
    log.info("exs_ads1115", "设置阈值", lo_v, hi_v)
    return true
end

--[[
配置比较器工作模式、连续触发次数与锁存行为，控制 ALERT/RDY 引脚输出方式
@api exs_ads1115.set_comparator(mode, queue, latch)
@param number mode
参数含义：比较器工作模式
数据类型：number
取值范围：0（传统模式，超过高阈值报警，回落到低阈值以下恢复）
         / 1（窗口模式，超过高阈值或低于低阈值都报警）
是否必选：否
注意事项：默认 0（传统模式）
参数示例：0
@param number queue
参数含义：连续触发次数
数据类型：number
取值范围：0（1 次超限即报警）/ 1（连续 2 次）/ 2（连续 4 次）
是否必选：否
注意事项：次数越多抗毛刺能力越强，默认 0
参数示例：0
@param boolean latch
参数含义：是否锁存报警
数据类型：boolean
取值范围：false（不锁存，信号恢复后自动解除报警）
         / true（锁存，需读取数据后清除）
是否必选：否
注意事项：默认 false；使用锁存模式时，中断回调中调用 get_data() 即可清除报警
参数示例：true
@return boolean
含义说明：比较器配置是否成功
数据类型：boolean
取值范围：true（成功）/ false（失败）
]]
function exs_ads1115.set_comparator(mode, queue, latch)
    if not g_ready then
        log.warn("exs_ads1115", "未初始化，请先调用 setup()")
        return false
    end
    g_comp_mode = mode or 0
    g_comp_queue = queue or 0
    g_comp_lat = (latch == true) and 1 or 0
    -- 重写配置使比较器设置生效（不启动转换）
    return write_config_checked(0)
end

--[[
查询 ALERT/RDY 引脚当前电平状态，判断比较器是否处于报警状态
需要 setup 时传入 config.alert_pin 指定引脚编号
@api exs_ads1115.get_alert()
@return number/nil
含义说明：引脚电平状态，0=报警触发（低电平），1=正常（高电平）；未配置 alert_pin 时返回 nil
数据类型：number 或 nil
]]
function exs_ads1115.get_alert()
    if not g_ready or not g_alert_pin then
        return nil
    end
    return gpio.get(g_alert_pin)  -- ALERT 默认低有效：低电平表示报警
end

--[[
设置零偏校准值（单位 V），补偿芯片失调误差，实际电压 = 测量电压 - offset
@api exs_ads1115.set_offset(value)
@param number value
参数含义：零偏校准值
数据类型：number
取值范围：-FS/32768 ~ FS/32768，单位 V，精度 1LSB 对应 FS/32768
是否必选：是
注意事项：将输入端短接（电压为 0）后读取数据，取读数的相反数作为 offset
参数示例：0.001
@return boolean
含义说明：校准值设置是否成功
数据类型：boolean
取值范围：true（成功）/ false（失败）
]]
function exs_ads1115.set_offset(value)
    if not g_ready then
        log.warn("exs_ads1115", "未初始化，请先调用 setup()")
        return false
    end
    g_offset = value or 0
    return true
end

--[[
设置增益校准系数，补偿芯片增益误差（0.01%~0.15%），实际电压 = (测量电压 - offset) × gain
@api exs_ads1115.set_gain(value)
@param number value
参数含义：增益校准系数
数据类型：number
取值范围：0.9 ~ 1.1，精度 0.0001
是否必选：是
注意事项：输入已知精密电压 Vref 后，gain = Vref / 测量电压；默认 1.0
参数示例：1.001
@return boolean
含义说明：校准值设置是否成功
数据类型：boolean
取值范围：true（成功）/ false（失败）
]]
function exs_ads1115.set_gain(value)
    if not g_ready then
        log.warn("exs_ads1115", "未初始化，请先调用 setup()")
        return false
    end
    g_gain = value or 1
    return true
end

--[[
关闭 ADS1115，释放 I2C 资源（软件 I2C 无需手动关闭）
@api exs_ads1115.close()
@return 无
]]
function exs_ads1115.close()
    if not g_ready then
        return
    end
    if not g_is_soft then
        i2c.close(g_i2c_id)  -- 释放硬件 I2C 总线
    end
    g_ready = false
    g_i2c_id = nil
    g_addr = nil
    g_alert_pin = nil
    log.info("exs_ads1115", "已关闭")
end

--[[
获取扩展库版本号
@api exs_ads1115.version()
@return string
含义说明：扩展库版本号，格式 yyyymmddhhmm
数据类型：string
]]
function exs_ads1115.version()
    return "202608241540"
end

return exs_ads1115
