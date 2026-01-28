--[[
@module  main
@summary LuatOS用户应用脚本文件入口,总体调度应用逻辑
@version 5.0.0
@date    2026.01.27
@author  李源龙
@usage
本项目演示的功能为：
    合宙iRTU的功能，主要包括参数配置，串口，网络通道，预置信息，GPIO，GNSS定位，音频，数据流，任务等
]]
--[[
必须定义PROJECT和VERSION变量,Luatools工具会用到这两个变量,远程升级功能也会用到这两个变量
PROJECT：项目名,ascii string类型
        可以随便定义,只要不使用,就行
VERSION：项目版本号,ascii string类型
        如果使用合宙iot.openluat.com进行远程升级,必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字,三个X表示的数字可以相同,也可以不同,同理三个Y和三个Z表示的数字也是可以相同,可以不同
            因为历史原因,YYY这三位数字必须存在,但是没有任何用处,可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级,根据自己项目的需求,自定义格式即可
]]
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "iRTU"
VERSION = "5.0.0"

--联网成功获取配置之后，代码里会将PRODUCT_KEY更新为当前项目下的KEY值进行升级，所以这里写死为默认值
--如果需要手动修改KEY请参考https://docs.openluat.com/air780epm/luatos/app/ota/fota/
--此KEY值仅针对合宙官方IOT平台FOTA，如果使用其他平台，可以不需要关注该参数
PRODUCT_KEY = "0LkZx9Kn3tOhtW7uod48xhilVNrVsScV" 

log.info("main", PROJECT, VERSION)

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

--加载irtu_main模块
require "irtu_main"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
