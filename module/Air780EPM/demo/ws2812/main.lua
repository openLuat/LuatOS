--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2026.08.17
@author  杨乔杉
@usage
本demo演示的核心功能为：
演示WS2812 22×22 全彩点阵的多种动效，包括色块覆盖/灯珠检测、彩虹渐变、蛇形扫描、
星点闪烁、矩形收缩、滚动文字。用户可通过取消注释相应的 require 语句来启用不同的
功能模块进行测试。

适用产品范围：
  本 demo 仅适用于合宙 Air1780P / Air1780H。
  灯板尺寸不是 22×22 时，请修改 ws2812_config.lua 中的 LED_W / LED_H / LED_COUNT。

项目说明：
  本项目基于 LuatOS 脚本框架，驱动 22×22 共 484 颗 WS2812 全彩灯珠，
  通过 GPIO16 输出单线时序信号，实现多种动态灯光效果。
  默认启动"色块覆盖/灯珠检测"任务；其他效果模块以 require 注释的形式提供，
  调试时按需取消注释即可切换到对应效果，同一时间建议只启用一个循环任务。

硬件接线：
  WS2812 DIN → GPIO16 (PIN97)
  5V/GND     → 外接 5V 电源（亮度较高时建议 5V/10A 以上）

更多说明参考本目录下的readme.md文件
]]

--[[
必须定义 PROJECT 和 VERSION 两个全局变量：
  - PROJECT：项目名称，ASCII 字符串，Luatools 下载工具会用它来识别和区分项目；
  - VERSION：项目版本号，ASCII 字符串，远程升级（iotcloud/fota）时会根据版本号
             判断是否需要升级以及差分包的匹配。
两者都必须是 ASCII 字符串，不能包含中文或特殊字符，否则 Luatools 解析会异常。
]]
PROJECT = "WS2812_testdemo"
VERSION = "001.999.000"

-- 打印项目名和版本号，方便在 Luatools 串口日志中确认当前运行的固件版本
log.info("main", "project name is ", PROJECT, "version is ", VERSION)

-- 如果内核固件支持 errDump 功能（错误日志上报），此处进行配置。
-- 参数 true 表示开启，600 表示每 600 秒（10 分钟）上报一次缓存的错误日志。
-- 【强烈建议打开此处的注释】，方便在量产/调试阶段远程收集 Lua 报错信息。
-- if errDump then
--     errDump.config(true, 600)
-- end

-- 启动一个循环定时器，每隔 3 秒钟打印一次 Lua 堆内存和系统内存占用。
-- 调试内存泄漏时非常有用；量产时可注释掉以减少日志输出。
-- rtos.meminfo()          返回 Lua 堆内存使用情况
-- rtos.meminfo("sys")     返回系统内存（RAM）使用情况
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)

-- ==================== 模块加载（require） ====================
-- 重要：require 的加载顺序非常关键！
--   1. ws2812_config 必须最先 require，因为它定义了全局表 WS2812_CFG（硬件引脚、
--      矩阵尺寸、亮度、速度、坐标映射、颜色工具函数等），后续所有效果模块都要直接
--      读取 WS2812_CFG，如果顺序反了会报 "attempt to index global 'WS2812_CFG' (a nil value)"。
--   2. 效果任务模块之间是并列关系，只 require 一个（其余保持注释），不要同时启用多个
--      循环渲染任务，否则它们会同时写灯带造成画面错乱。

-- 加载 WS2812 公共配置（硬件参数、坐标映射、颜色工具，所有效果模块都依赖它）
require "ws2812_config"

-- 加载 色块覆盖 / LED 灯珠检测模块（默认 DETECT_LOOP=true，无限循环检测）
-- 效果：全屏依次点亮 红/绿/蓝/白/黑 五色，用于肉眼检查是否有死灯、偏色、虚焊。
require "ws2812_blocks_task"

-- 加载 彩虹渐变效果模块
-- 效果：整屏按色相环做彩虹流动，颜色随时间平滑过渡。
-- require "ws2812_rainbow_task"

-- 加载 蛇形扫描效果模块
-- 效果：单颗/一排灯珠按蛇形路径（S 形）在 22×22 矩阵上扫描移动。
-- require "ws2812_snake_task"

