
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "bit64_test"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end


if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end



local function log_bit()
        log.info("按位取反，输出-6",bit.bnot(5))
        log.info("与,--输出1",bit.band(1,1))
        log.info("或，--输出3",bit.bor(1,2))
        log.info("异或结果为4",bit.bxor(2,3,5))
        log.info("逻辑左移，“100”，输出为4",bit.lshift(1,2))

        log.info("逻辑右移，“001”，输出为1",bit.rshift(4,2))
        log.info("算数右移，左边添加的数与符号有关，输出为0",bit.arshift(2,2))
        log.info("参数是位数，作用是1向左移动两位，打印出4",bit.bit(2))
        log.info("测试位数是否被置1",bit.isset(5,0))--第一个参数是是测试数字，第二个是测试位置.从右向左数0到7.是1返回true，否则返回false，该返回true
        log.info("测试位数是否被置1",bit.isset(5,1))--打印false
        log.info("测试位数是否被置1",bit.isset(5,2))--打印true
        log.info("测试位数是否被置1",bit.isset(5,3))--返回返回false
        log.info("测试位数是否被置0",bit.isclear(5,0))----与上面的相反
        log.info("测试位数是否被置0",bit.isclear(5,1))
        log.info("测试位数是否被置0",bit.isclear(5,2))
        log.info("测试位数是否被置0",bit.isclear(5,3))
        log.info("把0的第0，1，2，3位值为1",bit.set(0,0,1,2,3))--在相应的位数置1，打印15
        log.info("把5的第0，2位置为0",bit.clear(5,0,2))--在相应的位置置0，打印0
end

sys.taskInit(log_bit)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!