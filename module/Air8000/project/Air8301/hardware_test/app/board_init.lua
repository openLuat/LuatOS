--[[
@module  board_init
@summary Air8301 硬件测试板级初始化模块
@version 2.0
@date    2026.08.04
@author  江访
@usage
本模块处理 Air8301 上电时序 + 板级初始化（require 即执行，含 sys.wait 放协程）：

1. 上电时序：引脚复用 + 各外设供电使能
2. DO (继电器) 初始状态为关闭
3. 蜂鸣器初始化 (PWM2, 默认关闭)
4. 状态灯初始化 (GPIO21=4G_STATUS, GPIO141=WIFI_STATUS)
5. 恢复出厂设置：订阅 FACTORY_RESET_REQUEST（来源：系统信息页按钮 / reload_app 长按5秒）

注意：
- RS485 RE/DE 由 uart.setup 内置 RS485 模式控制（rs485_app.lua），本模块不操作 GPIO2/153
- DI 中断注册在 di_app.lua，本模块不再设置 DI 引脚
- RELOAD/WAKEUP2 按键由 reload_app.lua 独占（发布 KEY_EVENT + 长按5秒 FACTORY_RESET_REQUEST），
  本模块不再注册该引脚，避免中断重复注册覆盖
- 以太网1/2 CH390H 初始化由 network_app.lua 的 exnetif 统一管理
]]

-- ==================== 1. 上电时序 + 板级初始化任务 ====================

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

    -- RS485_1 供电 (485_3V3_UART1 = GPIO29)
    gpio.setup(29, 1)
    gpio.set(29, 1)

    -- RS232_1 供电 (232_3V3_UART2 = GPIO30)
    gpio.setup(30, 1)
    gpio.set(30, 1)

    -- GPIO31 (VPU_3.3V)，为上拉 RELOAD 和 DI1/DI2 提供电源
    gpio.setup(31, 1)
    gpio.set(31, 1)

    -- 以太网1 供电 (ETH_3.3V = GPIO32)
    gpio.setup(32, 1)
    gpio.set(32, 1)

    -- 以太网2 供电 (ETH_3.3V = GPIO33)
    gpio.setup(33, 1)
    gpio.set(33, 1)

    -- 等待wifi模块就绪
    sys.wait(200)

    -- Flash 供电使能 (FLASH_3V3 = GPIO140)
    gpio.setup(140, 1)
    gpio.set(140, 1)

    -- RS485_2 供电 (485_3V3_UART11 = GPIO147)
    gpio.setup(147, 1)
    gpio.set(147, 1)

    -- RS232_2 供电 (232_3V3_UART12 = GPIO146)
    -- 注意: GPIO146 开启后会上拉 RELOAD 和 GPIO16/GPIO17
    gpio.setup(146, 1)
    gpio.set(146, 1)

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

sys.taskInit(board_init_task)

-- ==================== 2. 蜂鸣器提示音 ====================

-- 蜂鸣器停止回调：关闭PWM通道
local function beep_stop_cb()
    pwm.close(2)
end

--[[
播放蜂鸣器提示音（短促滴一声）

@local
@function beep
@param duration_ms number 持续时间(ms)，默认100ms
]]
local function beep(duration_ms)
    duration_ms = duration_ms or 100
    pwm.setup(2, 2000, 50)  -- 2kHz, 50% 占空比
    pwm.start(2)
    sys.timerStart(beep_stop_cb, duration_ms)
end

-- ==================== 3. 恢复出厂设置 ====================

-- 恢复出厂后重启设备回调
local function reboot_cb()
    log.warn("board_init", "重启设备...")
    rtos.reboot()
end

--[[
恢复出厂设置（删除 fskv 中所有用户配置 + 5秒后重启）

@local
@function reset_factory
]]
local function reset_factory()
    log.warn("board_init", "执行恢复出厂设置...")

    -- 删除所有 fskv 用户配置
    pcall(fskv.clear)

    log.warn("board_init", "fskv 已清空，5 秒后重启...")

    -- 蜂鸣器长鸣提示
    beep(1000)

    -- 5 秒后重启
    sys.timerStart(reboot_cb, 5000)
end

-- 恢复出厂设置请求（来源：系统信息页按钮 / reload_app 长按5秒）
sys.subscribe("FACTORY_RESET_REQUEST", reset_factory)