-- 加载 星点闪烁效果模块
-- 效果：随机位置的灯珠像星星一样随机亮起、淡出，形成星空效果。
-- require "ws2812_sparkle_task"

-- 加载 矩形收缩效果模块（DETECT_LOOP=false 时可接力循环）
-- 效果：矩形边框从外向内一圈圈收缩，再从内向外展开，类似雷达扫描。
-- require "ws2812_rect_task"

-- 加载 滚动文字效果模块（"欢迎使用LuatOS"，依赖 ws2812_fonts）
-- 效果：点阵字体从右向左滚动显示"欢迎使用LuatOS"，字模由 ws2812_fonts.lua 提供。
-- require "ws2812_scroll_task"

-- ==================== 串口命令接口 ====================
-- 功能说明：
--   通过 USB 虚拟串口（UART_ID=1，即模组的 USB 口，插电脑后枚举出的 COM 口）
--   接收文本命令，运行时动态调整亮度和动画速度，无需重新烧录脚本。
-- 通信参数：波特率 115200，8N1；命令以回车（\r）或换行（\n）结尾。
-- 支持命令：
--   b=NNN   设置亮度 0~255（0 最暗/熄灭，255 最亮，耗电也最大）
--   s=NNN   设置帧间隔 ms（越小越快，范围 20~2000）
--   b?      查询当前亮度
--   s?      查询当前帧间隔
-- 串口工具示例：Luatools 调试口、sscom、MobaXterm 等，记得勾选"发送新行"。

-- UART_ID = 1：在 Air 系列模组上，UART1 默认映射为 USB 虚拟串口，
-- 插 USB 后电脑会枚举出一个 COM 口，直接发命令即可，不需要额外接 USB-TTL。
local UART_ID = 1

-- rx_buf：接收累积缓冲区（字符串）。
-- 原因：串口数据是流式到达的，一条 "b=128\r\n" 可能被底层拆成多次 recv 回调
--       （比如先收到 "b=1"，再收到 "28\r"，再收到 "\n"），不能假设一次回调就是一条完整命令。
-- 做法：每次收到数据就拼到 rx_buf 末尾，再用 string.find 查找换行符，切出完整的一行，
--       剩余未换行的残片继续留在 rx_buf 里等下一次拼接。
local rx_buf = ""

-- clamp：数值范围保护函数，把输入值钳制在 [lo, hi] 闭区间内。
-- 参数：
--   v  - 待处理的值（可能是字符串，因为 string.match 抠出来的是字符串）
--   lo - 允许的最小值
--   hi - 允许的最大值
-- 返回：落区间内的整数
-- 作用：防止用户发送非法值（例如 b=999 或 b=-50）导致亮度异常、溢出或时序错乱。
--       tonumber 失败时用 lo 作为默认值；math.floor 保证是整数。
local function clamp(v, lo, hi)
    v = math.floor(tonumber(v) or lo)
    if v < lo then v = lo elseif v > hi then v = hi end
    return v
end

