--[[
@module rtkv
@summary 远程KV数据库
@version 1.0
@date    2023.07.17
@author  wendal
@tag LUAT_USE_NETWORK
@usage

-- 是否还在为上报几个数据值而烦恼?
-- 是否还在为数据存入数据库而头痛不已?
-- 没有外网服务器, 内网穿透又很麻烦?
-- 不懂mqtt, 也没有下发需求, 只是想上报一些值?

-- 那本API就很适合您
-- 它可以:
--   将数据存到服务器,例如温湿度,GPS坐标,GPIO状态
--   读取服务器的数据,例如OTA信息
--   服务器会保存历史记录,也支持绘制成图表
-- 它不可以:
--   实时下发数据给设备
--   上传巨量数据

-- 网站首页, 输入设备识别号就能看数据 https://rtkv.air32.cn
-- 示例设备 http://rtkv.air32.cn/d/6055F9779010

-- 场景举例1, 上报温湿度数据到服务器, 然后网站查看地址是 XXX
rtkv.setup()
sys.taskInit(function()
    sys.waitUntil("IP_READY")
    while 1 do
        local val,result = sensor.ds18b20(17, true) 
        if result then
            rtkv.set("ds18b20_temp", val)
        end
        sys.wait(60*1000) -- 一分钟上报一次
    end
end)

-- 场景举例2, 简易版OTA
rtkv.setup()
sys.taskInit(function()
    sys.waitUntil("IP_READY")
    sys.wait(1000)
    while 1 do
        local ota_version = rtkv.get("ota_version")
        if ota_version and ota_version ~= _G.VERSION then
            local ota_url = rtkv.get("ota_url")
            if ota_url then
                -- 执行OTA, 以esp32c3为例
                local code = http.request("GET", ota_url, nil, nil, {dst="/update.bin"}).wait()
                if code and code == 200 then
                    log.info("ota", "ota包下载完成, 5秒后重启")
                    sys.wait(5000)
                    rtos.reboot()
                end
            end
        end
        sys.wait(4*3600*1000) -- 4小时检查一次
    end
end)

-- 场景举例3, 非实时下发控制
rtkv.setup()
sys.taskInit(function()
    local LED = gpio.setup(27, 0, nil, gpio.PULLUP)
    local INPUT = gpio.setup(22, nil)
    sys.waitUntil("IP_READY")
    sys.wait(1000)
    while 1 do
        local gpio27 = rtkv.get("gpio27")
        if gpio27 then
            LED(gpio27 == "1" and 1 or 0)
        end
        rtkv.set("gpio22", INPUT()) -- 上报GPIO22的状态
        sys.wait(15*1000) -- 15秒查询一次
    end
end)
]]

local rtkv = {}

--[[
rtkv初始化
@api rtkv.setup(conf)
@table 配置信息,详细说明看下面的示例
@return nil 没有返回值
@usage
-- 本函数只需要调用一次, 通常在main.lua里

-- 默认初始化, 开启了调试日志
rtkv.setup()
-- 初始化,并关闭调试日志
rtkv.setup({nodebug=true})
-- 详细初始化, 可以只填需要配置的项
rtkv.setup({
    apiurl = "http://rtkv.air32.cn", -- 服务器地址,可以自行部署 https://gitee.com/openLuat/luatos-service-rtkv
    device = "abc", -- 设备识别号,只能是英文字符+数值,区别大小写
    token = "123456", -- 设备密钥, 默认是设备的唯一id, 即mcu.unique_id()
    nodebug = false,  -- 关闭调试日志,默认false
    timeout = 3000, -- 请求超时, 单位毫秒, 默认3000毫秒
})

-- 关于device值的默认值
-- 若支持4G, 会取IMEI
-- 若支持wifi, 会取MAC
-- 其余情况取 mcu.unique_id() 即设备的唯一id
]]
function rtkv.setup(conf)
    if not conf then
        conf = {}
    end
    rtkv.conf = conf
    if not rtkv.conf.apiurl then
        conf.apiurl = "http://rtkv.air32.cn"
    end
    if not conf.device then
        if mobile then
            conf.device = mobile.imei()
        elseif wlan then
            conf.device = wlan.getMac()
        else
            conf.device = mcu.unique_id():toHex()
        end
    end
    if not conf.token then
        conf.token = mcu.unique_id():toHex()
    end
    if not conf.timeout then
        conf.timeout = 3000
    end
    if not conf.nodebug then
        -- log.info("rtkv", "apiurl", conf.apiurl)
        log.info("rtkv", "device", conf.device)
        log.info("rtkv", "token", conf.token)
        log.info("rtkv", "pls visit", conf.apiurl .. "/d/" .. conf.device)
    end
    return true
