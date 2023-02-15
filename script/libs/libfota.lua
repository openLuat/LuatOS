--[[
@module libfota
@summary libfota fota升级
@version 1.0
@date    2023.02.01
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
--用法实例
local libfota = require("libfota")

-- 功能:获取fota的回调函数
-- 参数:
-- result:number类型
--   0表示成功
--   1表示连接失败
--   2表示url错误
--   3表示服务器断开
--   4表示接收报文错误
--   5表示使用iot平台VERSION需要使用 xxx.yyy.zzz形式
function libfota_cb(result)
    log.info("fota", "result", result)
    -- fota成功
    if result == 0 then
        rtos.reboot()   --如果还有其他事情要做,就不要立刻reboot
    end
end

--注意!!!:使用合宙iot平台,必须用luatools量产生成的.bin文件!!! 自建服务器可使用.ota文件!!!
--注意!!!:使用合宙iot平台,必须用luatools量产生成的.bin文件!!! 自建服务器可使用.ota文件!!!
--注意!!!:使用合宙iot平台,必须用luatools量产生成的.bin文件!!! 自建服务器可使用.ota文件!!!

--下方示例为合宙iot平台,地址:http://iot.openluat.com 
libfota.request(libfota_cb)

--如使用自建服务器,自行更换url
-- 对自定义服务器的要求是:
-- 若需要升级, 响应http 200, body为升级文件的内容
-- 若不需要升级, 响应300或以上的代码,务必注意
libfota.request(libfota_cb,"http://xxxxxx.com/xxx/upgrade?version=" .. _G.VERSION)

-- 若需要定时升级
-- 合宙iot平台
sys.timerLoopStart(libfota.request, 4*3600*1000, libfota_cb)
-- 自建平台
sys.timerLoopStart(libfota.request, 4*3600*1000, libfota_cb, "http://xxxxxx.com/xxx/upgrade?version=" .. _G.VERSION)
]]

local sys = require "sys"
local sysplus = require "sysplus"
local libnet = require "libnet"

local libfota = {}

local taskName = "OTA_TASK"
local tag = "fota"

local function netCB(msg)
    if msg[1] == socket.EVENT then
        log.info(tag, "socket网络状态变更")
    elseif msg[1] == socket.TX_OK then
        log.info(tag, "socket发送完成")
    elseif msg[1] == socket.EV_NW_RESULT_CLOSE then
        log.info(tag, "socket关闭")
    else
        log.info(tag, "未处理消息", msg[1], msg[2], msg[3], msg[4])
    end
end

