local ctx_path = "/luadb/ctx.json"

local netready = {}
function netready.exec(ctx, timeout)
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
    elseif wlan and wlan.init and rtos.bsp() ~= "Air1601" then
        log.info("netready", "使用 WiFi 网络开始初始化")
        local ssid = ctx.wifi_ssid
        local password = ctx.wifi_password
        wlan.init()
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        wlan.connect(ssid, password, 1)
    elseif socket then
        -- 1601的话初始化以太网
        if rtos.bsp() == "Air1601" then
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
