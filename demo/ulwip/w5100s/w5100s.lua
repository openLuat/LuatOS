--[[
@module w5100s
@summary 集成wiznet w5100/w5200系列网卡驱动
@version 1.0
@date    2024.2.22
@author  wendal
@usage

local w5100s = require("w5100s")
spi_id = 1
spi.setup(spi_id, nil, 0, 0, 8, 1*1000*1000)
w5100s.init("w5100", {spi=spi_id, pin_cs=10, pin_int=nil})
]]
local w5100s = {}

--[[
硬件资料:
1. w5100s/w5100 https://www.w5100s.io/wp-content/uploads/w5100shome/Chip/W5100/Document/W5100_DS_V128E.pdf
2. w5200 https://www.w5100s.io/wp-content/uploads/w5100shome/Chip/W5200/Documents/W5200_DS_V140E.pdf

不同芯片之间的主要差异:
1. 通用缓冲区的长度不同, 但设置MAC的寄存器地址是一样的
2. 缓冲区总大小不同, 导致接收缓冲区的起始地址不同, 发送缓冲区的起始地址是相同的
3. LINK状态的寄存器位置有差异,但使用轮询式就不关注了

实现逻辑:
1. 初始化/复位芯片
2. 设置缓冲区大小,设置MAC,开启MACRAW模式
3. 轮询读取缓冲区和发送队列

错误检测:
1. 定时检测link状态,如果断掉则通知ulwip库
2. 定时检测新的当前模式是不是MACRAW,如果不是就重新初始化

TODO:
1. 控制txqueue的大小
2. 定时检测link状态,如果断掉则通知ulwip库
]]

local TAG = "w5100s"
w5100s.tx_queue = {}

function w5100s.init(tp, opts)
    -- buffsize 缓冲区大小, 型号相关

    if tp == "w5100" or tp == "w5100s" then
        opts.buffsize = 8192
    elseif tp == "w5200" then
        opts.buffsize = 16384
    else
        if not opts.buffsize then
            log.error(TAG, "型号未知且未定义缓冲区大小,无法初始化")
            return
        end
    end

    -- 检查必要的库是否存在ulwip/zbuff/spi/gpio
    if not ulwip or not zbuff or not spi or not gpio then
        log.error(TAG, "缺少必要的库: ulwip/zbuff/spi/gpio")
        return
    end
    -- CS脚必须有,可以是数字也可以是GPIO回调
    if not opts.pin_cs then
        log.error("TAG", "CS脚(pin_cs)必须定义")
        return
    elseif type(opts.pin_cs) == "number" then
        opts.pin_cs = gpio.setup(opts.pin_cs, 1, gpio.PULLUP)
    end
    -- 必须定义SPI,速度由客户自行定义
    if not opts.spi_id then
        log.error("TAG", "SPI(spi_id)必须定义")
        return
    end
    -- TODO 检测一下芯片是否存在

    w5100s.opts = opts
    w5100s.cmdbuff = zbuff.create(4)
    w5100s.rxbuff = zbuff.create(1600)
    return true
end

-- 对接硬件的函数
------------------------------------

-- 封装写入函数, w5100s的格式是32bit一次写入, 有效数据仅1个字节
local function w5xxx_write(addr, data)
    local cmdbuff = w5100s.cmdbuff
    for i=1, #data do
        cmdbuff[0] = 0xF0
        cmdbuff[1] = (addr & 0xFF00) >> 8
        cmdbuff[2] = addr & 0x00FF
        cmdbuff[3] = data:byte(i)
        cmdbuff:seek(0)
        w5100s.opts.pin_cs(0)
        -- local data = string.char(0xF0, (addr & 0xFF00) >> 8, addr & 0x00FF, data:byte(i))
        -- spi.send(SPI_ID, data)
        spi.send(SPI_ID, cmdbuff, 4)
        addr = addr + 1
        w5100s.opts.pin_cs(1)
    end
end

