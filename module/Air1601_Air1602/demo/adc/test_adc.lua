--[[
@module  test_adc_custom
@summary 自定义ADC功能测试
@version 4.0
@date    2026.06.12
@usage
本功能模块演示的内容为：
1. 测量ADC通道 1-7, 9-15
2. 每个通道采集14次样本
3. 剔除2个最高值和2个最低值
4. 取中间10个值求平均并打印处理过程

本文件没有对外接口,直接在main.lua中require "test_adc_custom"就可以加载运行；
]]
-- Air1601/Air1602内部ADC接口为12bits,ADC量程为0-3.3V
-- 支持的ADC通道列表（测量哪几个ADC，就写对应的ADC编号）
-- Air1601 支持: ADC1, ADC2, ADC5, ADC6
-- Air1602 支持: ADC1-7, ADC9-15
local CHANNELS = {5, 1}
--[[
    数据处理函数
    对采集的原始样本进行处理：
    1. 将样本升序排序
    2. 剔除2个最小值和2个最大值（去极值）
    3. 取中间10个值计算平均值
    @param channel_samples 原始样本数组
    @param tag 通道标识，用于日志输出
]] 
local function process_channel(channel_samples, tag)
    if #channel_samples >= 14 then
        -- 对样本升序排序
        table.sort(channel_samples)
        log.info(tag, "排序后:", table.concat(channel_samples, ", "))

        -- 计算中间10个值的和（索引3到12，共10个）
        local sum = 0
        local valid_count = #channel_samples - 4
        for i = 3, #channel_samples - 2 do
            sum = sum + channel_samples[i]
        end
        -- 计算平均值
        local avg_value = sum / valid_count

        -- 输出最终处理值
        log.info(tag, string.format("处理值: %.2f mV", avg_value))
    else
        log.info(tag, "样本不足，无法处理（需要14个样本）")
    end
end

--[[
    主采集函数
    循环采集所有ADC通道的数据：
    1. 每5秒执行一次大循环
    2. 遍历CHANNELS中的所有通道
    3. 每个通道采集14次样本（每次间隔5ms）
    4. 调用process_channel处理数据
]]
function adc_custom_func()
    -- 每个通道采集的样本数量
    local num_samples = 14
    local dummy_reads = 5  -- 采集前的 dummy read 次数，让ADC采样电路稳定

    -- 打开所有ADC通道（只打开一次）
    for _, ch in ipairs(CHANNELS) do
        adc.open(ch)
        log.info(string.format("ADC%d", ch), "通道已打开")
    end

    sys.wait(1200)  -- -- ADC打开后延迟1200ms，让引脚电压稳定；当外部供电越低，需适当增加延时

    -- 主循环，每5秒采集一次
    while true do

        -- 遍历所有ADC通道
        for _, ch in ipairs(CHANNELS) do
            local samples = {}

            -- 先做几次 dummy read，让ADC采样电路稳定（避免第一次数据不准）
            for _ = 1, dummy_reads do
                adc.get(ch)
                sys.wait(2)
            end

            -- 循环采集14次样本
            for _ = 1, num_samples do
                table.insert(samples, adc.get(ch))
                sys.wait(5)
            end
            -- 处理并打印该通道数据
            process_channel(samples, string.format("ADC%d", ch))
            sys.wait(3000) -- 每3秒采集一次
        end
    end
end

-- 启动ADC采集任务
sys.taskInit(adc_custom_func)