end

--[[
设置指定键对应的值
@api rtkv.set(key, value)
@string 键, 不能为nil,建议只使用英文字母/数字
@string 值, 不能为nil,一般建议不超过512字节
@return bool   成功返回true, 否则返回nil
@usage

-- 如果关心执行结果, 则需要在task里执行
-- 非task上下文, 会返回nil, 然后后台执行
rtkv.set("age", "18")
rtkv.set("version", _G.VERSION)
rtkv.set("project", _G.PROJECT)

-- 关于值的类型的说明
-- 支持传入字符串,布尔值,整数,浮点数, 最终还是会转为字符串上传
-- 通过 rtkv.get 获取值的时候, 返回的值的类型也会是字符串
]]
function rtkv.set(key, value)
    if not rtkv.conf or not key or not value then
        return
    end
    local url = rtkv.conf.apiurl .. "/api/rtkv/set?"
    url = url .. "device=" .. rtkv.conf.device
    url = url .. "&token=" .. rtkv.conf.token
    url = url .. "&key=" .. tostring(key):urlEncode()
    url = url .. "&value=" .. tostring(value):urlEncode()
    if rtkv.conf.debug then
        log.debug("rtkv", url)
    end
    local co, ismain = coroutine.running()
    if ismain then
        sys.taskInit(http.request, "GET", url)
    else
        local code, headers, body = http.request("GET", url, nil, nil, {timeout=rtkv.conf.timeout}).wait()
        if rtkv.conf.debug then
            log.info("rtkv", code, body)
        end
        if code and code == 200 and body == "ok" then
            return true
        end
    end
end

--[[
批量设置键值
@api rtkv.sets(datas)
@table 需要设置的键值对
@return bool   成功返回true, 否则返回nil
@usage
-- 如果关心执行结果, 则需要在task里执行
-- 非task上下文, 会返回nil, 然后后台执行
rtkv.sets({
    age = "18",
    vbat = 4193,
    temp = 23423
})
]]
function rtkv.sets(datas)
    local conf = rtkv.conf
    if not conf or not datas then
        return
    end
    local url = conf.apiurl .. "/api/rtkv/sets"
    local rbody = json.encode({
        device = conf.device,
        token  = conf.token,
        data = datas
    })
    if not rbody then
        log.info("rtkv", "rbody is nil")
        return
    end
    if not conf.nodebug then
        log.debug("rtkv", url, rbody)
    end
    local rheaders = {}
    rheaders["Content-Type"] = "application/json"
    local co, ismain = coroutine.running()
    if ismain then
        sys.taskInit(http.request, "POST", url, rheaders, rbody, {timeout=conf.timeout})
    else
        local code, headers, body = http.request("POST", url, rheaders, rbody, {timeout=conf.timeout}).wait()
        if not conf.nodebug then
            log.info("rtkv", code, body)
        end
        if code and code == 200 and body == "ok" then
            return true
        end
    end
end

--[[
获取指定键对应的值
@api rtkv.get(key)
@string 键, 不能为nil,长度需要2字节以上
@return string 成功返回字符,其他情况返回nil
@usage
-- 注意, 必须在task里执行,否则必返回nil
local age = rtkv.get("age")
]]
function rtkv.get(key)
    local conf = rtkv.conf
    if not conf or key then
        return
    end
    local url = conf.apiurl .. "/api/rtkv/get?"
    url = url .. "device=" .. conf.device
    url = url .. "&token=" .. conf.token
    url = url .. "&key=" .. tostring(key):urlEncode()
    if not conf.nodebug then
        log.debug("rtkv", "url", url)
    end
    local co, ismain = coroutine.running()
    if ismain then
        log.warn("rtkv", "must call in a task/thread")
        return
    else
        local code, headers, body = http.request("GET", url, nil, nil, {timeout=conf.timeout}).wait()
        if not conf.nodebug then
            log.info("rtkv", code, body)
        end
        if code and code == 200 and body == "ok" then
            return true
        end
    end
end

return rtkv
