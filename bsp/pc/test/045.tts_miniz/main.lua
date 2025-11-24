
_G.sys = require("sys")

sys.taskInit(function()
    local fd = io.open("/luadb/tts.irf")
    local s1 = 0
    local s2 = 0
    local s3 = 0
    while true do
       local data = fd:read(32*1024)
       if not data or #data == 0 then break end
       local gzip = miniz.compress(data)
       local fz = fastlz.compress(data)
       s1 = s1 + #data
       s2 = s2 + #gzip
       s3 = s3 + #fz

       log.info("分片大小", #data, #gzip, #fz)
    end
    fd:close()
    log.info("gzip  ", s1, s2, (s1 - s2) // 1024, (s2 * 100) // s1)
    log.info("fastlz", s1, s3, (s1 - s3) // 1024, (s3 * 100) // s1)
end)

sys.run()
