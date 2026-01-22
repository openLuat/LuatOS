--[[
@module  test_adc
@summary ADC功能测试
@version 1.0
@date    2025.07.15
@author  王城钧
@usage
本功能模块演示的内容为：
1. ADC通道配置与量程设置
2. 数据采集并处理
3. 循环打印处理过的ADC数据

本文件没有对外接口,直接在main.lua中require "test_adc"就可以加载运行；
]]

--[[
1. Air8101内部ADC接口为12bits,ADC量程为0-2.4V
2. Air8101有ADC1，ADC2，ADC3，ADC4，ADC5，ADC6，ADC10，ADC12，ADC13，ADC14，一共10路外部ADC；
这10路ADC复用的对应关系为：
ADC1 对应 ADC10；
ADC2 对应 ADC12；
ADC3 对应 ADC13；
ADC4 对应 ADC14；
ADC5 和 ADC6没有对应的其他ADC通道；
每个通道对应的关系如下：例如ADC1对应通道1
3. 特殊通道,CPU内部温度Temp -- adc.CH_CPU,主供电脚电压 VBAT -- adc.CH_VBAT
]]

local function process_channel(channel_samples, tag)
    if #channel_samples > 2 then
        -- 升序排序
        table.sort(channel_samples)
        
        -- 创建剔除极值后的新数组
        local trimmed = {}
        for i = 2, #channel_samples-1 do
            table.insert(trimmed, channel_samples[i])
        end
        
        -- 计算平均值
        local sum = 0
        for _, v in ipairs(trimmed) do
            sum = sum + v
        end
        local avg_value = sum / #trimmed

        -- 根据tag进行不同处理  
        if tag == "CPU TEMP" then  
            log.info(tag, string.format("温度值: %.2f ℃(样本数:%d)", avg_value/1000, #trimmed+2))  
        else  
            log.info(tag, string.format("处理值: %.2f mV (样本数:%d)", avg_value, #trimmed+2)) 
        end  
        
        -- -- 格式化输出
        -- log.info(tag, string.format("处理值: %.2f mV (样本数:%d)", avg_value, #trimmed+2))
    else
        log.info(tag, "样本不足无法处理")
    end
end

-- 主采集函数
function adc_all_func()
    local num_samples = 10  -- 每个通道采集样本数（可配置）
    local samples = {
        [1] = {},  -- 通道1
        [2] = {},  -- 通道2
        [3] = {},  -- 通道3
        [4] = {},  -- 通道4
        [5] = {},  -- CH_CPU
        [6] = {}   -- CH_VBAT
    }
    
    while true do
        sys.wait(1000)  -- 延时1秒,为了方便观察luatools日志,非必须
        
        -- 通道1采集处理
        -- 此演示对通道1外加了1.2V电压,方便观察1.2V外部供电下ADC的精准度。
        adc.open(1)
        for _ = 1, num_samples do
            table.insert(samples[1], adc.get(1))
        end
        adc.close(1)
        process_channel(samples[1], "adc通道1")
        
        -- 通道2采集处理
        -- 此演示对通道2外加2.3V电压,方便观察2.3V外部供电下ADC的精准度。
        adc.open(2)
        for _ = 1, num_samples do
            table.insert(samples[2], adc.get(2))
        end
        adc.close(2)
        process_channel(samples[2], "adc通道2")

        -- 通道3采集处理
        -- 此演示对通道3外加2.3V电压,方便观察2.3V外部供电下ADC的精准度。
        adc.open(3)
        for _ = 1, num_samples do
            table.insert(samples[3], adc.get(3))
        end
        adc.close(3)
        process_channel(samples[3], "adc通道3")

        -- 通道4采集处理
        -- 此演示对通道4外加了1.2V电压,方便观察1.2V外部供电下ADC的精准度。
        adc.open(4)
        for _ = 1, num_samples do
            table.insert(samples[4], adc.get(4))
        end
        adc.close(4)
        process_channel(samples[4], "adc通道4")

        -- CPU温度通道采集处理
        adc.open(adc.CH_CPU)
        for _ = 1, num_samples do
            table.insert(samples[5], adc.get(adc.CH_CPU))
        end
        adc.close(adc.CH_CPU)
        process_channel(samples[5], "CPU TEMP")
        
        -- VBAT通道采集处理
        adc.open(adc.CH_VBAT)
        for _ = 1, num_samples do
            table.insert(samples[6], adc.get(adc.CH_VBAT))
        end
        adc.close(adc.CH_VBAT)
        process_channel(samples[6], "VBAT")
        
        -- 清空样本数组
        for i = 1, 6 do
            samples[i] = {}
        end
    end
end

sys.taskInit(adc_all_func)

