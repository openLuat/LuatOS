--[[
@module  spi_sdcard_init
@summary spi_sdcard_init 功能模块
@version 1.0
@date    2025.09.02
@author  拓毅恒
@usage
用法实例：
- 在main.lua中添加：require "spi_sdcard_init"
- 系统会自动启动SD卡初始化任务
- 初始化完成后，可以通过文件系统API访问SD卡文件

注意事项：
- 使用时请确保正确连接SD卡硬件
- SD卡需为FAT32格式
- 开发板上TF和以太网是同一个SPI，使用TF时必须要将以太网拉高

本文件没有对外接口，直接在 main.lua 中 require "spi_sdcard_init" 即可加载运行。
]]

local ETH3V3_EN =140--以太网供电
local SPI_TF_CS = 20--SD卡片选
local SPI_ETH_CS = 12--以太网片选

-- 注：开发板上TF和以太网是同一个SPI，使用Air8000开发板时必须要将以太网拉高
-- 如果使用其他硬件，需要根据硬件原理图来决定是否需要此操作
-- 配置以太网供电引脚，设置为输出模式，并启用上拉电阻
gpio.setup(ETH3V3_EN, 1,gpio.PULLUP)
-- 配置以太网片选引脚，设置为输出模式，并启用上拉电阻
gpio.setup(SPI_ETH_CS, 1,gpio.PULLUP)

-- SD卡初始化函数
function sdcard_init()
    log.info("SDCARD", "开始初始化SD卡")

    -- 配置SPI，设置SPI1，波特率为400000，用于SD卡初始化
    local result = spi.setup(1, nil, 0, 0, 8, 400 * 1000)
    -- 记录SD卡初始化时SPI打开的结果
    log.info("sdcard_init", "open spi", result)

    -- 配置SD卡片选引脚，设置为输出模式，并启用上拉电阻
    gpio.setup(SPI_TF_CS, 1, gpio.PULLUP)

    -- 挂载SD卡到文件系统，指定挂载点为"/sd"
    local mount_result = fatfs.mount(fatfs.SPI, "/sd", 1, SPI_TF_CS, 24 * 1000 * 1000)
    log.info("SDCARD", "挂载SD卡结果:", mount_result)

    -- 获取SD卡的可用空间信息
    local data, err = fatfs.getfree("/sd")
    -- 如果成功获取到可用空间信息
    if data then
        -- 记录SD卡的可用空间信息
        log.info("fatfs", "可用空间", json.encode(data))
    else
        -- 记录获取可用空间信息时的错误信息
        log.info("fatfs", "err", err)
    end

    log.info("SDCARD", "SD卡初始化完成")
end

-- 启动SD卡配置任务
sys.taskInit(sdcard_init)