local function fota_task(cbFnc,storge_location, len, param1,ota_url,ota_port,timeout,tls,server_cert, client_cert, client_key, client_password)
    fota.init(storge_location, len, param1)
    if cbFnc == nil then
        cbFnc = function() end
    end
    -- 若ota_url没有传,那就是用合宙iot平台
    if ota_url == nil then
        if _G.PRODUCT_KEY == nil then
            -- 必须在main.lua定义 PRODUCT_KEY = "xxx"
            -- iot平台新建项目后, 项目详情中可以查到
            log.error("fota", "iot.openluat.com need PRODUCT_KEY!!!")
            cbFnc(5)
            return
        else
            local x,y,z = string.match(_G.VERSION,"(%d+).(%d+).(%d+)")
            if x and y and z then
                version = x.."."..z
                ota_url = "http://iot.openluat.com/api/site/firmware_upgrade?project_key=" .. _G.PRODUCT_KEY .. "&imei=".. mobile.imei() .. "&device_key=&firmware_name=" .. _G.PROJECT.. "_LuatOS-SoC_" .. rtos.bsp() .. "&version=" .. rtos.version():sub(2) .. "." .. version
            else
                log.error("fota", "_G.VERSION must be xxx.yyy.zzz!!!")
                cbFnc(5)
                return
            end
        end
    end

    local succ, param, ip, port, total, findhead, filelen, rcvCache,d1,d2,statusCode,retry,rspHead,rcvChunked,done,fotaDone,nCache
    local tbuff = zbuff.create(512)
    local rbuff = zbuff.create(4096)
    local netc = socket.create(nil, taskName)
    local tls_get = false
    if ota_url:sub(1,5) == "https" then
        tls_get = true
    end
    socket.config(netc, nil, nil, tls or tls_get,server_cert, client_cert, client_key, client_password)
    filelen = 0
    total = 0
    retry = 0
    done = false
    rspHead = {}
    local ret = 1
    local result = libnet.waitLink(taskName, 0, netc)
    
    local type,host,uri
    if ota_url then
        type,host,uri = string.match(ota_url,"(%a-)://(%S-)/(%S+)")
    end
    while retry < 3 and not done do
        local version
        if type == nil or host == nil then
            cbFnc(2)
            return
        end

        if ota_port == nil then
            local url_port = string.match(host,".:(%d+)")
            if url_port then
                ota_port = url_port
            elseif type == "http" then
                ota_port = 80
            elseif type == "https" then
                ota_port = 443
            end
        end

        result = libnet.connect(taskName, 30000, netc, host, ota_port) --后续出了http库则直接用http来处理
        tbuff:del()
        tbuff:copy(0, "GET /"..uri.."" .. " HTTP/1.1\r\n")
        tbuff:copy(nil,"Host: "..host..":"..ota_port.."\r\n")
        if filelen > 0 then --断网重连的话，只需要下载剩余的部分就行了
            tbuff:copy(nil,"Range: bytes=" .. total .. "-\r\n") 
        end
        
        tbuff:copy(nil,"Accept: application/octet-stream\r\n\r\n")
        log.info(tbuff:query())
        result = libnet.tx(taskName, 5000, netc, tbuff)
        rbuff:del()
        findhead = false
        while result do
            succ, param, ip, port = socket.rx(netc, rbuff)
            if not succ then
                log.info(tag, "服务器断开了", succ, param, ip, port)
                ret = 3
                break
            end
            if rbuff:used() > 0 then
                if findhead then
                    succ,fotaDone,nCache = fota.run(rbuff)
                    if succ then
                        total = total + rbuff:used()
                    else
                        log.error(tag, "写入异常，请至少在1秒后重试")
                        fota.finish(false)
                        done = true
                        break
                    end
                    log.info(tag, "收到服务器数据，长度", rbuff:used(), "fota结果", succ, done, "总共", filelen)
                    rbuff:del()
                    if fotaDone then
                        log.info(tag, "下载完成")
                        while true do
                            succ,fotaDone  = fota.isDone()
                            if fotaDone then
                                fota.finish(true)
                                log.info(tag, "FOTA完成")
                                done = true
                                ret = 0
                                break
                            end
                            sys.wait(100)
                        end
                        break
                    end
                else
                    rcvCache = rbuff:query()
                    d1,d2 = rcvCache:find("\r\n\r\n")
                    -- 打印出http response head
                    -- log.info(rcvCache:sub(1, d2))    
                    if d2 then
                        --状态行
                        _,d1,statusCode = rcvCache:find("%s(%d+)%s.-\r\n")
                        if not statusCode then
                            log.info(tag, "http没有状态返回")
                            ret = 4
                            break
                        end
                        statusCode = tonumber(statusCode)
                        if statusCode ~= 200 and statusCode ~= 206 then
                            log.info(tag, "http应答不OK", statusCode,rbuff:toStr(d2))
                            done = true
                            ret = 4
                            break
                        end
                        --应答头
                        for k,v in string.gmatch(rcvCache:sub(d1+1,d2-2),"(.-):%s*(.-)\r\n") do
                            rspHead[k] = v
                            if (string.upper(k)==string.upper("Transfer-Encoding")) and (string.upper(v)==string.upper("chunked")) then rcvChunked = true end
                        end
                        if filelen == 0 and not rcvChunked then 
                            if not rcvChunked then
                                filelen = tonumber(rspHead["Content-Length"] or "2147483647")
                            end
                        end
                        --未处理的body数据
                        rbuff:del(0, d2)
                        succ,fotaDone,nCache = fota.run(rbuff)
                        if succ then
                            total = total + rbuff:used()
                        else
                            log.error(tag, "写入异常，请至少在1秒后重试")
                            fota.finish(false)
                            done = true
                            break
                        end
                        log.info(tag, "收到服务器数据，长度", rbuff:used(), "fota结果", succ, done, "总共", filelen)
                        rbuff:del()

                        if fotaDone then
                            log.info(tag, "下载完成")
                            while true do
                                succ,fotaDone  = fota.isDone()
                                if fotaDone then
                                    fota.finish(true)
                                    log.info(tag, "FOTA完成")
                                    done = true
                                    ret = 0
                                    break
                                end
                                sys.wait(100)
                            end
                            break
                        end
                        
                    else
                        break
                    end
                    findhead = true
                end
            end 
            log.info(tag, "等待新数据到来")
            result, param = libnet.wait(taskName, 5000, netc)
            log.info(result, param)
            if not result then
                log.info(tag, "服务器断开了", result, param)
                break
            elseif not param then
                log.info(tag, "服务器没有数据", result, param)
                break
            end
        end
        libnet.close(taskName, 5000, netc)
        retry = retry + 1
    end
    cbFnc(ret)
    socket.release(netc)
    sysplus.taskDel(taskName)
    fota.finish(false)
end

--[[
fota升级
@api libfota.request(cbFnc,ota_url,storge_location, len, param1,ota_port,timeout,tls,server_cert, client_cert, client_key, client_password)
@function cbFnc 用户回调函数，回调函数的调用形式为：cbFnc(result) , 必须传
@string ota_url 升级URL, 若不填则自动使用合宙iot平台
@number/string storge_location 可选,fota数据存储的起始位置<br>如果是int，则是由芯片平台具体判断<br>如果是string，则存储在文件系统中<br>如果为nil，则由底层决定存储位置
@number len 可选,数据存储的最大空间
@userdata param1,可选,如果数据存储在spiflash时,为spi_device
@number ota_port 可选,请求端口,默认80
@number timeout 可选,请求超时时间,单位毫秒,默认20000毫秒
@boolean tls    可选,是否是加密传输，默认false
@string server_cert 可选,服务器ca证书数据
@string client_cert 可选,客户端ca证书数据
@string client_key 可选,客户端私钥加密数据
@string client_password 可选,客户端私钥口令数据
@return nil 无返回值
]]
function libfota.request(cbFnc,ota_url,storge_location, len, param1,ota_port,timeout,tls,server_cert, client_cert, client_key, client_password)
    sysplus.taskInitEx(fota_task, taskName, netCB, cbFnc,storge_location, len, param1,ota_url, ota_port,timeout or 30000,tls,server_cert, client_cert, client_key, client_password)
end

return libfota

