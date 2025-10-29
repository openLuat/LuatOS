
local function demo_http_get_gzip()
    -- 这里用 和风天气 的API做演示
    -- 这个API的响应, 总会gzip压缩过, 需要配合miniz库进行解压
    local code, headers, body = http.request("GET", "https://devapi.qweather.com/v7/weather/now?location=101010100&key=0e8c72015e2b4a1dbff1688ad54053de").wait()
    log.info("http.gzip", code)
    if code == 200 then
        local re = miniz.uncompress(body:sub(11), 0)
        log.info("和风天气", re)
        if re then
            local jdata = json.decode(re)
            log.info("jdata", jdata)
            if jdata then
                log.info("和风天气", jdata.code)
                if jdata.now then
                    log.info("和风天气", "天气", jdata.now.text)
                    log.info("和风天气", "温度", jdata.now.temp)
                end
            end
        end
    end
end
