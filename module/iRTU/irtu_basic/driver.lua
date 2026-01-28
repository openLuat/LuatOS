local driver = {}

local default=require "default"
local create = require "create"
local gnss = require "gnss"
local exgnss= require "exgnss"
local exvib= require "exvib"
local exaudio = require "exaudio"
local audio_config = require "audio_config"
local lbsLoc = require"lbsLoc"
local dtulib = require "dtulib"

local dtu

-- 基站定位坐标
local lbs = {lat, lng}
-- 串口缓冲区最大值
local SENDSIZE =4096
-- 串口写空闲
local writeIdle = {true, true, true}
-- 串口读缓冲区
local recvBuff, writeBuff = {{}, {}, {}, {},{},{}}, {{}, {}, {}, {},{},{}}


local netready

---------------------------------------------------------- 用户控制 GPIO 配置 ----------------------------------------------------------
driver.pios = {
    pio1 = gpio.setup(1, nil, gpio.PULLDOWN),
    pio2 = gpio.setup(2, nil, gpio.PULLDOWN),
    pio3 = gpio.setup(3, nil, gpio.PULLDOWN),
    pio4 = gpio.setup(4, nil, gpio.PULLDOWN),
    pio5 =gpio.setup(5, nil,gpio.PULLDOWN),
    pio6 =gpio.setup(6, nil,gpio.PULLDOWN),
    pio7 =gpio.setup(7, nil,gpio.PULLDOWN),
    pio8 =gpio.setup(8, nil,gpio.PULLDOWN),
    pio9 =gpio.setup(9, nil,gpio.PULLDOWN),
    pio10 =gpio.setup(10, nil,gpio.PULLDOWN),
    pio11 =gpio.setup(11, nil,gpio.PULLDOWN),
    pio16 =gpio.setup(16, nil,gpio.PULLDOWN),
    pio17 =gpio.setup(17, nil,gpio.PULLDOWN),
    pio20 =gpio.setup(20, nil,gpio.PULLDOWN),
    pio21 =gpio.setup(21, nil,gpio.PULLDOWN),
    pio22 =gpio.setup(22, nil,gpio.PULLDOWN),
    -- pio23 =gpio.setup(23, nil,gpio.PULLDOWN),
    -- pio24 =gpio.setup(24, nil,gpio.PULLDOWN),
    -- pio25 =gpio.setup(25, nil,gpio.PULLDOWN),
    pio26 =gpio.setup(26, nil,gpio.PULLDOWN),  --READY指示灯
    pio27 =gpio.setup(27, nil,gpio.PULLDOWN),  --NET指示灯
    pio28 =gpio.setup(28, nil,gpio.PULLDOWN),  
    pio29 =gpio.setup(29, nil,gpio.PULLDOWN) ,
    pio30 =gpio.setup(30, nil,gpio.PULLDOWN),
    pio31 =gpio.setup(31, nil,gpio.PULLDOWN),
    pio32 =gpio.setup(32, nil,gpio.PULLDOWN),
    pio33 =gpio.setup(33, nil,gpio.PULLDOWN),
    pio34 =gpio.setup(34, nil,gpio.PULLDOWN),
    pio35 =gpio.setup(35, nil,gpio.PULLDOWN),
    pio36 =gpio.setup(36, nil,gpio.PULLDOWN),
    pio37 =gpio.setup(37, nil,gpio.PULLDOWN),
    pio38 =gpio.setup(38, nil,gpio.PULLDOWN),
}

-- 保存获取的基站坐标
function driver.setLocation(lat, lng)
    lbs.lat, lbs.lng = lat, lng
    log.info("基站定位请求的结果:", lat, lng)
end


