-- SPI接口TF卡和WAN口复用演示项目
-- 项目功能：
-- 1. 演示Air8000开发板上SPI1接口复用，同时支持TF卡存储和CH390网络芯片
-- 2. TF卡功能：文件读写操作、启动次数记录、状态日志保存
-- 3. WAN口功能：通过CH390芯片提供以太网连接，支持DHCP自动获取IP
-- 4. 网络测试：定期进行HTTP请求测试，验证网络连通性
-- 5. 状态监控：实时监控TF卡和网络状态，记录运行日志
-- 
-- 硬件配置：
-- - SPI1: 复用接口，连接TF卡和CH390
-- - GPIO20: TF卡片选引脚
-- - GPIO12: CH390片选引脚  
-- - GPIO140: CH390供电控制引脚
-- - SPI速度: 12.8MHz（兼容TF卡和CH390的统一速度）
PROJECT = "spi_tf_wan"
VERSION = "1.0.0"
-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

local rtos_bsp = rtos.bsp()

local USE_CH390 = true  -- 使用ch390时，设置为true，否则为false
local SPI_SPEED = 25600000

-- if USE_CH390 then
--     gpio.setup(140, 1, gpio.PULLUP)  -- 打开ch390供电
-- end

-- spi_id,pin_cs
local function fatfs_spi_pin()     
    return 1, 20    -- Air8000整机开发板上的pin_cs为gpio20
end

-- TF卡和WAN口初始化函数
local function tf_wan_init()
    gpio.setup(140, 1, gpio.PULLUP)  -- 打开ch390供电
    sys.wait(1000)
    
    -- #################################################
    -- 首先初始化TF卡
    -- #################################################
    log.info("tf_wan", "开始初始化TF卡")
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因

    -- 此为spi方式
    local spi_id, pin_cs,tp = fatfs_spi_pin() 
    -- 仅SPI方式需要自行初始化spi, sdio不需要
    -- 使用较低的统一速度以兼容TF卡和CH390
    spi.setup(spi_id, nil, 0, 0, pin_cs, SPI_SPEED)
    gpio.setup(pin_cs, 1)
    fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, SPI_SPEED)

    local data, err = fatfs.getfree("/sd")
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end

    -- #################################################
    -- 文件操作测试
    -- #################################################
    local f = io.open("/sd/boottime", "rb")
    local c = 0
    if f then
        local data = f:read("*a")
        log.info("fs", "data", data, data:toHex())
        c = tonumber(data)
        f:close()
    end
    log.info("fs", "boot count", c)
    if c == nil then
        c = 0
    end
    c = c + 1
    f = io.open("/sd/boottime", "wb")
    if f ~= nil then
        log.info("fs", "write c to file", c, tostring(c))
        f:write(tostring(c))
        f:close()
    else
        log.warn("sdio", "mount not good?!")
    end
    if fs then
        log.info("fsstat", fs.fsstat("/"))
        log.info("fsstat", fs.fsstat("/sd"))
    end

    -- 测试一下追加, fix in 2021.12.21
    os.remove("/sd/test_a")
    sys.wait(50)
    f = io.open("/sd/test_a", "w")
    if f then
        f:write("ABC")
        f:close()
    end
    f = io.open("/sd/test_a", "a+")
    if f then
        f:write("def")
        f:close()
    end
    f = io.open("/sd/test_a", "r")
    if  f then
        local data = f:read("*a")
        log.info("data", data, data == "ABCdef")
        f:close()
    end

    -- 测试一下按行读取, fix in 2022-01-16
    f = io.open("/sd/testline", "w")
    if f then
        f:write("abc\n")
        f:write("123\n")
        f:write("wendal\n")
        f:close()
    end
    sys.wait(100)
    f = io.open("/sd/testline", "r")
    if f then
        log.info("sdio", "line1", f:read("*l"))
        log.info("sdio", "line2", f:read("*l"))
        log.info("sdio", "line3", f:read("*l"))
        f:close()
    end
    
    log.info("tf_wan", "TF卡初始化完成")
    
    -- #################################################
    -- 然后初始化WAN口
    -- #################################################
    log.info("tf_wan", "开始初始化WAN口")
    sys.wait(500)

    -- 初始化指定netdrv设备,
    -- socket.LWIP_ETH 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 1, 片选 GPIO12
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=1,cs=12})
    netdrv.dhcp(socket.LWIP_ETH, true)
    
    log.info("tf_wan", "WAN口初始化完成")
end

-- 初始化TF卡和WAN口
sys.taskInit(tf_wan_init)

-- 网络和TF卡状态监控，包含文件读写和网络通信
local function status_monitor()
    local boot_count = 0
    
    while true do
        sys.wait(1000)  -- 每1秒检查一次
        
        local status_info = {}
        
        -- 检查WAN口状态
        local wan_link = netdrv.link(socket.LWIP_ETH)
        local wan_ready = netdrv.ready(socket.LWIP_ETH)
        table.insert(status_info, string.format("WAN: link=%s ready=%s", tostring(wan_link), tostring(wan_ready)))
        
        -- 检查TF卡状态并进行文件读写操作
        local tf_status = "未知"
        local data, err = fatfs.getfree("/sd")
        if data then
            tf_status = "正常"
            
            -- 读取启动次数文件
            local f = io.open("/sd/boottime", "rb")
            if f then
                local count_data = f:read("*a")
                boot_count = tonumber(count_data) or 0
                f:close()
            end
            boot_count = boot_count + 1
            
            -- 写入新的启动次数
            f = io.open("/sd/boottime", "wb")
            if f then
                f:write(tostring(boot_count))
                f:close()
                log.info("文件操作", "启动次数已更新:", boot_count)
            end
            
            -- 写入状态日志文件
            local timestamp = os.date("%Y-%m-%d %H:%M:%S")
            local status_log = string.format("[%s] %s\n", timestamp, table.concat(status_info, ", "))
            f = io.open("/sd/status.log", "ab")
            if f then
                f:write(status_log)
                f:close()
            end
        else
            tf_status = "异常"
        end
        table.insert(status_info, string.format("TF卡: %s (启动次数: %d)", tf_status, boot_count))
        
        log.info("状态", table.concat(status_info, ", "))
        
        -- WAN口网络通信测试
        if wan_ready then
            log.info("网络测试", "开始WAN口网络通信测试")
            local code, headers, body = http.request("GET", "http://httpbin.air32.cn/get", nil, nil, {adapter=socket.LWIP_ETH}).wait()
            if code == 200 then
                -- 将网络测试结果写入TF卡
                if tf_status == "正常" then
                    local f = io.open("/sd/network_test.log", "ab")
                    if f then
                        local test_log = string.format("[%s] WAN HTTP测试成功, 响应码: %d\n", os.date("%Y-%m-%d %H:%M:%S"), code)
                        log.info("网络测试", "WAN口HTTP请求成功, 响应码:", code)
                        f:write(test_log)
                        f:close()
                    end
                end
            else
                log.info("网络测试", "WAN口HTTP请求失败, 响应码:", code)
            end
        end
        
        -- 输出内存使用情况
        log.info("内存", "Lua:", rtos.meminfo())
        log.info("内存", "Sys:", rtos.meminfo("sys"))
    end
end

-- 启动状态监控任务
sys.taskInit(status_monitor)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
