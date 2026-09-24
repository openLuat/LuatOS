--[[
@module  test_relay
@summary 继电器控制测试脚本（临时文件，正式发布前请删除）
@version 1.1
@date    2026.09.10
@usage
本脚本用于继电器模块（隔离口 UART1 / 从站地址 1 / 9600 8N1）的独立测试，
上电后自动循环执行全部继电器控制命令，便于核对接发的 Modbus 帧与继电器实际动作。

使用方法：
1、本文件放入 firmware/code/ 目录
2、在 main.lua 中 require "relay_ctrl" 之后临时增加一行：require "test_relay"
3、重新烧录运行，观察日志输出与继电器实际动作
4、测试完成后删除该 require 行（或删除本文件）

预期现象（隔离口接真实继电器模块时）：
- open(0)    → 通道0 继电器吸合 → 风扇转
- close(0)   → 通道0 继电器释放 → 风扇停
- open(1)    → 通道1 吸合 → LED 亮
- close(1)   → 通道1 释放 → LED 灭
- toggle(1)  → 通道1 状态翻转
- all_open() → 4 路全部吸合
- all_close()→ 4 路全部释放

预期发出帧（隔离口接电脑 485 调试助手，从站设为 1 时可抓包核对）：
- open(0)      : 01 05 00 00 FF 00 <CRC>
- close(0)     : 01 05 00 00 00 00 <CRC>
- toggle(0)    : 01 05 00 00 55 00 <CRC>
- open(1)      : 01 05 00 01 FF 00 <CRC>
- all_open()   : 01 0F 00 00 00 04 01 0F <CRC>
- all_close()  : 01 0F 00 00 00 04 01 00 <CRC>
- read_status(): 01 01 00 00 00 04 <CRC>
]]

local relay_ctrl = require "relay_ctrl"
local exmodbus = require "exmodbus"

-- 是否打开串口原始收发帧调试打印
-- true = 打印收发帧，便于核对帧内容与 CRC；测试完成可改为 false
local DEBUG_FRAME = true
exmodbus.debug(DEBUG_FRAME)

-- 每步之间的等待时间（毫秒），用于观察硬件动作
local STEP_WAIT = 5000

-- 执行单个测试步骤
-- @param name string 步骤名称
-- @param fn function 步骤执行函数，返回 false 或 nil 表示失败
local function run_step(name, fn)
    log.info("test_relay", ">>>>>>>>>> " .. name .. " <<<<<<<<<<")
    local ret = fn()
    if ret == false or ret == nil then
        log.warn("test_relay", name .. " 执行失败（未接从站时超时属正常）")
    end
    sys.wait(STEP_WAIT)
end

-- 继电器测试主任务
sys.taskInit(function()
    sys.wait(3000) -- 等待系统与串口初始化完成
    log.info("test_relay", "========= 继电器测试开始（隔离口 UART1 / 从站1 / 9600 8N1）=========")

    while true do
        -- 先回读一次实际状态，校准本地缓存，避免后续 toggle 判断偏差
        run_step("回读状态 read_status（校准缓存）", function() return relay_ctrl.read_status() end)

        run_step("开风扇 open(0)",  function() return relay_ctrl.open(0)  end)
        run_step("关风扇 close(0)", function() return relay_ctrl.close(0) end)

        run_step("开LED open(1)",   function() return relay_ctrl.open(1)  end)
        run_step("关LED close(1)",  function() return relay_ctrl.close(1) end)

        run_step("翻转LED toggle(1)",          function() return relay_ctrl.toggle(1) end)
        run_step("翻转LED toggle(1)（翻回）",  function() return relay_ctrl.toggle(1) end)

        run_step("全开 all_open",  function() return relay_ctrl.all_open()  end)
        run_step("全关 all_close", function() return relay_ctrl.all_close() end)

        run_step("回读全部状态 read_status", function() return relay_ctrl.read_status() end)

        log.info("test_relay", "========= 一轮测试完成，3 秒后重新开始 =========")
        sys.wait(3000)
    end
end)
