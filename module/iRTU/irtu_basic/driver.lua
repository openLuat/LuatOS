--[[
@module  driver
@summary irtu串口/GPIO灯/自动任务采集功能
@version 5.0.0
@date    2026.01.27
@author  李源龙
@usage
初始化串口，GPIO灯，自动任务采集功能
]]
local driver = {}

local default=require "default"
local create = require "create"

local gnss = require "gnss"
local exgnss= require "exgnss"
local exvib= require "exvib"

local exaudio = require "exaudio"
local audio_config = require "audio_config"
local lbsLoc2 = require"lbsLoc2"
local airlbs = require "airlbs"
local dtulib = require "dtulib"

local dtu
local cfg
-- 基站定位坐标
local lbs = {lat, lng}
-- 串口缓冲区最大值
local SENDSIZE =4096
-- 串口写空闲
local writeIdle = {true, true, true}
-- 串口读缓冲区
local recvBuff, writeBuff = {{}, {}, {}, {},{},{}}, {{}, {}, {}, {},{},{}}

--netready灯的初始化接收变量
local netready



-- 保存获取的基站坐标
function driver.setLocation(lat, lng)
    lbs.lat, lbs.lng = lat, lng
    log.info("基站定位请求的结果:", lat, lng)
end

-- airlbs配置数据存储键名
local AirlbsConfigKey = "airlbs_config"

-- 默认airlbs配置
local default_airlbs_config = {
    project_id = "",
    project_key = "",
    timeout = 10000
}

-- 加载airlbs配置
local function load_airlbs_config()
    -- 初始化fskv存储系统
    local result = fskv.init()
    if not result then
        log.error("load_airlbs_config", "fskv初始化失败，使用默认配置")
        return default_airlbs_config
    end
    
    -- 尝试从fskv加载配置
    local config_data = fskv.get(AirlbsConfigKey)
    if not config_data then
        log.info("load_airlbs_config", "未找到配置文件，使用默认配置")
        return default_airlbs_config
    end
    
    -- 解析配置数据
    local config = json.decode(config_data)
    if not config then
        log.error("load_airlbs_config", "配置文件解析失败，使用默认配置")
        return default_airlbs_config
    end
    
    -- 合并配置（确保所有字段都存在）
    local merged_config = {}
    merged_config.project_id = config.project_id or default_airlbs_config.project_id
    merged_config.project_key = config.project_key or default_airlbs_config.project_key
    merged_config.timeout = config.timeout or default_airlbs_config.timeout
    
    log.info("load_airlbs_config", "配置加载成功")
    return merged_config
end

-- 保存airlbs配置
local function save_airlbs_config(config)
    -- 初始化fskv存储系统
    local result = fskv.init()
    if not result then
        log.error("save_airlbs_config", "fskv初始化失败")
        return false
    end
    
    -- 保存配置
    local config_str = json.encode(config)
    local save_result = fskv.set(AirlbsConfigKey, config_str)
    
    if save_result then
        log.info("save_airlbs_config", "配置保存成功")
        return true
    else
        log.error("save_airlbs_config", "配置保存失败")
        return false
    end
end

-- 获取当前airlbs配置
local function get_current_airlbs_config()
    if not _G.airlbs_config then
        _G.airlbs_config = load_airlbs_config()
    end
    return _G.airlbs_config
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

