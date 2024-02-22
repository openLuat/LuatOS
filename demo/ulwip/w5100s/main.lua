
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ulwip"
VERSION = "1.0.0"

--[[
本demo是尝试对接W5100

W5100的文档
https://www.wiznet.io/wp-content/uploads/wiznethome/Chip/W5100/Document/W5100_DS_V128E.pdf
https://d1.amobbs.com/bbs_upload782111/files_29/ourdev_555431.pdf

接线方式:
1. 5V -> VCC
2. GND -> GND
3. SCK -> PB05
4. MISO -> PB06
5. MOSI -> PB07
6. CS -> PB04

本demo的现状:
1. 一定要为W5100s稳定供电
2. 确保w5100s与模块的物理连接是可靠的
3. 当前使用轮询方式读取W5100s的状态, 未使用中断模式
]]

-- sys库是标配
_G.sys = require("sys")
require "sysplus"

SPI_ID = 0
spi.setup(SPI_ID, nil, 0, 0, 8, 1*1000*1000)
PIN_CS = gpio.setup(pin.PB04, 1, gpio.PULLUP)

TAG = "w5100s"
local mac = "0C1234567890"
local adapter_index = socket.LWIP_ETH

tx_queue = {}

-- 封装写入函数, w5100s的格式是32bit一次写入, 有效数据仅1个字节
function w5xxx_write(addr, data)
    for i=1, #data do
        PIN_CS(0)
        local data = string.char(0xF0, (addr & 0xFF00) >> 8, addr & 0x00FF, data:byte(i))
        spi.send(SPI_ID, data)
        addr = addr + 1
        PIN_CS(1)
    end
    
end

-- 封装读取函数, w5100s的格式是32bit一次读取, 有效数据仅1个字节
function w5xxx_read(addr, len)
    local result = ""
    for i=1, len do
        PIN_CS(0)
        local data = string.char(0x0F, (addr & 0xFF00) >> 8, addr & 0x00FF)
        spi.send(SPI_ID, data)
        --log.info("发送读取命令", data:toHex())
        result = result .. spi.recv(SPI_ID, 1)
        addr = addr + 1
        PIN_CS(1)
    end
    return result
end

-- 读取16bit的无符号整数
local function read_UINT16(addr)
    local data = w5xxx_read(addr, 2)
    -- log.info(TAG, "读取寄存器", string.format("0x%04X", addr), data:toHex())
    if #data ~= 2 then
        log.error(TAG, "读取寄存器失败", string.format("0x%0x4", addr))
        return 0
    end
    local ival = data:byte(1) *256 + data:byte(2)
    return ival
end

-- 写入16bit的无符号整数
local function write_UINT16(addr, val)
    local data = pack.pack(">H", val)
    -- log.info(TAG, "写入寄存器", string.format("0x%04X", addr), data:toHex())
    w5xxx_write(addr, data)
end

-- 打印common registers的数据
function print_CR(data)
    -- 当前模式
    local mode = data:byte(1)
    log.info("当前模式", mode)
    -- Source Hardware Address. 应该是MAC地址
    local mac = data:sub(0x0A, 0x0F)
    log.info("源MAC地址", mac:toHex())

    -- Interrupt Register
    local irq = data:byte(0x15 + 1)
    log.info("中断状态", irq)

    -- RX Memory Size
    local rx_mem = data:byte(0x1A + 1)
    log.info("RX内存大小", rx_mem >> 6, (rx_mem >> 4) & 0x3, (rx_mem >> 2) & 0x3, rx_mem & 0x3)
    -- TX Memory Size
    local tx_mem = data:byte(0x1B + 1)
    log.info("TX内存大小", tx_mem >> 6, (tx_mem >> 4) & 0x3, (tx_mem >> 2) & 0x3, tx_mem & 0x3)
end

-- 设置mac地址
function w5xxx_set_mac(mac)
    w5xxx_write(0x09, mac)
end

