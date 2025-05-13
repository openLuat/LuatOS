--模块运行从 main.lua 开始运行,先调用必须的库(例如:sys 库)，然后运行代码，创建任务，最后 sys.run 收尾。
PROJECT = "TEST"  --逐行运行:从这一行开始运行
VERSION = "2.0.0"

--请求底层系统接口模块
sys = require("sys")
sysplus = require("sysplus")
libnet = require "libnet"

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

--加载test.lua脚本文件
require "test"
--调用test.lua脚本文件的函数
text()

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
--sys.run()用来内部和外部消息处理循环，遍历消息队列的消息，找到对应的函数来执行。
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
