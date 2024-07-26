local t = {}

local attributes = {
    location = {
        lat = 0,
        lng = 0,
    },
    isCharging = false,
    battery = 0,
    step = 0,
    ledControl = false,
    redLed = true,
    blueLed = true,
    isFixed = "获取中",
    lat = "无数据",
    lng = "无数据",
    rsrp = 0,
    rsrq = 0,
    vbat = 0,
    audioStatus = "空闲",
    callStatus = "不支持",
    isGPSOn = true,
    sleepMode = false,
}

--已修改的数据，缓存在这里，等待上报
local reportTemp = {}

--初始化
function t.initial()
    sys.taskInit(function()
        sys.waitUntil("CLOUD_CONNECTED") -- 连接成功
        for k,v in pairs(reportTemp) do
            attributes[k] = v
        end
        --上报数据初始化一下
        ThingsCloud.reportAttributes(attributes)
        while true do
            local hasData = false
            for _,_ in pairs(reportTemp) do
                hasData = true
                break
            end
            if not hasData then
                --没数据，等待
                sys.waitUntil("ATTRIBUTES_UPDATED")
            end
            sys.wait(100)
            --有数据，复制数据
            local temp = {}
            for k,v in pairs(reportTemp) do
                temp[k] = v
            end
            reportTemp = {}
            --上报数据
            ThingsCloud.reportAttributes(temp)

            sys.wait(5500)--防止上报太频繁，最快5秒一次
        end
    end)
end

--修改数据
function t.set(k,v,fromCloud)
    --值没改变，不用处理
    if attributes[k] == v then
        return
    end
    --休眠模式下，只有sleepMode属性可以修改
    if attributes.sleepMode then
        log.info("attributes.set", "sleepMode",k,v)
        if fromCloud then--云端下发的数据只能修改sleepMode属性
            if k ~= "sleepMode" then
                return
            end
        else
            return
        end
    end
    if type(v) == "table" then
        local hasChange = false
        for k1,v1 in pairs(v) do
            if attributes[k][k1] ~= v1 then
                hasChange = true
                break
            end
        end
        if not hasChange then
            return
        end
    end
    attributes[k] = v
    --来自云端的数据不用缓存
    if not fromCloud then
        --缓存数据，等待上报
        reportTemp[k] = v
        sys.publish("ATTRIBUTES_UPDATED")
    end
end

--获取数据
function t.get(k)
    return attributes[k]
end

--获取所有数据
function t.all()
    return attributes
end

--刷新所有数据
function t.setAll()
    reportTemp = attributes
end

return t