-- 串口写数据处理
function write(uid, str,cid)
    uid = tonumber(uid)
    if not str or str == "" or not uid then return end
    if uid == uart.VUART_0 then return uart.write(uart.VUART_0, str) end
    if str ~= true then
        for i = 1, #str, SENDSIZE do
            table.insert(writeBuff[uid], str:sub(i, i + SENDSIZE - 1))
        end
        log.info("str的实际值是",str)
        log.warn("uart" .. uid .. ".write data length:", writeIdle[uid], #str)
    end
    if writeIdle[uid] and writeBuff[uid][1] then
        if 0 ~= uart.write(uid, writeBuff[uid][1]) then
            table.remove(writeBuff[uid], 1)
            writeIdle[uid] = false
            log.warn("UART_" .. uid .. " writing ...")
        end
    end
end

local function writeDone(uid)
    if uid=="32" or uid==32 then
        
    else
        if #writeBuff[uid] == 0 then
            writeIdle[uid] = true
            sys.publish("UART_" .. uid .. "_WRITE_DONE")
            log.warn("UART_" .. uid .. "write done!")
        else
            writeIdle[uid] = false
            uart.write(uid, table.remove(writeBuff[uid], 1))
            log.warn("UART_" .. uid .. "writing ...")
        end
    end
end

-- DTU配置工具默认的方法表
cmd = {}
cmd.config = {
    ["A"] = function(t)
        if t[1]~=nil and t[2]~=nil and t[3]~=nil then
            t[2]=t[2]=="nil" and "" or t[2]
            t[3]=t[3]=="nil" and "" or t[3]
            dtu.apn = t 
            default.cfg_get():import(dtu)
            log.info("APN配置成功",dtu.apn[1],dtu.apn[2],dtu.apn[3])
            mobile.flymode(0,true)
            mobile.apn(0,1,dtu.apn[1],dtu.apn[2],dtu.apn[3])
            mobile.flymode(0, false)
            return "OK"
        end
    end, -- APN 配置
    ["readconfig"] = function(t)-- 读取整个DTU的参数配置
        if t[1] == dtu.password or dtu.password == "" or dtu.password == nil then
            return default.cfg_get():export("string")
        else
            return "PASSWORD ERROR"
        end
    end,  

}
cmd.rrpc = {
    ["getfwver"] = function(t) return "rrpc,getfwver," .. _G.PROJECT .. "_" .. _G.VERSION .. "_" .. rtos.version() end,
    ["getnetmode"] = function(t) return "rrpc,getnetmode," .. (mobile.status() and mobile.status() or 1) end,
    ["getver"] = function(t) return "rrpc,getver," .. _G.VERSION end,
    ["getcsq"] = function(t) return "rrpc,getcsq," .. (mobile.csq() or "error ") end,
    ["getadc"] = function(t) return "rrpc,getadc," .. create.getADC(tonumber(t[1]) or 0) end,
    ["reboot"] = function(t)
        sys.timerStart(dtulib.restart, 1000, "Remote reboot!") 
        return "OK" end,
    ["getimei"] = function(t) return "rrpc,getimei," .. (mobile.imei() or "error") end,
    ["getmuid"] = function(t) return "rrpc,getmuid," .. (mobile.muid() or "error") end,
    ["getimsi"] = function(t) return "rrpc,getimsi," .. (mobile.imsi() or "error") end,
    ["getvbatt"] = function(t) return "rrpc,getvbatt," .. create.getADC(adc.CH_VBAT) end,
    ["geticcid"] = function(t) return "rrpc,geticcid," .. (mobile.iccid() or "error") end,
    ["getproject"] = function(t) return "rrpc,getproject," .. _G.PROJECT end,
    ["getcorever"] = function(t) return "rrpc,getcorever," .. rtos.version() end,
    ["getlocation"] = function(t) return "rrpc,location," .. (lbs.lat or 0) .. "," .. (lbs.lng or 0) end,
    ["getreallocation"] = function(t)
        lbsLoc.request(function(result, lat, lng, addr,time,locType)
            if result then
                lbs.lat, lbs.lng = lat, lng
                log.info("定位类型,基站定位成功返回0", locType)
                driver.setLocation(lat, lng)
            end
        end)
        return "rrpc,getreallocation," .. (lbs.lat or 0) .. "," .. (lbs.lng or 0)
    end,
    ["gettime"] = function(t)
        local t = os.date("*t")
        return "rrpc,gettime," .. string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year,t.month,t.day,t.hour,t.min,t.sec)
    end,
    ["setpio"] = function(t) 
        if driver.pios["pio" .. t[1]] and (tonumber(t[2]) ==0 or tonumber(t[2]) ==1) then 
            gpio.setup(tonumber(t[1]),tonumber(t[2]))
            return "OK" 
        end 
        return "ERROR" end,
    ["getpio"] = function(t)
        if driver.pios["pio" .. t[1]] then 
            return "rrpc,getpio" .. t[1] .. "," .. gpio.get(t[1]) 
        end
        return "ERROR" end,
    ["netstatus"] = function(t)
        if t == nil or t == "" or t[1] == nil or t[1] == "" then
            return "rrpc,netstatus," .. (create.getDatalink() and "RDY" or "NORDY")
        else
            return "rrpc,netstatus," .. (t[1] and (t[1] .. ",") or "") .. (create.getDatalink(tonumber(t[1])) and "RDY" or "NORDY")
        end
    end,
    ["gnssopen"] = function(t)sys.publish("GPS_OPEN") return "rrpc,gnssopen,OK" end,
    ["gnssmsg"] = function(t) return "rrpc,gnssmsg," .. (gnss.locateMessage(dtu.gps.fun[8]) or "") end,
    ["gnssclose"] = function(t) 
        exgnss.close_all() 
        sys.timerStop(g_tid)
        exvib.close()
        sys.timerStop(s_tid)
        sys.timerStop(tid)
        return "rrpc,gnssclose,OK" 
    end,
    ["upconfig"] = function(t)sys.publish("UPDATE_DTU_CNF") return "rrpc,upconfig,OK" end,
    ["function"] = function(t)log.info("rrpc,function:", table.concat(t, ",")) return "rrpc,function," .. (loadstring(table.concat(t, ","))() or "OK") end,
    ["simcross"] = function(t) 
        if tonumber(t[1])==1 or tonumber(t[1])==0 or tonumber(t[1])==2 then
            mobile.flymode(0, true)
            mobile.simid(tonumber(t[1]))
            mobile.flymode(0, false)
            return "simcross,ok,"..t[1] 
        else
            return "simcross,error,"..t[1]
        end
    end,
    ["ttsplay"] = function(t) 
        if t then
            log.info("TTT",t[1])
            -- sys.publish("AUDIO_PLAY_TTS",t[1])
            local result=audio_config.audio_play_tts(t[1])
            -- local result=audio.tts(0, t[1])
            -- sys.wait(1000)
            log.info("TTT",result)
            return "rrpc,ttsplay,"..(result and "OK" or "ERROR")
            -- return "rrpc,ttsplay,"..(result and "OK" or "ERROR")
        end
    end,
    ["setvol"] = function(t) 
        if t and tonumber(t[1])>=0 and tonumber(t[1])<=100 then
            log.info("TTT",t[1])
            if exaudio.vol(tonumber(t[1])) then
                fskv.set("vol",tonumber(t[1]))
                return "rrpc,setvol,OK"
            else
                return "rrpc,setvol,ERROR"
            end
        else
            return "rrpc,setvol,ERROR"
        end
    end,
    ["getvol"] = function(t) 
        if fskv.get("vol") then
            return "rrpc,getvol,"..fskv.get("vol")
        else
            return "rrpc,getvol,65"
        end
    end,
    ["fileplay"] = function(t) 
        if t then
            local result=audio_config.audio_play_file(t[1],t[2],t[3])
            return "rrpc,fileplay,"..(result and "OK" or "ERROR")
        end
    end,
    ["stopplay"] = function(t) 
        if t then
            if exaudio.play_stop() then
                return "rrpc,stopplay,OK"
            else
                return "rrpc,stopplay,ERROR"
            end
        end
    end,
}


