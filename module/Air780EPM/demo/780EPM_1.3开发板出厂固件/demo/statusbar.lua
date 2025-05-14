statusbar_780epm = {}

lbsLoc2 = require "lbsLoc2"

--状态栏数据 
statusbar_780epm.data = {
    -- 电池状态
    bat_level = 0, -- 电量等级 (0-4)
    sig_stren = 0, -- 4G信号强度 (0-4)
    net_ready = false,

    -- 天气信息
    weather = {
        text = "", -- 天气文本 ("晴", "雨"等)
        temp = "", -- 温度
        humidity = "", -- 湿度
        result = false, -- 是否获取成功
    },
    weather_icon = "/luadb/default.jpg"
}

local weather_icons = {
      ["云"] = "/luadb/cloudy.jpg",
      ["雨"] = "/luadb/rain.jpg",
      ["晴"] = "/luadb/sunny.jpg",
      ["雪"] = "/luadb/snow.jpg",
      ["阴"] = "/luadb/cloudyday.jpg",
      ["雾"] = "/luadb/sunny.jpg",
      ["风"] = "/luadb/wind.jpg"
}

function statusbar_780epm.get_bat_level()
    local data = statusbar_780epm.data
    adc.open(adc.CH_VBAT)
    local vbat = adc.get(adc.CH_VBAT)
    local dump_power = vbat/4200
    log.info("当前电量为：",dump_power,vbat)
    dump_rate = dump_power*100
    if dump_rate == 0 then
        data.bat_level = 0
    elseif dump_rate <= 25 then
        data.bat_level = 1
    elseif dump_rate <=50 then
        data.bat_level = 2
    elseif dump_rate <= 75 then
        data.bat_level = 3
    else
        data.bat_level = 4
    end
    log.info("bat_level:",data.bat_level)
end

function statusbar_780epm.get_sig_strength()
    local data = statusbar_780epm.data
    local cp = mobile.status()
    log.info("mobile status:", cp)

    if cp == 1 or cp == 5 then
        data.net_ready = true
    else 
        data.net_ready = false
        return
    end

    local c1 = mobile.csq()
    if c1 < 8 or c1 > 31 then -- "网络注册失败     
        data.sig_stren = 1
    elseif c1 <= 15 then -- 网络信号弱
        data.sig_stren = 2
    elseif c1 <= 26 then -- 网络信号正常
        data.sig_stren = 3
    else
        data.sig_stren = 4
    end
end

function statusbar_780epm.get_weather()
    local lbs_location
    local winfo
    local data = statusbar_780epm.data

    if not data.net_ready then
        return
    end

    mobile.reqCellInfo(15)
    sys.waitUntil("CELL_INFO_UPDATE", 3000)

    local lbs_lat, lbs_lng ,t =  lbsLoc2.request(5000, nil, nil, true)
    log.info("lat,lng",lbs_lat,lbs_lng)
    if lbs_lat and lbs_lng then
      lbs_location = lbs_lng..","..lbs_lat
    else
      lbs_location = "101010100"
    end
    
    log.info("lbs_location",lbs_location)
    local url = "https://devapi.qweather.com/v7/weather/now?location="..lbs_location.."&key=2c69d20742df4b3bbfa3c7006ce35210"
    local code, headers, body = http.request("GET", url).wait(300)
    log.info("url=",url)
    log.info("http.gzip", code)
    if code ~= 200 then
        return ""
    end

    log.info("21")
    local re = miniz.uncompress(body:sub(11), 0)
    log.info("和风天气", re)

    if re == nil or re == "" then
        return
    end

    local jdata = json.decode(re)
    log.info("jdata", jdata)
    if not jdata then
        return
    end
    log.info("和风天气", jdata.code,jdata.now)

    if not jdata.now then
        return
    end

    log.info("和风天气", "天气", jdata.now.text)

    data.weather.text = jdata.now.text
    data.weather.temp = jdata.now.temp
    data.weather.humidity = jdata.now.humidity
    data.weather.result = true

    for keyword, icon in pairs(weather_icons) do
        if string.find(data.weather.text, keyword) then
            data.weather_icon = icon
           break
        end
    end
end

return statusbar_780epm