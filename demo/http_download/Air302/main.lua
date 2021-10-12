
-- 必须有PROJECT和VERSION这两个信息
PROJECT = "httpdw"
VERSION = "1.0.0"

local sys = require "sys"

sys.taskInit(function()
    while 1 do
        if socket.isReady() then
            -- 延时2秒,明显减少DNS失败的概率
            sys.wait(2000)
            -- AGPS文件的下载路径,只适用于Air530
            local url = "http://download.openluat.com/9501-xingli/brdcGPD.dat_rda"
            -- local url = "http://nutzam.com/httpget" -- 大小刚好4000 byte
            http.get(url, {dw="/agps.bin"}, function(code,headers,body)
                log.info("agps", "download", code)
            end)
            -- sys.wait(60*60*1000) -- 一小时检查一次
            sys.wait(4 * 60* 60*1000) -- 4小时检查一次
        else
            sys.wait(3000)
        end
    end
end)

-- 结尾总是这一句哦
sys.run()
