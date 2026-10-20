local ctx_path = "/luadb/ctx.json"

local netready = {}

local wifi_en = gpio.setup(12, 0)
local uartid = 3

local function config_uart_gpio_input()
    -- 将串口对应的gpio设置为输入拉低模式
    gpio.setup(22, nil, gpio.PULLDOWN)
    gpio.setup(23, nil, gpio.PULLDOWN)
end

local function config_uart_gpio_close()
    -- 关闭串口对应的GPIO 引脚功能
    gpio.close(22)
    gpio.close(23)
end

local function uart_setup()
    config_uart_gpio_input()
    local uart_id = 3
    sys.wait(1000)
    wifi_en(1) -- 拉高wifi使能gpio
    sys.wait(1000)
    config_uart_gpio_close()
    uart.setup(uart_id, 2000000, 8, 1, uart.None, uart.LSB, 2048)
end

local spi_id = 0
-- 片选引脚
local spi_cs = 8
-- 数据宽度
local spi_databits = 8
-- CPHA
local spi_cpha = 0
-- CPOL
local spi_cpol = 0
-- 时钟速率
local spi_speed = 30*1000*1000
-- 以下三项留空即用驱动默认值(高位在前/主模式/全双工)
local spi_bit_order = nil
local spi_mode = nil
local spi_communication = nil
if rtos.bsp() == "Air1601" or rtos.bsp() == "Air1602" then
    spi_id = 1
    spi_cs = 14
    spi_irq = 51
else
    gpio.setup(20, 1, gpio.PULLUP) -- 打开CH390H LDO供电
end


-- Air1601/1602: 外挂 CH390 以太网 (SPI1 + CS14)。
-- 原来 netready 只在"mobile 不存在"的构建里初始化 CH390, Air1601/1602 都编了
-- mobile, 所以那段是死代码; 这里提到前面统一初始化, 并用 ch390_inited 兜住,
-- 避免在无 mobile 的构建里被下面的历史副本重复初始化。
local ch390_inited = false

local function ch390_setup()
    if ch390_inited then
        return
    end
    ch390_inited = true
    local result = spi.setup(spi_id, nil, spi_cpha, spi_cpol, spi_databits, spi_speed, spi_bit_order, spi_mode, spi_communication)
    log.info("netready_1601", "spi open", result)
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {
        spi = spi_id,
        cs = spi_cs,
        -- irq = spi_irq
    })
    sys.wait(1000) -- 等待以太网模块初始化完成,去掉会导致以太网初始化失败
    netdrv.dhcp(socket.LWIP_ETH, true)
    log.info("LWIP_ETH", "mac addr", netdrv.mac(socket.LWIP_ETH))
    -- L2TP/OpenVPN 这类隧道在 setup 时把"当前默认网卡"记为外层传输网卡,
    -- 不钉住的话可能从 4G/WiFi 出去而不是以太网
    socket.dft(socket.LWIP_ETH)
end

function netready.exec(ctx, timeout)
    local model = hmeta.model()
    log.info("hmeta.model()", model)
    local no_sim = mobile == nil or mobile.simPin == nil
    if no_sim and (model == "Air780EPM" or model == "Air780EHM") then
        pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
        gpio.setup(20, 1)
        log.info("netready_1780", "使用以太网，开始初始化")
        local result = spi.setup(0, -- spi_id
        nil, 0, -- CPHA
        0, -- CPOL
        8, -- 数据宽度
        25600000 -- ,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
        )
        log.info("main", "open", result)
        if result ~= 0 then -- 返回值为0，表示打开成功
            log.info("main", "spi open error", result)
            return
        end
        -- 初始化指定netdrv设备,
        -- socket.LWIP_ETH 网络适配器编号
        -- netdrv.CH390外挂CH390
        -- SPI ID 1, 片选 GPIO12
        netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {
            spi = 0,
            cs = 8
        })
        sys.wait(1000) -- 等待以太网模块初始化完成,去掉会导致以太网初始化失败
        netdrv.dhcp(socket.LWIP_ETH, true)
        log.info("LWIP_ETH", "mac addr", netdrv.mac(socket.LWIP_ETH))
        socket.dft(socket.LWIP_ETH)
        return
    end
    -- -- 1602使用airlink连接wifi
    if hmeta.model() == "Air1602" then
        -- wifi_en(1) 
        -- log.info("netready_1602", "使用 AirLink SPI 连接 WiFi，开始初始化")
        -- airlink.config(airlink.CONF_SPI_ID, 1) -- SPI1
        -- airlink.config(airlink.CONF_SPI_CS, 29) -- GPIO PA_29
        -- airlink.config(airlink.CONF_SPI_RDY, 8) -- GPIO PA_08
        -- airlink.config(airlink.CONF_SPI_SPEED, 8 * 1000000) -- 8MHz速度
        -- netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
        -- netdrv.setup(socket.LWIP_AP, netdrv.WHALE)
        -- airlink.start(airlink.MODE_SPI_MASTER)
        -- sys.wait(1000)

        -- uart_setup()
        -- airlink.init() -- 初始化airlink
        -- airlink.config(airlink.CONF_UART_ID, uartid) -- 配置airlink的串口3

        -- netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
        -- netdrv.setup(socket.LWIP_AP, netdrv.WHALE)

        -- airlink.start(airlink.MODE_UART) -- 启动airlink的串口模式
        -- sys.wait(100)
    end
    if hmeta.model() == "Air1601" then
        ch390_setup()
    end
    -- 应该 根据 型号和上下文, 进行联网操作
    if mobile then
        -- 什么都不做
        log.info("netready", "使用移动网络，无需初始化")
        if rtos.bsp() == "Air8000" then
            log.info("netready", "使用 WiFi 网络开始初始化")
            local ssid = ctx.wifi_ssid
            local password = ctx.wifi_password
            wlan.init()
            wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
            wlan.connect(ssid, password, 1)
        end
    elseif wlan and wlan.init and hmeta.model() ~= "Air1601" and hmeta.model() ~= "Air1602" then
        log.info("netready", "使用 WiFi 网络开始初始化")
        local ssid = ctx.wifi_ssid
        local password = ctx.wifi_password
        wlan.init()
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        wlan.connect(ssid, password, 1)
        log.info("wlan", "connect", ssid, password)
        socket.dft(socket.LWIP_STA)
    elseif socket then
        -- 1601/1602 的外挂以太网已在前面 ch390_setup() 里初始化过(带 ch390_inited 去重),
        -- 这里只是无 mobile 构建下的历史兜底路径
        if hmeta.model() == "Air1601" or hmeta.model() == "Air1602" then
            log.info("netready_1601", "使用以太网，开始初始化")
            ch390_setup()
        else
            -- 适配了socket库也OK, 就当1秒联网吧
            sys.timerStart(sys.publish, 1000, "IP_READY")
        end
    end
end

function netready.deinit()
    if mobile then
        mobile.flymode(0, true)
        log.info("netready", "使用移动网络，进入飞行模式")
    elseif wlan and wlan.disconnect and rtos.bsp() ~= "Air1601" then
        log.info("netready", "断开 WiFi 连接")
        wlan.disconnect()
    end
end

return netready