-- 串口读指令
local function read(uid, idx)
    log.error("uart.read--->", uid, idx)
    local s = table.concat(recvBuff[idx])
    recvBuff[idx] = {}
    log.info("UART_" .. uid .. " read:", #s, (s:sub(1, 100):toHex()))
    log.info("串口数据长度:", #s)
    -- 根据透传标志位判断是否解析数据
    
    -- DTU的参数配置
    if s:sub(1, 7) == "config," or s:sub(1, 5) == "rrpc," then
        return write(uid, create.userapi(s))
    end
  -- 正常透传模式
    log.info("这个里面的内容是",dtu.plate == 1 and mobile.imei() .. s or s)
    sys.publish("NET_SENT_RDY_" .. uid, dtu.plate == 1 and mobile.imei() .. s or s)
end

-- uart 的初始化配置函数
-- 数据流模式
local streamlength = 0
local function streamEnd(uid)
    if #recvBuff[uid] > 0 then
        sys.publish("NET_SENT_RDY_" .. uid, table.concat(recvBuff[uid]))
        recvBuff[uid] = {}
        streamlength = 0
    end
end

function uart_INIT(i, uconf)
    uconf[i][1] = tonumber(uconf[i][1])
    log.info("串口的数据是",uconf[i][1], uconf[i][2], uconf[i][3], uconf[i][4], uconf[i][5],uconf[i][6])
    local rs485us=tonumber(uconf[i][7]) and tonumber(uconf[i][7]) or 0
    local parity=uart.None
    if uconf[i][4]==0 then
        parity=uart.EVEN
    elseif  uconf[i][4]==1 then
        parity=uart.Odd
    elseif uconf[i][4]==2 then
        parity=uart.None
    end
    if driver.pios[dtu.uconf[i][6]] then
        driver["dir" .. i] = tonumber(dtu.uconf[i][6]:sub(4, -1))
        driver.pios[dtu.uconf[i][6]] = nil
    else
        driver["dir" .. i] = nil
    end
    log.info("driver",driver["dir" .. i])
    log.info("rs485us",rs485us)
    uart.setup(uconf[i][1], uconf[i][2], uconf[i][3], uconf[i][5],parity,uart.LSB,SENDSIZE, driver["dir" .. i],0,rs485us)
    uart.on(uconf[i][1], "sent", writeDone)
    if uconf[i][1] == uart.VUART_0 or tonumber(dtu.uartReadTime) > 0 then
        uart.on(uconf[i][1], "receive", function(uid, length)
            log.info("接收到的数据是",uid,length)
            table.insert(recvBuff[i], uart.read(uconf[i][1], length or 8192))
            sys.timerStart(sys.publish, tonumber(dtu.uartReadTime) or 25, "UART_RECV_WAIT_" .. uconf[i][1], uconf[i][1], i)
            -- sys.publish("UART_RECV_WAIT_" .. uconf[i][1], uconf[i][1], i)
        end)
    else
        uart.on(uconf[i][1], "receive", function(uid, length)
            local str = uart.read(uconf[i][1], length or 8192)
            sys.timerStart(streamEnd, 1000, i)
            streamlength = streamlength + #str
            table.insert(recvBuff[i], str)
            if streamlength > 29200 then
                sys.publish("NET_SENT_RDY_" .. uconf[i][1], table.concat(recvBuff[i]))
                recvBuff[i] = {}
                streamlength = 0
            end
        end)
    end
    -- 处理串口接收到的数据
    sys.subscribe("UART_RECV_WAIT_" .. uconf[i][1], read)

    sys.subscribe("UART_SENT_RDY_" .. uconf[i][1], write)
end



-- 自动任务采集
local function autoSampl(uid, t)
    while true do
        sys.waitUntil("AUTO_SAMPL_" .. uid)
        for i = 2, #t do
            local str = t[i]:match("function(.+)end")
            if not str then
                if t[i] ~= "" then 
                    write(uid, (dtulib.fromHexnew(t[i]))) end
            else
                local res, msg = pcall(loadstring(str))
                if res then
                    sys.publish("NET_SENT_RDY_" .. uid, msg)
                end
            end
            sys.wait(t[1])
        end
    end
end


-- NETLED指示灯任务
local function blinkPwm(ledPin, light, dark)
    ledPin(1)
    sys.wait(light)
    ledPin(0)
    sys.wait(dark)
end

local function netled(led)
    local ledpin = gpio.setup(led, 1)
    while true do
        while mobile.status() == 3 or mobile.status() == 2 or mobile.status() == 0 do
            blinkPwm(ledpin, 100, 100)
            netready(0)
        end
        while mobile.status() == 1 or mobile.status() == 5 do
            if create.getDatalink() then
                netready(1)
                blinkPwm(ledpin, 200, 1800)
            else
                netready(0)
                blinkPwm(ledpin, 500, 500)
            end
        end
        sys.wait(10000)
    end
end

--初始化串口/灯/自动任务采集功能
function driver.init()
    dtu = default.get()
    -- 初始化配置UART1和UART2
    local uidgps = dtu.gps and dtu.gps.fun and tonumber(dtu.gps.fun[1])
    if uidgps ~= 1 and dtu.uconf and dtu.uconf[1] and tonumber(dtu.uconf[1][1]) == 1 then
        uart_INIT(1, dtu.uconf) end
    if uidgps ~= 2 and dtu.uconf and dtu.uconf[2] and tonumber(dtu.uconf[2][1]) == 2 then uart_INIT(2, dtu.uconf) end
    if uidgps ~= 3 and dtu.uconf and dtu.uconf[3] and tonumber(dtu.uconf[3][1]) == 3 then 
        uart_INIT(3, dtu.uconf)
    end
    if true then
        dtu.uconf[4] = {uart.VUART_0, 115200, 8, 2, 0}
        uart_INIT(4, dtu.uconf)
    end
    -- 网络READY信号
    if not dtu.pins or not dtu.pins[2] or not default.pios[dtu.pins[2]] then 
        netready = gpio.setup(26, 0)
    else
        netready = gpio.setup(tonumber(dtu.pins[2]:sub(4, -1)), 0)
        default.pios[dtu.pins[2]] = nil
    end

    if not dtu.pins or not dtu.pins[1] or not default.pios[dtu.pins[1]] then 
        sys.taskInit(netled,27)
    else
        sys.taskInit(netled, tonumber(dtu.pins[1]:sub(4, -1)))
        default.pios[dtu.pins[1]] = nil
    end

    --自动任务采集
    if dtu.cmds and dtu.cmds[1] and dtu.cmds[1][1] then sys.taskInit(autoSampl, 1, dtu.cmds[1]) end
    if dtu.cmds and dtu.cmds[2] and dtu.cmds[2][1] then sys.taskInit(autoSampl, 2, dtu.cmds[2]) end
    if dtu.cmds and dtu.cmds[3] and dtu.cmds[3][1] then sys.taskInit(autoSampl, 3, dtu.cmds[3]) end

end

return driver