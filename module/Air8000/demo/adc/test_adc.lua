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

1. Air8000内部ADC接口为12bits,ADC量程为0-3.6V
2. Air8000内部具有4路通用ADC通道,通道0 -- 3
3. 特殊通道,CPU内部温度Temp -- adc.CH_CPU,主供电脚电压 VBAT -- adc.CH_VBAT
4. 设置分压(adc.setRange)要在adc.open之前设置,否则无效!!
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
        [0] = {},  -- 通道0样本数组
        [1] = {},  -- 通道1
        [2] = {},  -- 通道2
        [3] = {},  -- 通道3
        [4] = {},  -- CH_CPU
        [5] = {}   -- CH_VBAT
    }
    
    while true do
        sys.wait(1000)  -- 延时1秒,为了方便观察luatools日志,非必须
        
        -- 通道0采集处理
        adc.setRange(adc.ADC_RANGE_MIN)  
        -- 设置ADC量程,注意量程设置一定要在adc.open()之前,通道0的量程设置为了adc.ADC_RANGE_MIN
        -- 此演示对通道0外加了1.2V电压,这样设置与通道1形成对比,方便观察1.2V外部供电下adc.ADC_RANGE_MAX和adc.ADC_RANGE_MIN两种量程的测量精准度。
        adc.open(0)
        for _ = 1, num_samples do
            table.insert(samples[0], adc.get(0))
        end
        adc.close(0)
        process_channel(samples[0], "adc通道0")

        -- 通道1采集处理
        adc.setRange(adc.ADC_RANGE_MAX) 
        -- 设置ADC量程,注意量程设置一定要在adc.open()之前,通道1的量程设置为了adc.ADC_RANGE_MAX
        -- 此演示对通道1外加了1.2V电压,这样设置与通道0形成对比,方便观察1.2V外部供电下adc.ADC_RANGE_MAX和adc.ADC_RANGE_MIN两种量程的测量精准度。
        adc.open(1)
        for _ = 1, num_samples do
            table.insert(samples[1], adc.get(1))
        end
        adc.close(1)
        process_channel(samples[1], "adc通道1")
        
        -- 通道2采集处理
        adc.setRange(adc.ADC_RANGE_MAX) 
        -- 设置ADC量程,注意量程设置一定要在adc.open()之前,通道2的量程设置为了adc.ADC_RANGE_MAX
        -- 此演示对通道2外加3.3V电压,这样设置可以与通道3形成对比,方便观察3.3V外部供电下adc.ADC_RANGE_MAX和adc.ADC_RANGE_MIN两种量程的测量精准度。
        adc.open(2)
        for _ = 1, num_samples do
            table.insert(samples[2], adc.get(2))
        end
        adc.close(2)
        process_channel(samples[2], "adc通道2")
        
        -- 通道3采集处理
        adc.setRange(adc.ADC_RANGE_MIN) 
        -- 设置ADC量程,注意量程设置一定要在adc.open()之前,通道3的量程设置为了adc.ADC_RANGE_MIN
        -- 此演示对通道3外加3.3V电压,这样设置可以与通道2形成对比,方便观察3.3V外部供电下adc.ADC_RANGE_MAX和adc.ADC_RANGE_MIN两种量程的测量精准度。
        adc.open(3)
        for _ = 1, num_samples do
            table.insert(samples[3], adc.get(3))
        end
        adc.close(3)
        process_channel(samples[3], "adc通道3")
        
        -- CPU温度通道采集处理
        adc.open(adc.CH_CPU)
        for _ = 1, num_samples do
            table.insert(samples[4], adc.get(adc.CH_CPU))
        end
        adc.close(adc.CH_CPU)
        process_channel(samples[4], "CPU TEMP")
        
        -- VBAT通道采集处理
        adc.open(adc.CH_VBAT)
        for _ = 1, num_samples do
            table.insert(samples[5], adc.get(adc.CH_VBAT))
        end
        adc.close(adc.CH_VBAT)
        process_channel(samples[5], "VBAT")
        
        -- 清空样本数组
        for i = 0, 5 do
            samples[i] = {}
        end
    end
end

sys.taskInit(adc_all_func)

