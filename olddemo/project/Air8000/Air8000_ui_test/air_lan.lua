local air_lan = {}
local test_type = "lan_test"
dhcps = require "dhcpsrv"
dnsproxy = require "dnsproxy"

--[[
@brief 初始化LAN网络功能
@description
1. 初始化CH390芯片供电和SPI通信
2. 配置网络适配器参数
3. 设置IPv4地址和子网掩码
4. 等待网络连接就绪
5. 创建DHCP服务器和DNS代理
6. 可选启动iperf服务器
@return air_lan 返回air_lan对象
]]
function air_lan.run_tests()
    sys.wait(500)
    log.info("ch390", "打开LDO供电")
    gpio.setup(140, 1, gpio.PULLUP) -- 打开ch390供电
    lcd.clear()
    log.info("lan测试开始")
    lcd.drawStr(50, 50, "lan测试开始")
    sys.wait(6000)
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
        cs = 12
    })
    sys.wait(3000)
    local ipv4, mark, gw = netdrv.ipv4(socket.LWIP_ETH, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    log.info(" lan ipv4", ipv4, mark, gw)

    local cunt = 1
    while netdrv.link(socket.LWIP_ETH) ~= true and cunt < 10 do
        log.info("lan ", "没联网成功 尝试重连第" .. cunt .. "次")
        lcd.clear()
        lcd.drawStr(50, 50, "没联网成功 尝试重连第" .. cunt .. "次")
        cunt = cunt + 1
        sys.wait(1000)
    end

    sys.wait(2000)
    dhcps.create({
        adapter = socket.LWIP_ETH
    })

    if iperf then
        log.info("启动iperf服务器端")
          lcd.clear()
        lcd.drawStr(50, 50, "启动iperf服务器端")
        iperf.server(socket.LWIP_ETH)
    end
    log.info("lan 执行到61行")
    local isReady, default = socket.adapter(socket.LWIP_ETH)
    local test_mode, test_end, failing_res, pass, failing_item = "", "", "", false, ""
    log.info("lan 执行到64行")
    if isReady then
        test_mode = "测试项目通过"
        test_end = "pass"
        pass = "pass"
        log.info(test_type, test_mode)

    else
        test_mode = "测试项目未通过"
        test_end = "fail"
        pass = "fail"
        failing_res = "CH390联网未成功"
        failing_item = "lan"
        log.info(test_type, test_mode)

    end
    log.info("lan 执行到80行")
    local data = {
        type = test_type,
        test_mode = test_mode,
        test_end = pass or failing_item,
        fail_res =  failing_res,
        imei = mobile.imei()
    }
      lcd.clear()
        lcd.drawStr(50, 50, "lan测试结束")
        lcd.drawStr(50, 70, "测试结果：" .. pass or failing_res)
        if pass =="fail" then
            lcd.drawStr(50, 90, "失败的原因是:" .. failing_res)
        end
    local data = json.encode(data)
    log.info("lan 准备给服务器发消息", data)
    sys.publish("OTHER_FILE_SENDMSG", data)

end

return air_lan
