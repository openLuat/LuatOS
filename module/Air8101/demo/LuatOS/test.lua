
--声明本地的变量，在test.lua里面可以访问
local a = 1
local b = 2
--申明本地函数
local function read()
    log.info("test.read")
end
--申明本地函数
local function write()
    log.info("write")
end
--内部调用函数
write()
--申明函数,别的脚本文件可以通过require "test" 调用
function text()
    log.info("这是test.lua 的文本")
end
--循环定时器：，调用此函数会在core里面创建运行定时器，定时器时间到会把“定时器消息”，放到外部消息队列里
--sys.run()启动消息处理循环，从外部消息队列取到定时器消息后运行read函数
sys.timerLoopStart(read,1000)

sys.taskInit(function()
        while true do
        --生产者：发布这个消息，并把消息"TEST_wait"放到内部消息队列
        sys.publish("TEST_wait",a)--可以发布多个变量sys.publish("TEST",1,2,3)
         --生产者：发布这个消息，并把消息"TEST_subscribe"放到内部消息队列
        sys.publish("TEST_subscribe",b)--发布这个消息，此时所有在等的都会收到这条消息
       --调用此函数会在core里面创建运行定时器，定时器时间到会把“定时器消息”，放到外部消息队列里
        sys.wait(2000) --延时2秒，这段时间里可以运行其他代码
        end
end)

sys.taskInit(function()
        while true do
                 --消费者：在消息处理函数表中把协程ID和"TEST_wait"绑定
                 --此处阻塞等待TEST_wait消息，收到这个消息或者超过10秒，才会退出阻塞等待状态
                result, data = sys.waitUntil("TEST_wait", 10000)--等待超时时间10000ms，超过就返回false而且不等了
                if result == true then
                        log.info("rev",data)--输出a的值
                end
                --sys.wait(2000)
        end
end)
local function callBackTest(x,y,...)
        log.info("callBack",x)--输出b的值
end
--消费者：在消息处理函数表中把回调函数和"TEST_subscribe"绑定
--当收到TEST_subscribe消息时，会执行callBackTest 函数
sys.subscribe("TEST_subscribe",callBackTest)--单独订阅，可以当回调来用


