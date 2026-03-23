--[[
@module  test_adc_custom
@summary 自定义ADC功能测试
@version 2.0
@date    2026.03.09
@usage
本功能模块演示的内容为：
1. 同时测量ADC1、ADC5（外部供电1.2V）
2. 同时测量ADC2、ADC6（外部供电3.3V）
3. 数据采集并处理
4. 循环打印处理过的ADC数据

本文件没有对外接口,直接在main.lua中require "test_adc_custom"就可以加载运行；
]]

--[[
1. Air1601内部ADC接口为12bits,ADC量程为0-3.6V
2. Air1601内部具有4路通用ADC通道,通道1 、2、5、6
3. 设置分压(adc.setRange)要在adc.open之前设置,否则无效!!
4. ADC1/5和ADC2/6为复用通道，本示例同时测试这些通道
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

        -- 格式化输出
        log.info(tag, string.format("处理值: %.2f mV (样本数:%d)", avg_value, #trimmed+2))
    else
        log.info(tag, "样本不足无法处理")
    end
end

-- 主采集函数
function adc_custom_func()
    local num_samples = 10  -- 每个通道采集样本数（可配置）
    local samples = {
        [1] = {},  -- ADC1通道样本数组
        [5] = {},  -- ADC5通道样本数组
        [2] = {},  -- ADC2通道样本数组
        [6] = {}   -- ADC6通道样本数组
    }
    
    while true do
        sys.wait(1000)  -- 延时1秒,为了方便观察luatools日志,非必须
        
        -- ADC1采集处理（外部供电1.2V）
        adc.setRange(adc.ADC_RANGE_MIN)  
        -- 设置ADC量程,注意量程设置一定要在adc.open()之前
        -- 对于1.2V电压，使用ADC_RANGE_MIN可以获得更高的精度
        adc.open(1)
        for _ = 1, num_samples do
            table.insert(samples[1], adc.get(1))
        end
        adc.close(1)
        process_channel(samples[1], "ADC1 (1.2V)")

        -- ADC5采集处理（外部供电1.2V）
        adc.setRange(adc.ADC_RANGE_MIN)  
        adc.open(5)
        for _ = 1, num_samples do
            table.insert(samples[5], adc.get(5))
        end
        adc.close(5)
        process_channel(samples[5], "ADC5 (1.2V)")

         -- ADC2采集处理（外部供电3.3V）
         adc.setRange(adc.ADC_RANGE_MAX) 
         -- 设置ADC量程,注意量程设置一定要在adc.open()之前
         -- 对于3.3V电压，使用ADC_RANGE_MAX可以获得合适的精度
         adc.open(2)
         for _ = 1, num_samples do
             table.insert(samples[2], adc.get(2))
         end
         adc.close(2)
         process_channel(samples[2], "ADC2 (3.3V)")

         -- ADC6采集处理（外部供电3.3V）
         adc.setRange(adc.ADC_RANGE_MAX) 
         adc.open(6)
         for _ = 1, num_samples do
             table.insert(samples[6], adc.get(6))
         end
         adc.close(6)
         process_channel(samples[6], "ADC6 (3.3V)")
        
        -- 清空样本数组
        for k, _ in pairs(samples) do
            samples[k] = {}
        end
    end
end

sys.taskInit(adc_custom_func)
