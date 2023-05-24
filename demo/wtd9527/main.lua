PROJECT = 'wtd9527'
VERSION = '2.0.0'
LOG_LEVEL = log.LOG_INFO
log.setLevel(LOG_LEVEL )
require 'wtd9527'
local sys = require "sys"
_G.sysplus = require("sysplus")


sys.taskInit(function ()
    wtd9527.init(28)
    wtd9527.feed_dog(28)--28为看门狗控制引脚
    --wtd9527.set_time(1)--开启定时模式再打开此代码，否则无效
    while 1 do
    sys.wait(100)
    end
end)

sys.run()
