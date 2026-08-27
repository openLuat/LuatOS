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
        -- 1601的话初始化以太网
        if hmeta.model() == "Air1601" or hmeta.model() == "Air1602" then
            log.info("netready_1601", "使用以太网，开始初始化")
            local result = spi.setup(1, -- spi_id
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
                spi = 1,
                cs = 14
            })
            sys.wait(1000) -- 等待以太网模块初始化完成,去掉会导致以太网初始化失败
            netdrv.dhcp(socket.LWIP_ETH, true)
            log.info("LWIP_ETH", "mac addr", netdrv.mac(socket.LWIP_ETH))
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