--串口发送是否完成
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
--config指令
cmd.config = {
    ["A"] = function(t)
        if t[1]~=nil and t[2]~=nil and t[3]~=nil then
            t[2]=t[2]=="nil" and "" or t[2]
            t[3]=t[3]=="nil" and "" or t[3]
            dtu.apn = t 
            cfg:import(dtu)
            log.info("APN配置成功",dtu.apn[1],dtu.apn[2],dtu.apn[3])
            mobile.flymode(0,true)
            mobile.apn(0,1,dtu.apn[1],dtu.apn[2],dtu.apn[3])
            mobile.flymode(0, false)
            return "OK"
        end
    end, -- APN 配置
    ["readconfig"] = function(t)-- 读取整个DTU的参数配置
        if t[1] == dtu.password or dtu.password == "" or dtu.password == nil then
            return cfg:export("string")
        else
            return "PASSWORD ERROR"
        end
    end,  
    ["writeconfig"] = function(t, s)-- 读取整个DTU的参数配置
        local str = s:match("(.+)\r\n") and s:match("(.+)\r\n"):sub(20, -1) or s:sub(20, -1)
        local dat, result, errinfo = json.decode(str)
        if result then
            if dtu.password == dat.password or dtu.password == "" or dtu.password == nil then
                cfg:import(str)
                sys.timerStart(dtulib.restart, 5000, "Setting parameters have been saved!")
                return "OK"
            else
                return "PASSWORD ERROR"
            end
        else
            return "JSON ERROR"
        end
    end,
}
--rrpc指令
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
    ["setairlbsconfig"] = function(t)
        if #t < 2 then
            return "rrpc,setairlbsconfig,ERROR,参数不足"
        end
        
        local config = {
            project_id = t[1],
            project_key = t[2],
            timeout = tonumber(t[3]) or 10000
        }
        
        local save_result = save_airlbs_config(config)
        if save_result then
            -- 更新全局配置
            _G.airlbs_config = config
            return "rrpc,setairlbsconfig,OK," .. config.project_id .. "," .. config.project_key .. "," .. config.timeout
        else
            return "rrpc,setairlbsconfig,ERROR,保存失败"
        end
    end,
    ["getairlbsconfig"] = function(t)
        local config = get_current_airlbs_config()
        return "rrpc,getairlbsconfig,OK," .. config.project_id .. "," .. config.project_key .. "," .. config.timeout
    end,
    ["getreallocation"] = function(t, source_info)
        log.info("getreallocation called with source_info:", source_info)
        
        -- 启动一个task来处理定位
        sys.taskInit(function()
            while not socket.adapter(socket.dft()) do
                log.warn("lbsloc2_task_func", "wait IP_READY", socket.dft())
                -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
                -- 或者等待1秒超时退出阻塞等待状态;
                -- 注意：此处的1000毫秒超时不要修改的更长；
                -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
                -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
                -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
                sys.waitUntil("IP_READY", 1000)
            end
            -- 首先进行基站扫描
            mobile.reqCellInfo(15)--进行基站扫描，超时时间为15s
            sys.waitUntil("CELL_INFO_UPDATE", 3000)--等到扫描成功，超时时间3S
            
            -- 然后请求定位
            -- 直接请求定位
            local lat, lng, t = lbsLoc2.request(5000)
            if lat and lng then
                lbs.lat, lbs.lng = lat, lng
                log.info("基站定位请求的结果:", lat, lng)
                driver.setLocation(lat, lng)
            end
            
            -- 定位完成后发送响应
            local response = "rrpc,getreallocation," .. (lbs.lat or 0) .. "," .. (lbs.lng or 0)
            log.info("Sending location response:", response)
            
            -- 根据来源信息发送响应
            if source_info then
                if source_info.type == "uart" then
                    -- 串口来源，发送到对应的串口
                    write(source_info.uid, response)
                elseif source_info.type == "network" then
                    -- 传递两个参数，第一个参数用于判断cid，类似于GPSCID_的处理方式
                    sys.publish("NET_SENT_RDY_" .. source_info.uid, "CID_" .. source_info.cid, response)
                else
                    log.warn("Unknown source type")
                end
            else
                log.warn("getreallocation: No source information available")
            end
        end)
        
        -- 不立即返回，异步响应将通过 NET_SENT_RDY 事件发送
        return nil
    end,
    ["getairlbslocation"] = function(t, source_info)
        log.info("getairlbslocation called with source_info:", source_info)
        
        -- 启动一个task来处理定位
        sys.taskInit(function()
            -- 获取配置
            local config = get_current_airlbs_config()
            while not socket.adapter(socket.dft()) do
                log.warn("lbsloc2_task_func", "wait IP_READY", socket.dft())
                -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
                -- 或者等待1秒超时退出阻塞等待状态;
                -- 注意：此处的1000毫秒超时不要修改的更长；
                -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
                -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
                -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
                sys.waitUntil("IP_READY", 1000)
            end
            
            -- socket.sntp() --进行NTP授时
            -- sys.waitUntil("NTP_UPDATE", 1000)
            if not config.project_id or config.project_id == "" or not config.project_key or config.project_key == "" then
                local response = "rrpc,getairlbslocation,ERROR,未配置项目信息"
                log.info("Sending location response:", response)
                
                if source_info then
                    if source_info.type == "uart" then
                        write(source_info.uid, response)
                    elseif source_info.type == "network" then
                        -- 传递两个参数，第一个参数用于判断cid，类似于GPSCID_的处理方式
                        sys.publish("NET_SENT_RDY_" .. source_info.uid, "CID_" .. source_info.cid, response)
                    else
                        log.warn("Unknown source type")
                    end
                end
                return
            end
            
            -- 准备定位参数
            local param = {
                project_id = config.project_id,
                project_key = config.project_key,
                timeout = config.timeout
            }
            
            -- 检查是否需要wifi定位
            local use_wifi = false
            if t and #t > 0 and t[1] == "1" then
                use_wifi = true
                -- 扫描wifi
                if wlan then
                    wlan.init()
                    wlan.scan()
                    sys.waitUntil("WLAN_SCAN_DONE", 5000)
                    local wifi_info = wlan.scanResult()
                    if wifi_info and #wifi_info > 0 then
                        param.wifi_info = wifi_info
                        log.info("WiFi扫描到", #wifi_info, "个热点")
                    end
                end
            end
            
            -- 请求定位
            log.info("airlbs定位请求参数:", json.encode(param))
            local result, data = airlbs.request(param)
            
            if result then
                lbs.lat, lbs.lng = data.lat, data.lng
                log.info("airlbs定位成功:", data.lat, data.lng)
                driver.setLocation(data.lat, data.lng)
                
                local response = "rrpc,getairlbslocation,OK," .. data.lat .. "," .. data.lng
                log.info("Sending location response:", response)
                
                if source_info then
                    if source_info.type == "uart" then
                        write(source_info.uid, response)
                    elseif source_info.type == "network" then
                        -- 传递两个参数，第一个参数用于判断cid，类似于GPSCID_的处理方式
                        sys.publish("NET_SENT_RDY_" .. source_info.uid, "CID_" .. source_info.cid, response)
                    else
                        log.warn("Unknown source type")
                    end
                end
            else
                local response = "rrpc,getairlbslocation,ERROR," .. (data or "定位失败")
                log.error("airlbs定位失败:", data)
                
                if source_info then
                    if source_info.type == "uart" then
                        write(source_info.uid, response)
                    elseif source_info.type == "network" then
                        -- 传递两个参数，第一个参数用于判断cid，类似于GPSCID_的处理方式
                        sys.publish("NET_SENT_RDY_" .. source_info.uid, "CID_" .. source_info.cid, response)
                    else
                        log.warn("Unknown source type")
                    end
                end
            end
        end)
        
        -- 不立即返回，异步响应将通过 NET_SENT_RDY 事件发送
        return nil
    end,
    ["gettime"] = function(t)
        local t = os.date("*t")
        return "rrpc,gettime," .. string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year,t.month,t.day,t.hour,t.min,t.sec)
    end,
    ["setpio"] = function(t) 
        if default.pios["pio" .. t[1]] and (tonumber(t[2]) ==0 or tonumber(t[2]) ==1) then 
            gpio.setup(tonumber(t[1]),tonumber(t[2]))
            return "OK" 
        end 
        return "ERROR" end,
    ["getpio"] = function(t)
        if default.pios["pio" .. t[1]] then 
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
       sys.publish("GNSSCLOSE")
        return "rrpc,gnssclose,OK" 
    end,
    ["upconfig"] = function(t)sys.publish("UPDATE_DTU_CNF") return "rrpc,upconfig,OK" end,
    ["function"] = function(t)
        log.info("rrpc,function:", table.concat(t, ","))
        local ok, result = pcall(function()
            local func = loadstring(table.concat(t, ","))
            if func then
                return func() or "OK"
            end
            return "ERROR"
        end)
        if not ok then
            log.error("rrpc,function", "执行失败:", result)
            return "rrpc,function,ERROR"
        end
        return "rrpc,function," .. tostring(result)
    end,
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
            local result=audio_config.audio_play_tts(t[1])
            return "rrpc,ttsplay,"..(result and "OK" or "ERROR")
        end
    end,
    ["setvol"] = function(t) 
        if t and tonumber(t[1])>=0 and tonumber(t[1])<=100 then
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
        -- 对于 getreallocation 和 getairlbslocation 指令，我们需要传递来源信息（串口）给 userapi，以便异步响应
        if s:find("getreallocation") or s:find("getairlbslocation") then
            local result = create.userapi(s, {
                type = "uart",
                uid = uid
            })
            if result then
                return write(uid, result)
            else
                log.info("read: Command will be handled asynchronously")
                return nil -- 不立即写入，异步响应将通过 NET_SENT_RDY 事件发送
            end
        else
            local result = create.userapi(s)
            if result then
                return write(uid, result)
            end
        end
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