-- cmd_queue：命令队列（FIFO）。
-- 为什么要用队列 + 独立 task 处理：
--   uart.on 的 "recv" 回调运行在中断/事件上下文中，里面绝对不能做耗时操作
--   （比如 sys.wait、大量 log、写 WS2812 灯带），否则会阻塞串口接收，造成丢字节。
--   正确做法：回调里只做"读字节 + 拼包 + 切行"，把切好的完整命令塞进 cmd_queue，
--   然后立刻返回；由下面这个独立协程 task 每 20ms 轮询队列，取出命令慢慢处理
--   （修改 WS2812_CFG、打印日志都在这里做，互不影响）。
local cmd_queue = {}
sys.taskInit(function()
    while true do
        if #cmd_queue > 0 then
            -- table.remove(t, 1)：取出数组第一个元素（队首），其余元素前移，实现 FIFO
            local line = table.remove(cmd_queue, 1)
            if line == "b?" then
                -- 查询当前亮度
                log.info("cmd", "brightness =", WS2812_CFG.brightness)
            elseif line == "s?" then
                -- 查询当前帧间隔
                log.info("cmd", "speed_ms =", WS2812_CFG.speed_ms)
            else
                -- 匹配 b=数字 或 s=数字 形式的赋值命令
                -- 模式串 "^([bs])=(%-?%d+)$" 解释：
                --   ^      锚定行首
                --   ([bs]) 捕获组1：匹配单个字符 b 或 s，作为 key
                --   =      字面量等号
                --   (%-?%d+) 捕获组2：
                --          %-  是 Lua 模式中转义后的减号 "-"（Lua 里 "-" 是特殊修饰符，必须用 %- 转义）
                --          ?   表示负号可有可无（支持非负整数，也支持负数）
                --          %d+ 匹配一到多个数字 0-9
                --   $      锚定行尾，确保整行就是一个完整的 k=v，没有多余字符
                local k, v = string.match(line, "^([bs])=(%-?%d+)$")
                if k == "b" then
                    -- 设置亮度，范围 0~255（8 位 PWM 占空比）
                    WS2812_CFG.brightness = clamp(v, 0, 255)
                    log.info("cmd", "brightness =", WS2812_CFG.brightness)
                elseif k == "s" then
                    -- 设置帧间隔，范围 20~2000ms（20ms≈50fps，2000ms=2fps 很慢）
                    WS2812_CFG.speed_ms = clamp(v, 20, 2000)
                    log.info("cmd", "speed_ms =", WS2812_CFG.speed_ms)
                else
                    -- 既不是 b?/s?，也不符合 b=数字/s=数字，提示用法
                    log.info("cmd", "unknown:", line, "(use b=NNN s=NNN b? s?)")
                end
            end
        end
        -- 每 20ms 轮询一次队列，既保证响应及时，又让出 CPU 给其他 task
        sys.wait(20)
    end
end)

-- 用 if uart then 包裹的原因：
--   做防御性判断。某些精简固件（例如只带最小内核、不带 uart 模块的固件）中
--   全局变量 uart 可能为 nil，直接调用 uart.setup 会抛 attempt to call nil value。
--   有了这个判断，即使固件没启用 uart，脚本也不会崩溃，只会打印一条警告日志，
--   灯光效果仍可正常运行。
if uart then
    -- 配置串口：UART_ID、波特率 115200；其余参数 8N1 为 uart.setup 默认值
    uart.setup(UART_ID, 115200)
    -- 注册接收回调：每当串口收到 len 个字节就会被触发
    uart.on(UART_ID, "recv", function(id, len)
        -- 一次性把内核缓冲区里的 len 字节全部读出来
        local data = uart.read(id, len)
        if not data then return end
        -- 追加到累积缓冲区
        rx_buf = rx_buf .. data
        -- 循环切分：只要缓冲区里还能找到换行符，就切出一行
        while true do
            -- 模式 "[\r\n]+" 匹配一个或多个连续的 \r 或 \n，
            -- 这样可以同时兼容三种换行风格：
            --   \n      （Linux/Mac）
            --   \r      （旧 Mac）
            --   \r\n    （Windows/串口工具默认）
            -- 连续多个换行（例如 \r\n\r\n）会被整体识别为一个分隔符，切出空行，
            -- 后面的 line ~= "" 判断会把空行丢弃。
            local s, e = string.find(rx_buf, "[\r\n]+")
            if not s then break end       -- 没找到换行，说明是半包，留到下次再切
            local line = string.sub(rx_buf, 1, s - 1)   -- 换行符之前的内容 = 一条命令
            rx_buf = string.sub(rx_buf, e + 1)          -- 剩余未处理的部分
            if line ~= "" then
                -- 入队，交给上面的独立 task 处理，避免在 recv 回调里做耗时操作
                cmd_queue[#cmd_queue + 1] = line
            end
        end
    end)
    log.info("main", "串口命令已就绪 (115200): b=NNN s=NNN b? s?")
else
    log.warn("main", "固件未启用 uart，无法使用串口命令")
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
-- sys.run() 是 LuatOS 脚本的调度主循环入口：
--   它启动 sys 库的事件循环，驱动所有 sys.taskInit 注册的协程、所有 sys.timer 定时器，
--   并负责分发串口、网络、GPIO 等各种回调事件。
-- 注意：sys.run() 在正常运行时永远不会返回，因此它后面写的任何语句都不会被执行到。
--       不要在它后面添加任何代码/变量/打印！！！
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
