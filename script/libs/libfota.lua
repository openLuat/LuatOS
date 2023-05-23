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

local libfota = {}


local function fota_task(cbFnc,storge_location, len, param1,ota_url,ota_port,libfota_timeout,server_cert, client_cert, client_key, client_password)
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
    local ret
    if server_cert then
        
    end
    local code, headers, body = http.request("GET", ota_url, nil, nil, {fota=true,timeout = libfota_timeout},server_cert, client_cert, client_key, client_password).wait()
    log.info("http fota", code, headers, body)
    if code == 200 then
        if body == 0 then
            ret = 4
        else
            ret = 0
        end
    elseif code == -4 then
        ret = 1
    elseif code == -5 then
        ret = 3
    else
        ret = 4
    end
    cbFnc(ret)
end

--[[
fota升级
@api libfota.request(cbFnc,ota_url,storge_location, len, param1,ota_port,libfota_timeout,server_cert, client_cert, client_key, client_password)
@function cbFnc 用户回调函数，回调函数的调用形式为：cbFnc(result) , 必须传
@string ota_url 升级URL, 若不填则自动使用合宙iot平台
@number/string storge_location 可选,fota数据存储的起始位置<br>如果是int，则是由芯片平台具体判断<br>如果是string，则存储在文件系统中<br>如果为nil，则由底层决定存储位置
@number len 可选,数据存储的最大空间
@userdata param1,可选,如果数据存储在spiflash时,为spi_device
@number ota_port 可选,请求端口,默认80
@number libfota_timeout 可选,请求超时时间,单位毫秒,默认30000毫秒
@string server_cert 可选,服务器ca证书数据
@string client_cert 可选,客户端ca证书数据
@string client_key 可选,客户端私钥加密数据
@string client_password 可选,客户端私钥口令数据
@return nil 无返回值
]]
function libfota.request(cbFnc,ota_url,storge_location, len, param1,ota_port,libfota_timeout,server_cert, client_cert, client_key, client_password)
    sys.taskInit(fota_task, cbFnc,storge_location, len, param1,ota_url, ota_port,libfota_timeout or 30000,server_cert, client_cert, client_key, client_password)
end

return libfota