-- 读取接收到的数据, 从缓冲区取
function w5xxx_read_data(len, update_mark)
    -- 先读取数据长度
    -- local data = w5xxx_read(0x0426, 2)
    local remain_size = read_UINT16(0x0426)
    -- 读取指针位置
    -- data = w5xxx_read(0x0428, 2)
    local rx_offset = read_UINT16(0x0428) & 0x1FFF
    -- log.info(TAG, "RX寄存器状态", "剩余待读", remain_size, "偏移量", string.format("0x%04X", rx_offset))

    if len > remain_size then
        log.info("请求读取的长度大于剩余长度", len, remain_size)
        len = remain_size
        -- return
    end
    local data = ""
    if rx_offset + len > 0x2000 then
        -- 需要环形读取了
        local data1 = w5xxx_read(0x6000 + rx_offset, 0x2000 - rx_offset)
        local data2 = w5xxx_read(0x6000, len - #data1)
        data = data1 .. data2
    else
        data = w5xxx_read(0x6000 + rx_offset, len)
    end
    -- 更新读取指针位置
    if update_mark then
        local t = (read_UINT16(0x0428) + len)
        -- log.info(TAG, "回写指针偏移量", string.format("0x%04X", t))
        w5xxx_write(0x0428, string.char((t & 0xFF00) >> 8, t & 0xFF))
        -- 告知已经读取完毕
        w5xxx_write(0x0401, string.char(0x40))
    end
    return data
end

-- 写入数据到发送缓冲区,并执行发送
function w5xxx_write_data(data)
    -- 首先, 读取指针位置
    local tx_offset = read_UINT16(0x0422) & 0x1FFF
    log.info(TAG, "TX寄存器状态", "剩余可写", read_UINT16(0x0420), "偏移量", string.format("0x%04X", tx_offset))

    -- data = string.char(#data >>8, #data & 0xFF) .. data
    if tx_offset + #data > 0x2000 then
        -- 需要环形写入
        w5xxx_write(0x4000 + tx_offset, data:sub(1, 0x2000 - tx_offset))
        w5xxx_write(0x4000, data:sub(0x2000 - tx_offset + 1))
    else
        w5xxx_write(0x4000 + tx_offset, data)
    end
    -- 更新读取指针位置
    -- log.info(TAG, "当前TX指针偏移量", string.format("0x%04X", read_UINT16(0x0424)), "数据长度", #data)
    local t = read_UINT16(0x0424) + #data
    -- log.info(TAG, "目标TX指针偏移量", string.format("0x%04X", t))
    -- w5xxx_write(0x0424, string.char((t & 0xFF00) >> 8, t & 0xFF))
    write_UINT16(0x0424, t)
    -- 校验一下, 读取RR/WR值, 并算出差值(发送长度)
    -- local tx_start = read_UINT16(0x0422)
    -- local tx_end = read_UINT16(0x0424)
    -- log.info(TAG, "TX寄存器状态", "开始指针", tx_start, "结束指针", tx_end, "差值", (tx_end - tx_start) & 0x1FFF, #data)
    -- 告知已经写入完毕
    w5xxx_write(0x0401, string.char(0x20))
end

-- 对接ulwip库的link out
function netif_write_out(adapter_index, data)
    -- log.info(TAG, "待发送mac数据", data:toHex())
    table.insert(tx_queue, data)
end

sys.taskInit(function()
    sys.wait(1000)
    if wlan and wlan.init then
        wlan.init()
    end
    ---------------------------
    log.info(TAG, "w5100开始搞")
    w5xxx_write(0x0, string.char(0x80))
    w5xxx_read(0x00, 0x10)
    sys.wait(200)
    local data = w5xxx_read(0x00, 0x30)
    log.info(TAG, "w5xxx_read", data:toHex())
    print_CR(data)
    if #data == 0 then
        log.info("w5100通信失败!!!")
        return
    end

    -- 设置模式为全关闭
    -- local mode = w5xxx_read(0x0, 1)
    -- log.info(TAG, "MR,设置前", mode:toHex())
    -- w5xxx_write(0x0, string.char(0x0))
    -- mode = w5xxx_read(0x0, 1)
    -- log.info(TAG, "MR,设置后", mode:toHex())

    -- 写入MAC地址
    log.info(TAG, "写入MAC地址", mac)
    w5xxx_set_mac((mac:fromHex()))

    -- 设置TX/RX的缓冲区大小
    w5xxx_write(0x1A, string.char(0x03)) -- 全部给S0, 8kb
    w5xxx_write(0x1B, string.char(0x03)) -- 全部给S0, 8kb

    -- 再次读取通用寄存器的数据
    data = w5xxx_read(0x00, 0x30)
    log.info(TAG, "w5xxx_read", data:toHex())
    print_CR(data)

    -- 将S0设置为MACRAW模式
    w5xxx_write(0x0400, string.char(0x04 | 0x40))
    -- sys.wait(100)
    -- w5xxx_write(0x0402, string.char(0x01))
    -- 开启数据收发
    w5xxx_write(0x0401, string.char(0x01))
    sys.wait(100)
    w5xxx_write(0x0402, string.char(0x01))
    sys.wait(100)

    sys.publish("w5100_ready")

    while 1 do

        -- 处理接收队列
        local rx_size = read_UINT16(0x0426)
        --log.info(TAG, "待接收数据长度", rx_size)
        if rx_size > 0 then
            data = w5xxx_read_data(2)
            local frame_size = data:byte(1) * 256 + data:byte(2)
            if frame_size < 60 or frame_size > 1600 then
                log.info(TAG, "MAC帧大小异常", frame_size)
                w5xxx_read_data(frame_size, 8192) -- 全部废弃
            else
                -- log.info(TAG, "MAC帧大小", frame_size - 2)
                local mac_frame = w5xxx_read_data(frame_size, true)
                if mac_frame then
                    -- log.info(TAG, "MAC帧数据(含2字节头部)",  mac_frame:toHex())
                    ulwip.input(adapter_index, mac_frame:sub(3))
                end
            end
        end

        -- 处理发送队列
        if #tx_queue > 0 then
            local send_buff_remain = read_UINT16(0x0420)
            local tmpdata = tx_queue[1]
            log.info(TAG, "发送队列", #tx_queue, #tmpdata, send_buff_remain)
            if send_buff_remain >= #tmpdata then
                tmpdata = table.remove(tx_queue, 1)
                w5xxx_write_data(tmpdata)
                sys.wait(5)
            end
        end

        -- 有没有待接收的数据呢
        rx_size = read_UINT16(0x0426)
        if rx_size == 0 and #tx_queue == 0 then
            sys.wait(20)
        else
            sys.wait(5)
        end
        --sys.wait(100)
    end

    log.info("结束了..............")
end)

sys.taskInit(function()
    sys.waitUntil("w5100_ready")
    log.info("适配器索引是啥", adapter_index)

    -- local mac = string.fromHex("0C1456060177")
    local ret = ulwip.setup(adapter_index, string.fromHex(mac), netif_write_out)
    log.info("ulwip.setup", ret)
    if ret then
        ulwip.reg(adapter_index)
        log.info("ulwip", "添加成功, 设置设备就绪")
        ulwip.updown(adapter_index, true)
        log.info("ulwip", "启动dhcp")
        ulwip.dhcp(adapter_index, true)
        -- ulwip.ip(adapter_index, "192.168.1.199", "255.255.255.0", "192.168.1.1")
        sys.wait(100)
        log.info("ulwip", "设置设备已经在线")
        ulwip.link(adapter_index, true)
        while ulwip.ip(adapter_index) == "0.0.0.0" do
            sys.wait(1000)
            log.info("等待IP就绪")
        end
        log.info("ulwip", "IP地址", ulwip.ip(adapter_index))
        -- 为了能正常访问外网, 需要把该网卡设置为默认路由
        ulwip.dft(adapter_index)
        -- sys.publish("net_ready")
        sys.wait(1000)
        log.info("发起http请求")
        local code, headers, body = http.request("GET", "http://httpbin.air32.cn/get", nil, nil, {adapter=adapter_index, timeout=5000, debug=true}).wait()
        -- local code, headers, body = http.request("GET", "http://192.168.1.6:8000/get", nil, nil, {adapter=adapter_index, timeout=5000, debug=true}).wait()
        log.info("ulwip", "http", code, json.encode(headers or {}), body)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
