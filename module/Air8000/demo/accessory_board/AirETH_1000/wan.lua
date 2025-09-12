--[[
@module  wan
@summary wan 以太网提供网络供模组上网
@version 1.0
@date    2025.09.12
@author  王城钧
@usage
本文件为lan网络模块，核心业务逻辑为：
1.以太网提供网络供模组上网
2.http测试以太网网络
本文件没有对外接口，直接在main.lua中require "wan"就可以加载运行；
]]

-- 启动WAN网络初始化
local function wan_init()
    sys.wait(500)                   --等待500ms，此延时非必须
    log.info("ch390", "打开LDO供电")
    gpio.setup(140, 1, gpio.PULLUP) --打开ch390供电
    sys.wait(6000)                  --等待6000ms，此延时非必须
    local result = spi.setup(
        1,                          --spi_id
        nil,
        0,                          --CPHA
        0,                          --CPOL
        8,                          --数据宽度
        25600000                    --,--频率
    -- spi.MSB,--高低位顺序    可选，默认高位在前
    -- spi.master,--主模式     可选，默认主
    -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "open", result)
    if result ~= 0 then --返回值为0，表示打开成功
        log.info("main", "spi open error", result)
        return
    end
    -- 初始化指定netdrv设备,
    -- socket.LWIP_ETH 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 1, 片选 GPIO12
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, { spi = 1, cs = 12 })
    netdrv.dhcp(socket.LWIP_ETH, true)
end

-- WAN网络测试任务
local function wan_task()
    -- sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(6000)    --非必须延时，只是为了方便观察日志输出                                                                                                      -- 此处延时非必须，只是为了方便观察日志输出
        log.info("http",
            http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil, { adapter = socket.LWIP_ETH }).wait())          --adapter指定为以太网联网方式
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end

-- 启动WAN网络初始化和任务
sys.taskInit(wan_init)

-- 启动WAN联网测试
sys.taskInit(wan_task)
