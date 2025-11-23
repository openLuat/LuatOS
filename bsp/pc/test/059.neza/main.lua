
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

_G.sys = require("sys")
require "sysplus"

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    -- socket.sslLog(3)
    local url = "https://piaofang.maoyan.com/i/api/movie/getBoxShow?movieId=1294273&boxLevel=1"
    local rheaders = {["User-Agent"]="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36 Edg/91.0.864.67"}
    local code, headers, body = http.request("GET", url, rheaders, nil, {timeout=3000}).wait()
    log.info("http", code, json.encode(headers))
    if code and code == 200 then
        -- log.info("http", "body", body)
        local jdata = json.decode(body)
        -- 总票房
        local total = jdata["data"]["boxInfoDataRes"][1]["boxSummaryList"][1]["valueDesc"]
        -- 今日票房
        local today = jdata["data"]["boxDatas"][1][19]["boxDesc"]

        log.info("http", "总票房", total .. "万")
        log.info("http", "今日票房", today .. "万")
    end
end)

sys.run()
