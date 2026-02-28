PROJECT = "tcptest"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {"xu"}

-- 引入测试套件和测试运行器模块
testrunner = require("testrunner")

-- 载入需要测试的模块
tcp_tests = require("tcp_test")


sysplus.taskInitEx(function()
    -- 这个任务是用 sysplus.taskInitEx 创建的，所以可以使用 libnet
    
    -- 运行批量测试
    testrunner.runBatch("tcp_demo", {
        {testTable = tcp_tests, testcase = "tcp测试"}
    })
end, "TCP_ECHO_TASK")
sys.run()