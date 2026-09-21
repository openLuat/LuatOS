--[[
@module  board_init
@summary Air8301 板级初始化模块（智控电场发生器通讯控制板）
@version 1.0
@date    2026.09.18
@author  嵌入式软件设计开发代理
@usage
本模块处理 Air8301 上电时序 + 板级初始化（require 即执行，含 sys.wait 放协程）：
1. 上电时序：引脚复用 + 各外设供电使能
2. DO (继电器) 初始状态为关闭（安全默认态）
3. 蜂鸣器初始化 (PWM2, 默认关闭)
4. 状态灯初始化 (GPIO21=4G_STATUS, GPIO141=WIFI_STATUS)

参考：module/Air8000/project/Air8301/hardware_test/app/board_init.lua
说明：本工程仅使用 LCD + 4G/WiFi + UART1，其余外设供电保持与硬件测试固件一致的使能时序。
      恢复出厂 / RELOAD 按键相关逻辑本工程未使用，故不移植。
]]

--[[
板级初始化协程（require 后自动启动）：
按硬件要求依次执行引脚复用、各外设供电上电、DO/蜂鸣器/状态灯默认态设置。
含 sys.wait(200) 等待 WiFi 模组就绪，故必须放在协程中执行。

@local
@function board_init_task
]]
local function board_init_task()
    log.info("board_init", "===== Air8301 上电时序开始 =====")

    -- 引脚复用
    pins.setup(98, "PWM2")
    pins.setup(41, "GPIO12")
    pins.setup(66, "GPIO5")
    pins.setup(67, "GPIO4")

    -- SPI1 总线 CS 脚全部拉高（空闲态）
    gpio.setup(12, 1, gpio.PULLUP) -- SPI1_CS0 = GPIO12 (以太网1)
    gpio.setup(5, 1, gpio.PULLUP)  -- SPI1_CS1 = GPIO5  (以太网2)
    gpio.setup(4, 1, gpio.PULLUP)  -- SPI1_CS2 = GPIO4  (外部Flash)

    -- LCD 供电使能 (LCD_EN = GPIO28)
    gpio.setup(28, 1)
    gpio.set(28, 1)

    -- RS485_1 供电 (485_3V3_UART1 = GPIO29)，UART1 用于与高压控制板通信
    gpio.setup(29, 1)
    gpio.set(29, 1)

    -- GPIO31 (VPU_3.3V)，为上拉 RELOAD 和 DI1/DI2 提供电源
    gpio.setup(31, 1)
    gpio.set(31, 1)

    -- 等待wifi模块就绪
    sys.wait(200)

    -- DI/DO 供电 (VDD_5V_DI_DO = GPIO152)
    gpio.setup(152, 1)
    gpio.set(152, 1)

    -- DO 继电器默认关闭（GPIO24/25 高电平导通）
    gpio.setup(24, 0)
    gpio.set(24, 0)
    gpio.setup(25, 0)
    gpio.set(25, 0)

    -- 蜂鸣器预置 0% 占空比，确保通电时不响（PWM2/PIN98）
    pwm.setup(2, 2000, 0)
    pwm.close(2)

    -- 状态灯默认熄灭（GPIO21=4G_STATUS, GPIO141=WIFI_STATUS）
    gpio.setup(21, 0)
    gpio.set(21, 0)
    gpio.setup(141, 0)
    gpio.set(141, 0)

    log.info("board_init", "===== Air8301 板级初始化完成 =====")
end

-- 启动板级初始化协程
sys.taskInit(board_init_task)