--串口初始化
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
    if default.pios[dtu.uconf[i][6]] then
        driver["dir" .. i] = tonumber(dtu.uconf[i][6]:sub(4, -1))
        default.pios[dtu.uconf[i][6]] = nil
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
                local res, msg = pcall(function()
                    local func = loadstring(str)
                    if func then
                        return func()
                    end
                    return nil
                end)
                if res and msg then
                    sys.publish("NET_SENT_RDY_" .. uid, msg)
                elseif not res then
                    log.error("autoSampl", "执行自动任务失败:", msg)
                    log.error("autoSampl", "任务执行堆栈:", debug.traceback())
                end
            end
            sys.wait(t[1])
        end
        if dtu.pwrmod=="psm" then
            if dtu.psm_time and dtu.psm_time > 0 then
                pm.dtimerStart(2, dtu.psm_time*1000)
            end
            pm.power(pm.WORK_MODE, 3)
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

-- NETLED指示灯任务
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
    cfg = default.cfg_get()
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
    if dtu.pwrmod == "normal" then
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
    end
    --自动任务采集
    if dtu.cmds and dtu.cmds[1] and dtu.cmds[1][1] then sys.taskInit(autoSampl, 1, dtu.cmds[1]) end
    if dtu.cmds and dtu.cmds[2] and dtu.cmds[2][1] then sys.taskInit(autoSampl, 2, dtu.cmds[2]) end
    if dtu.cmds and dtu.cmds[3] and dtu.cmds[3][1] then sys.taskInit(autoSampl, 3, dtu.cmds[3]) end

end

return driver