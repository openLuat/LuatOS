--[[
遥测数据
]]

local mreport = {
    conf = {}
}

--[[
自定义配置(非必须)
@api mreport.setup(conf)
@table conf 配置信息
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

sys.subscribe("IP_READY", function ()
    if mreport.sc then
        socket.close(mreport.sc)
        mreport.sc = nil
    end
end)

function mreport.send(ext)
    -- 底层固件不含必要函数的话, 就不要调用了
    -- if not mobile.scell or not mcu.ticks2 then return end

    -- 创建socket
    if not mreport.sc then
        mreport.sc = socket.create(mreport.conf.adapter, function() end)
        -- 总是连接连接一次服务器
        if mreport.sc then
            socket.config(mreport.sc, mreport.conf.port or 12388, true)
            socket.connect(mreport.sc, mreport.conf.host or "47.94.236.172", mreport.conf.port or 12388)
        end
    end
    if not mreport.sc then return end

    -- 组织所需要的全部数据

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
    data.imei = mobile.imei()
    data.imsi = mobile.imsi()
    data.iccid = mobile.iccid()
    data.model = hmeta.model()
    if hmeta.hwver then
        data.hwver = hmeta.hwver()
    end
    data.phone = mobile.number(0)
    data.apn = mobile.apn(0)

    -- 供电和自身温度
    if adc then
        adc.open(adc.CH_VBAT)
        adc.open(adc.CH_CPU)
        data.vbat = adc.get(adc.CH_VBAT)
        data.ctemp = adc.get(adc.CH_CPU)
        adc.close(adc.CH_VBAT)
        adc.close(adc.CH_CPU)
    end

    -- GNSS定位相关
    if libgnss then 
        data.rmc = libgnss.getRmc(3)
        data.vtg = libgnss.getVtg(3)
        data.gga = libgnss.getGga(3)
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
        data.tmms, data.tms = mcu.ticks2(1)
    end
    -- 内存状态
    data.mem_lua = {rtos.meminfo()}
    data.mem_sys = {rtos.meminfo("sys")}
    data.mem_psram = {rtos.meminfo("psram")}

    -- 软件版本号
    data.pver = VERSION
    data.proj = PROJECT
    data.bspver = rtos.version():sub(2)
    data.localtime = os.time()
    data.powerreson = pm.lastReson()

    local ip, _, _, ipv6 = socket.localIP()
    if ip then
        data.ipv4 = ip
    end
    if ipv6 then
        data.ipv6 = ipv6
    end

    pcall(function()
        local rd = json.encode(data)
        log.debug("遥测数据", rd)
        socket.tx(mreport.sc, rd, mreport.conf.host or "47.94.236.172", mreport.conf.port or 12388)
    end)
end

sys.subscribe("IP_READY", function ()
    if mreport.sc then
        socket.close(mreport.sc)
        socket.connect(mreport.sc, mreport.conf.host or "47.94.236.172", mreport.conf.port or 12388)
    end
end)


-- sys.taskInit(function()
--    while 1 do
--         sys.wait(15000)
--         mreport.send()
--    end
-- end)

return mreport
