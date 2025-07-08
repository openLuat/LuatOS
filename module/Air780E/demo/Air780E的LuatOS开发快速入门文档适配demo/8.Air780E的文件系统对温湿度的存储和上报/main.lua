
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "filedemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    while 1 do
        sys.wait(5000)
        --采集温湿度数据,该引脚需要接开发板上一个带上拉5k电阻的引脚
        local hum,tem,result = sensor.dht1x(7,true)
        log.info("hum:",hum/100,"tem:",tem/100,result)

        if result then
            --[[打印文件系统信息
            @param1 获取是否成功
            @param2 总的block数量
            @param3 已使用的block数量
            @param4 block的大小,单位字节
            @param5 文件系统类型,例如lfs代表littlefs
            ]]
            log.info("result,总block,已使用block,block大小,类型",fs.fsstat())
            --拼接温湿度和结果数据
            local fullData = hum..tem..tostring(result)
            --将温湿度数据写入文件中
            local res_wri = io.writeFile("/dht1.txt", fullData)
            --打印写入结果
            log.info("writeFile result",res_wri)
            --读取温湿度数据
            local readData = io.readFile("/dht1.txt")
            --[[string.sub(s,i,j)
                返回字符串s中的位置i到位置j的数据
            ]]
            log.info("文件读取的数据","hum:",string.sub(readData,1,4)/100,"tem:",string.sub(readData,5,8)/100,string.sub(readData,9,12))
        else
            log.info("温湿度值校验失败")
        end

    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

-- tcs3472 下载固件和脚本
