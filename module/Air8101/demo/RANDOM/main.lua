PROJECT = "cryptodemo"
VERSION = "1.0.0"
-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()

    sys.wait(1000)
    -- ---------------------------------------
    log.info("随机数测试")
    math.randomseed(os.time())
    for i=1, 10 do
         sys.wait(100)
         log.info("crypto", "真随机数",string.unpack("I",crypto.trng(4)))
         log.info("crypto", "伪随机数",math.random()) -- 输出的是浮点数,不推荐
         log.info("crypto", "伪随机数",math.random(100)) --输出1-100之间随机数
         log.info("crypto", "伪随机数",math.random(1, 65525)) -- 不推荐
    end
    log.info("crypto", "ALL Done")
    sys.wait(100000)
end)

sys.run()