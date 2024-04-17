--[[
@module libfota2
@summary fota升级v2
@version 1.0
@date    2024.04.09
@author  wendal
@demo    fota2
@usage
--用法实例
local libfota2 = require("libfota2")

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
        rtos.reboot()   --如果还有其他事情要做,自行决定reboot的时机
    end
end

--下方示例为合宙iot平台,地址:http://iot.openluat.com 
libfota2.request(libfota_cb)

--如使用自建服务器,自行更换url
-- 对自定义服务器的要求是:
-- 若需要升级, 响应http 200, body为升级文件的内容
-- 若不需要升级, 响应300或以上的代码,务必注意
local opts = {url="http://xxxxxx.com/xxx/upgrade"}
-- opts的详细说明, 看后面的函数API文档
libfota2.request(libfota_cb, opts)

-- 若需要定时升级
-- 合宙iot平台
sys.timerLoopStart(libfota2.request, 4*3600*1000, libfota_cb)
-- 自建平台
sys.timerLoopStart(libfota2.request, 4*3600*1000, libfota_cb, opts)
]]

local sys = require "sys"
require "sysplus"

local libfota2 = {}


local function fota_task(cbFnc, opts)
    local ret = 0
    local code, headers, body = http.request(opts.method, opts.url, opts.headers, opts.body, opts, opts.server_cert, opts.client_cert, opts.client_key, opts.client_password).wait()
    -- log.info("http fota", code, headers, body)
    if code == 200 or code == 206 then
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
        log.info("fota", code, body)
        ret = 4
    end
    cbFnc(ret)
end

--[[
fota升级
@api libfota.request(cbFnc, opts)
@table fota参数, 后面有详细描述
@function cbFnc 用户回调函数，回调函数的调用形式为：cbFnc(result) , 必须传
@return nil 无返回值
@usaga

-- opts参数说明, 所有参数都是可选的
-- 1. opts.url string 升级所需要的URL, 若使用合宙iot平台,则不需要填
-- 2. opts.version string 版本号, 默认是 BSP版本号.x.z格式
-- 3. opts.timeout int 请求超时时间, 默认300000毫秒,单位毫秒
-- 4. opts.project_key string 合宙IOT平台的项目key, 默认取全局变量PRODUCT_KEY. 自建服务器不用填
-- 5. opts.imei string 设备识别码, 默认取IMEI(Cat.1模块)或WLAN MAC地址(wifi模块)或MCU唯一ID
-- 6. opts.firmware_name string 固件名称,默认是 _G.PROJECT.. "_LuatOS-SoC_" .. rtos.bsp()
-- 7. opts.server_cert string 服务器证书, 默认不使用
-- 8. opts.client_cert string 客户端证书, 默认不使用
-- 9. opts.client_key string 客户端私钥, 默认不使用
-- 10. opts.client_password string 客户端私钥口令, 默认不使用
-- 11. opts.method string 请求方法, 默认是GET
-- 12. opts.headers table 额外添加的请求头,默认不需要
-- 13. opts.body string 额外添加的请求body,默认不需要
]]
function libfota2.request(cbFnc, opts)
    if not opts then
        opts = {}
    end
    if fota then
        opts.fota = true
    else
        os.remove("/update.bin")
        opts.dst = "/update.bin"
    end
    if not cbFnc then
        cbFnc = function() end
    end
    -- 处理URL
    if not opts.url then
        opts.url = "http://iot.openluat.com/api/site/firmware_upgrade"
    end
    if opts.url:sub(1, 4) ~= "###" and not opts.url_done then
        -- 补齐project_key函数
        if not opts.project_key then
            opts.project_key = _G.PRODUCT_KEY
            if not opts.project_key then
                log.error("fota", "iot.openluat.com need PRODUCT_KEY!!!")
                cbFnc(5)
                return
            end
        end
        -- 补齐version参数
        if not opts.version then
            local x,y,z = string.match(_G.VERSION,"(%d+).(%d+).(%d+)")
            opts.version = rtos.version():sub(2) .. "." .. x.."."..z
        end
        -- 补齐firmware_name参数
        if not opts.firmware_name then
            opts.firmware_name = _G.PROJECT.. "_LuatOS-SoC_" .. rtos.bsp()
        end
        -- 补齐imei参数
        if not opts.imei then
            local imei = ""
            if mobile then
                imei = mobile.imei()
            elseif wlan and wlan.getMac then
                imei = wlan.getMac()
            else
                imei = mcu.unique_id():toHex()
            end
            opts.imei = imei
        end

        -- 然后拼接到最终的url里
        opts.url = string.format("%s?imei=%s&project_key=%s&firmware_name=%s&version=%s", opts.url, opts.imei, opts.project_key, opts.firmware_name, opts.version)
    else
        opts.url = opts.url:sub(4)
        opts.url_done = true
    end
    -- 处理method
    if not opts.method then
        opts.method = "GET"
    end
    log.info("fota.url", opts.method, opts.url)
    log.info("fota.imei", opts.imei)
    log.info("fota.project_key", opts.project_key)
    log.info("fota.firmware_name", opts.firmware_name)
    log.info("fota.version", opts.version)
    sys.taskInit(fota_task, cbFnc, opts)
end

return libfota2
