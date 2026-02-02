--[[
@module  mreport
@summary 遥测数据上报模块：设备信息、网络状态、GNSS数据等遥测信息上报
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 设备信息上报（IMEI、IMSI、ICCID、型号、硬件版本等）
2. 网络状态上报（基站信息、APN、IP地址等）
3. GNSS定位数据上报（RMC、VTG、GGA语句）
4. 系统状态上报（内存、温度、电池电压、运行时间等）
5. 版本信息上报（软件版本、项目版本、BSP版本等）
]]

local mreport = {
    conf = {}
}

-- ==================== 配置函数 ====================

--[[
自定义遥测服务器配置（非必须）
@api mreport.setup(conf)
@table conf 配置信息
@string conf.host 服务器地址，默认"47.94.236.172"
@number conf.port 服务器端口，默认12388
@usage
mreport.setup({
    host= "mreport.air32.cn",
    port = 12388
})
]]
function mreport.setup(conf)
    if not conf then return end
    mreport.conf = conf
end

-- ==================== 内部事件处理 ====================

-- IP就绪事件：断开旧连接
sys.subscribe("IP_READY", function ()
    if mreport.sc then
        socket.close(mreport.sc)
        mreport.sc = nil
    end
end)

-- ==================== 核心函数 ====================

--[[
发送遥测数据到服务器
功能：收集并上报以下数据
1. 基站信息：MCC/MNC/TAC/CID/APN等
2. 设备信息：IMEI/IMSI/ICCID/型号/硬件版本等
3. 硬件状态：电池电压、CPU温度
4. GNSS数据：RMC/VTG/GGA定位语句
5. 系统状态：内存使用、运行时间、启动原因等
6. 版本信息：软件版本、项目版本、BSP版本等
7. 网络信息：本地IP地址

@api mreport.send(ext)
@table ext 用户自定义扩展数据（可选）
@usage
mreport.send()  -- 发送遥测数据
mreport.send({custom="value"})  -- 发送带自定义数据的遥测
]]
function mreport.send(ext)
    -- 底层固件不含必要函数的话, 就不要调用了
    -- if not mobile.scell or not mcu.ticks2 then return end

    -- 创建socket
    if not mreport.sc then
        mreport.sc = socket.create(mreport.conf.adapter, function() end)
        -- 总是连接一次服务器
        if mreport.sc then
            socket.config(mreport.sc, mreport.conf.port or 12388, true)
            socket.connect(mreport.sc, mreport.conf.host or "47.94.236.172", mreport.conf.port or 12388)
        end
    end
    if not mreport.sc then return end

    -- ==================== 组织数据 ====================

    -- 基站相关
    local data = mobile.scell and mobile.scell() or {}
    if data == nil then return end
    if data.cid == nil then
        data.cid = mobile.eci()
        data.tac = mobile.tac()
        local cells = mobile.getCellInfo()
        if cells and #cells > 0 then
            local cell = cells[1]
            if cell and cell.mnc and cell.mcc then
                data.mcc = cell.mcc
                data.mnc = cell.mnc
            end
            cell = nil
        end
        cells = nil
    end

    -- 硬件相关
    data.imei = mobile.imei()      -- 设备IMEI
    data.imsi = mobile.imsi()      -- SIM卡IMSI
    data.iccid = mobile.iccid()    -- SIM卡ICCID
    data.model = hmeta.model()     -- 设备型号
    if hmeta.hwver then
        data.hwver = hmeta.hwver()  -- 硬件版本
    end
    data.phone = mobile.number(0)   -- 手机号
    data.apn = mobile.apn(0)       -- APN名称

    -- 供电和CPU温度
    if adc then
        adc.open(adc.CH_VBAT)
        adc.open(adc.CH_CPU)
        data.vbat = adc.get(adc.CH_VBAT)    -- 电池电压
        data.ctemp = adc.get(adc.CH_CPU)    -- CPU温度
        adc.close(adc.CH_VBAT)
        adc.close(adc.CH_CPU)
    end

    -- GNSS定位相关（使用libgnss）
    if libgnss then
        data.rmc = libgnss.getRmc(3)  -- 获取RMC语句（推荐最小定位数据）
        data.vtg = libgnss.getVtg(3)  -- 获取VTG语句（航迹地速和航向）
        data.gga = libgnss.getGga(3)  -- 获取GGA语句（定位数据）
        -- 去除语句首尾空白字符
        if data.rmc then
            data.rmc = data.rmc:trim()
        end
        if data.gga then
            data.gga = data.gga:trim()
        end
        if data.vtg then
            data.vtg = data.vtg:trim()
        end
    end

    -- 用户自定义数据
    if ext then
       data.ext = ext
    elseif mreport.ext then
        data.ext = mreport.ext
    end

    -- 开机至今的毫秒值
    if mcu.ticks2 then
        data.tmms, data.tms = mcu.ticks2(1)  -- 系统运行时间
    end

    -- 内存状态
    data.mem_lua = {rtos.meminfo()}      -- Lua内存
    data.mem_sys = {rtos.meminfo("sys")}  -- 系统内存
    data.mem_psram = {rtos.meminfo("psram")}  -- PSRAM内存

    -- 软件版本号
    data.pver = VERSION                -- 产品版本
    data.proj = PROJECT                -- 项目名称
    data.bspver = rtos.version():sub(2) -- BSP版本
    data.localtime = os.time()         -- 当前时间
    data.powerreson = pm.lastReson()   -- 启动原因

    -- 本地IP地址
    local ip = socket.localIP()
    if ip then
        data.ipv4 = ip
    end

    -- ==================== 发送数据 ====================

    pcall(function()
        local rd = json.encode(data)
        log.debug("遥测数据", rd)
        socket.tx(mreport.sc, rd, mreport.conf.host or "47.94.236.172", mreport.conf.port or 12388)
    end)
end

-- ==================== 事件订阅 ====================

-- IP就绪事件：重连服务器
sys.subscribe("IP_READY", function ()
    if mreport.sc then
        socket.close(mreport.sc)
        socket.connect(mreport.sc, mreport.conf.host or "47.94.236.172", mreport.conf.port or 12388)
    end
end)

-- ==================== 可选定时任务（已注释） ====================

-- sys.taskInit(function()
--    while 1 do
--         sys.wait(15000)
--         mreport.send()
--    end
-- end)

return mreport
