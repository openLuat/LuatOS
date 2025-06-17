--加载AirVOC_1000驱动文件
local air_voc = require "AirVOC_1000"


--每隔1秒读取一次TVOC数据
local function read_voc_task_func()
    --打开voc硬件
    air_voc.open()

    while true do
        --读取TVOC的ppb，ppm，quality_level值
        local ppb = air_voc.get_ppb()
        local ppm = air_voc.get_ppm()
        local level, description = air_voc.get_quality_level()
        
        --读取成功
        if ppb then
            log.info("空气质量", 
                string.format("TVOC: ppb %d, ppm %.3f, 等级 %d(%s)", 
                ppb, ppm, level, description))
        --读取失败
        else
            log.error("空气质量", "读取数据失败")
        end

        --等待1秒
        sys.wait(1000)
    end

    --关闭voc硬件
    air_voc.close()
end

--创建一个task，并且运行task的主函数read_voc_task_func
sys.taskInit(read_voc_task_func)