-- 封装读取函数, w5100s的格式是32bit一次读取, 有效数据仅1个字节
local function w5xxx_read(addr, len, rxbuff, offset)
    local result = ""
    local cmdbuff = w5100s.cmdbuff
    for i=1, len do
        cmdbuff[0] = 0x0F
        cmdbuff[1] = (addr & 0xFF00) >> 8
        cmdbuff[2] = addr & 0x00FF
        cmdbuff:seek(0)
        w5100s.opts.pin_cs(0)
        -- local data = string.char(0x0F, (addr & 0xFF00) >> 8, addr & 0x00FF)
        -- spi.send(SPI_ID, data)
        spi.send(SPI_ID, cmdbuff, 3)
        --log.info("发送读取命令", data:toHex())
        local ival = spi.recv(SPI_ID, 1)
        if rxbuff then
            rxbuff[offset + i - 1] = #ival == 1 and ival:byte(1) or 0
        else
            result = result .. ival
        end
        addr = addr + 1
        w5100s.opts.pin_cs(1)
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
local function print_CR(data)
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

-- 设置/读取mac地址
function w5100s.mac(mac)
    if mac then
        w5xxx_write(0x09, mac)
    end
    return w5xxx_read(0x09, 6)
end

-- 读取接收到的数据, 从缓冲区取
local function w5xxx_read_data(len, update_mark, rawmode)
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
    local rxbuff = w5100s.rxbuff
    if rx_offset + len > 0x2000 then
        -- 需要环形读取了
        -- local data1 = w5xxx_read(0x6000 + rx_offset, 0x2000 - rx_offset)
        -- local data2 = w5xxx_read(0x6000, len - #data1)
        -- data = data1 .. data2
        w5xxx_read(0x6000 + rx_offset, 0x2000 - rx_offset, rxbuff, 0)
        w5xxx_read(0x6000, len - (0x2000 - rx_offset), rxbuff, 0x2000 - rx_offset)
    else
        -- data = w5xxx_read(0x6000 + rx_offset, len)
        w5xxx_read(0x6000 + rx_offset, len, rxbuff, 0)
    end
    -- log.info(TAG, "读取数据", data:toHex())
    -- 更新读取指针位置
    if update_mark then
        local t = (read_UINT16(0x0428) + len)
        -- log.info(TAG, "回写指针偏移量", string.format("0x%04X", t))
        w5xxx_write(0x0428, string.char((t & 0xFF00) >> 8, t & 0xFF))
        -- 告知已经读取完毕
        w5xxx_write(0x0401, string.char(0x40))
    end
    if rawmode then
        return rxbuff
    end
    return rxbuff:toStr(0, len)
end

-- 写入数据到发送缓冲区,并执行发送
local function w5xxx_write_data(data)
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

function w5100s.ready()
    -- 起码要调用init才行呀
    if not w5100s.opts then
        log.info(TAG, "未初始化")
        return
    end
    -- 读取MACRAW状态
    local macraw = w5xxx_read(0x0403, 1)
    if not macraw or #macraw ~= 1 or macraw ~= "\x42" then
        log.info(TAG, "MACRAW状态异常", string.toHex(macraw or ""))
        return
    end
    -- 读MAC地址
    local mac = w5xxx_read(0x09, 6)
    if not mac or #mac ~= 6 or mac == "\0\0\0\0\0\0" then
        log.info(TAG, "MAC未设置")
        return
    end
    return true
end

--[[
获取link的状态
@api w5100s.link()
@return boolean 返回true表示已连接, false表示未连接或其他错误
]]
function w5100s.link()
    if not w5100s.opts then
        log.info(TAG, "未初始化")
        return
    end
    local pyh = w5xxx_read(0x003C, 1)
    if not pyh or #pyh ~= 1 or ((pyh:byte(1) & 0x80) ~= 0) then
        log.info(TAG, "PYH状态值", string.toHex(pyh or ""))
        return
    end
    return true
end

function w5100s.do_init()
    -- log.info(TAG, "w5100开始搞")
    w5xxx_write(0x0, string.char(0x80))
    --w5xxx_read(0x00, 0x10)
    sys.wait(200)
    local data = w5xxx_read(0x00, 0x30)
    -- log.info(TAG, "w5xxx_read", data:toHex())
    -- print_CR(data)
    if #data == 0 then
        log.info("w5100通信失败!!!")
        return
    end

    -- 写入MAC地址
    if w5100s.opts.mac then
        log.info(TAG, "写入MAC地址", w5100s.opts.mac)
        w5100s.mac(w5100s.opts.mac)
    end

    -- 设置TX/RX的缓冲区大小
    w5xxx_write(0x1A, string.char(0x03)) -- 全部给S0, 8kb
    w5xxx_write(0x1B, string.char(0x03)) -- 全部给S0, 8kb

    -- 再次读取通用寄存器的数据
    -- data = w5xxx_read(0x00, 0x30)
    -- log.info(TAG, "w5xxx_read", data:toHex())
    -- print_CR(data)

    -- 将S0设置为MACRAW模式
    w5xxx_write(0x0400, string.char(0x04 | 0x40))
    -- sys.wait(100)
    -- w5xxx_write(0x0402, string.char(0x01))
    -- 开启数据收发
    w5xxx_write(0x0401, string.char(0x01))
    -- sys.wait(100)
    w5xxx_write(0x0402, string.char(0x01))
    sys.wait(50)
end

local function one_time( )
    -- 处理接收队列
    local rx_size = read_UINT16(0x0426)
    --log.info(TAG, "待接收数据长度", rx_size)
    if rx_size > 0 then
        local data = w5xxx_read_data(2)
        local frame_size = data:byte(1) * 256 + data:byte(2)
        if frame_size < 60 or frame_size > 1600 then
            log.info(TAG, "MAC帧大小异常", frame_size, "强制复位芯片")
            -- w5xxx_read_data(frame_size, 1520) -- 全部废弃
            w5xxx_write(0x0, string.char(0x80))
            return
        else
            -- log.info(TAG, "输入MAC帧,大小", frame_size - 2)
            local mac_frame = w5xxx_read_data(frame_size, true, true)
            if mac_frame then
                -- log.info(TAG, "MAC帧数据(含2字节头部)",  mac_frame:toHex())
                -- ulwip.input(w5100s.opts.adapter, mac_frame:sub(3))
                ulwip.input(w5100s.opts.adapter, mac_frame, frame_size - 2, 2)
            end
            mac_frame = nil -- 释放内存
        end
    end

    -- 处理发送队列
    if #w5100s.tx_queue > 0 then
        local send_buff_remain = read_UINT16(0x0420)
        local tmpdata = w5100s.tx_queue[1]
        log.info(TAG, "发送队列", #w5100s.tx_queue, #tmpdata, send_buff_remain)
        if send_buff_remain >= #tmpdata then
            tmpdata = table.remove(w5100s.tx_queue, 1)
            w5xxx_write_data(tmpdata)
            sys.wait(5)
        end
        tmpdata = nil -- 释放内存
    end

    -- 有没有待接收的数据呢
    rx_size = read_UINT16(0x0426)
    if rx_size == 0 and #w5100s.tx_queue == 0 then
        sys.wait(20)
    else
        sys.wait(5)
    end
    --sys.wait(100)
end

local function netif_write_out(adapter_index, data)
    -- log.info(TAG, "待发送mac数据", data:toHex())
    if w5100s.ready() then
        -- TODO 限制传输队列的大小
        table.insert(w5100s.tx_queue, data)
    else
        log.info(TAG, "w5100s未就绪,丢弃数据", #data)
    end
end

function w5100s.main_loop()
    local adapter_index = w5100s.opts.adapter
    if not w5100s.ulwip_ready then
        local mac = w5100s.opts.mac or w5100s.mac()
        local ret = ulwip.setup(adapter_index, mac, netif_write_out)
        ulwip.reg(adapter_index)
        ulwip.updown(adapter_index, true)
        ulwip.dhcp(adapter_index, true)
        log.info(TAG, "ulwip初始化完成")
        if w5100s.opts.dft then
            ulwip.dft(adapter_index)
        end
        w5100s.ulwip_ready = true
    end
    ulwip.link(adapter_index, true)
    while w5100s.link() and w5100s.ready(true, true, true) do
        one_time()
    end
end

function w5100s.main_task()
    while 1 do
        if not w5100s.link() then
            log.info(TAG, "网线未连接,等待")
            if w5100s.ulwip_ready then
                ulwip.link(w5100s.opts.adapter, false)
            end
        else
            if not w5100s.ready(true, true, true) then
                log.info(TAG, "w5100s未就绪,执行初始化")
                w5100s.do_init()
            else
                log.info(TAG, "w5100s就绪,执行主逻辑")
                w5100s.tx_queue = {} -- 清空队列
                w5100s.main_loop()
            end
        end
        sys.wait(1000)
    end
end

function w5100s.start()
    if not w5100s.opts then
        log.info(TAG, "未初始化")
        return
    end
    if not w5100s.task_id then
        w5100s.task_id = sys.taskInit(w5100s.main_task)
    end
    return true
end


return w5100s
