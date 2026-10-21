--[[
@module  board_init
@summary Air8301 出厂固件板级初始化模块
@version 1.0
@date    2026.09.22
@author  江访
@usage
本模块处理 Air8301 上电时序 + 板级初始化（require 即执行，含 sys.wait 放协程）：

1. 上电时序：引脚复用 + 各外设供电使能
2. DO (继电器) 初始状态为关闭
3. 蜂鸣器由 buzzer_drv 统一管理 (PWM2/PIN98, 0% 占空比静音待命，本模块不再直接操作 PWM)
4. 状态灯初始化 (GPIO21=4G_STATUS, GPIO141=WIFI_STATUS)
5. 恢复出厂设置：订阅 FACTORY_RESET_REQUEST（来源：系统信息页按钮 / reload_app 长按5秒）
   清空用户配置后回写 test_done，重启仍进业务模式（不会掉进产测模式）

注意：
- RS485 RE/DE 由 uart.setup 内置 RS485 模式控制（comm_core.lua / rtu_slave_manage.lua），
  本模块不操作 GPIO2/153
- DI 中断注册在 di_app.lua，本模块不再设置 DI 引脚
- RELOAD/WAKEUP2 按键由 reload_app.lua 独占（发布 KEY_EVENT + 长按5秒 FACTORY_RESET_REQUEST），
  本模块不再注册该引脚，避免中断重复注册覆盖
- 以太网1/2 CH390H 初始化由 network_app.lua 的 exnetif 统一管理
]]

-- ==================== 0. 依赖模块 ====================
-- 蜂鸣器 PWM 驱动：PWM2/PIN98 唯一占用者，require 即完成引脚复用并配置为 0% 占空比静音待命
local buzzer_drv = require "buzzer_drv"

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

    -- 蜂鸣器：由 buzzer_drv 统一管理（require 时已配置为 0% 占空比静音待命）
    -- 此前 board_init 与 buzzer_app 各自 pwm.setup/close 抢占 PWM2 且频率不一致，本次已收敛到驱动层

    -- 状态灯默认熄灭（GPIO21=4G_STATUS, GPIO141=WIFI_STATUS）
    gpio.setup(21, 0)
    gpio.set(21, 0)
    gpio.setup(141, 0)
    gpio.set(141, 0)

    log.info("board_init", "===== Air8301 板级初始化完成 =====")
end

sys.taskInit(board_init_task)

-- ==================== 2. 蜂鸣器提示音 ====================
-- 提示音统一走 buzzer_drv（PWM2/PIN98 唯一占用者），本模块不再直接调用 pwm 接口
-- 原 beep()/beep_stop_cb() 已删除，等价能力为 buzzer_drv.beep_bg(ms)

-- ==================== 3. 恢复出厂设置 ====================

-- 恢复出厂后重启设备回调
local function reboot_cb()
    log.warn("board_init", "重启设备...")
    rtos.reboot()
end

--[[
恢复出厂设置（删除 fskv 中所有用户配置 + 5秒后重启）

注意：test_done 是「产测完成标记」，main.lua 开机按它分流（true=业务模式，nil=产测模式），
      不属于用户配置。若被 fskv.clear 一并清掉，业务模式长按 RELOAD 恢复出厂后重启会掉进产测模式，
      故此处先备份 test_done，清空后回写。

@local
@function reset_factory
]]
local function reset_factory()
    log.warn("board_init", "执行恢复出厂设置...")

    -- 备份产测完成标记（用户配置之外的状态，恢复出厂不得清除）
    local test_done = fskv.get("test_done")

    -- 删除所有 fskv 用户配置
    pcall(fskv.clear)

    -- 回写产测完成标记，确保重启后仍进入业务（出厂）模式
    if test_done then
        fskv.set("test_done", test_done)
        log.info("board_init", "保留产测完成标记 test_done，重启后仍进入业务模式")
    end

    log.warn("board_init", "用户配置已清空（保留 test_done），5 秒后重启...")

    -- 蜂鸣器长鸣 1 秒提示（本函数为订阅回调，非协程上下文，用非阻塞接口定时关断）
    buzzer_drv.beep_bg(1000)

    -- 5 秒后重启
    sys.timerStart(reboot_cb, 5000)
end

-- 恢复出厂设置请求（来源：系统信息页按钮 / reload_app 长按5秒）
sys.subscribe("FACTORY_RESET_REQUEST", reset_factory)
