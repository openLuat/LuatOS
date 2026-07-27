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
            因为历史原因,YYY这三位数字必须存在,但是没有任何用处,可以一直写为999
        如果不使用合宙iot.openluat.com进行远程升级,根据自己项目的需求,自定义格式即可
]]
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "iRTU"
VERSION = "5.0.5"

--联网成功获取配置之后，代码里会将PRODUCT_KEY更新为当前项目下的KEY值进行升级，所以这里写死为默认值
--如果需要手动修改KEY请参考https://docs.openluat.com/air780epm/luatos/app/ota/fota/
--此KEY值仅针对合宙官方IOT平台FOTA，如果使用其他平台，可以不需要关注该参数
PRODUCT_KEY = "0LkZx9Kn3tOhtW7uod48xhilVNrVsScV" 

log.info("main", PROJECT, VERSION)

local rfa = require("rfa")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

-- 检查是否为RFA模式, 用mobile.rfTestParam接口是否存在来判断当前固件是否支持RFA模式
if rfa and mobile.rfTestParam then
    -- 通过自发送 AT+ECNPICFG? 查询 rfCaliDone 和 rfNSTDone
    -- 两者都为1表示RFA校准流程全部通过；否则禁止加载irtu, 进入RFA校准模式
    local resp = rfa.dispatch("AT+ECNPICFG?")
    local rfCaliDone, rfNSTDone = 0, 0
    if resp then
        rfCaliDone, rfNSTDone = resp:match('"rfCaliDone":(%d+),"rfNSTDone":(%d+)')
    end
    rfCaliDone = tonumber(rfCaliDone) or 0
    rfNSTDone = tonumber(rfNSTDone) or 0
    log.info("main", "rfCaliDone", rfCaliDone, "rfNSTDone", rfNSTDone)
    if rfCaliDone == 1 and rfNSTDone == 1 then
        -- 校准已完成: 允许加载irtu脚本, 再通过 AT+SETCFG? 查询是否处于rfa模式
        -- 只有 rfa_mode 明确为(false)才退出rfa模式, VUART_0归irtu, 正常处理irtu数据
        -- 读不到配置或rfa_mode为(true): 处于rfa模式, VUART_0归rfa的AT服务器, 禁用irtu的VUART_0数据回调
        local cfg_resp = rfa.dispatch("AT+SETCFG?")
        local rfa_mode = cfg_resp and cfg_resp:match('"rfa_mode"%s*,%s*"(%a+)"')
        log.info("main", "rfa_mode", rfa_mode)
        if rfa_mode == "false" then
            log.info("main", "已退出rfa模式, 进入iRTU模式")
        else
            log.info("main", "当前处于rfa模式, 禁用irtu的VUART_0数据回调")
            -- 启动 RFA AT 服务器，绑定到 USB 虚拟串口 VUART_0
            -- 波特率对虚拟串口无实际意义，但保持 115200 与产线工具一致
            rfa.start(uart.VUART_0, 115200)
            -- 置位全局标志, 通知irtu的driver不要注册VUART_0的数据回调
            _G.IRTU_DISABLE_VUART = true
        end
        -- 校准完成后无论是否退出rfa模式都加载irtu_main模块
        require "irtu_main"
    else
        -- 校准未完成: 禁止require irtu代码, VUART_0只响应rfa的校准指令
        log.info("main", "RFA校准未完成，进入RFA校准模式，禁止加载irtu")
        rfa.start(uart.VUART_0, 115200)
    end
else
    log.info("main", "rfa模块未加载，默认iRTU模式")
    --加载irtu_main模块
    require "irtu_main"
end


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
