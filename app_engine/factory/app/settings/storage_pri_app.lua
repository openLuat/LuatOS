--[[
@module  storage_pri_app
@summary 外部存储初始化（SD卡 / NOR Flash / NAND Flash 挂载，PC 模拟）
@version 1.0
@date    2026.05.15
]]

local model = rtos.bsp()

if model == "PC" then
    -- PC: 创建全部挂载点目录模拟存储
    exapp.init("custom", { storage_type = "sd_tf" })
    exapp.init("custom", { storage_type = "little_flash" })
    exapp.init("custom", { storage_type = "nand_flash" })
elseif model and model:find("Air8000") then
    -- Air8000 核心板: SPI1 CS=GPIO12, 20MHz
    -- exapp.init("custom", { storage_type = "sd_tf",        spi_id = 1, pin_cs = 12, speed = 20000000 })
    -- exapp.init("custom", { storage_type = "little_flash",  spi_id = 1, pin_cs = 12, speed = 20000000 })
    -- exapp.init("custom", { storage_type = "nand_flash",    spi_id = 1, pin_cs = 12, speed = 20000000 })
elseif model and (model:find("Air1601") or model:find("Air1602")) then
    -- Engine_Air1602_5inch_720x1280_003_V000
    -- gpio.setup(50, 1)
    -- gpio.set(50, 1)
    -- exapp.init("custom", { storage_type = "nand_flash", spi_id = 2, pin_cs = 4, speed = 20000000 })
else
    -- 自定义型号
    -- exapp.init("custom", { storage_type = "sd_tf", spi_id = 1, pin_cs = 12, speed = 20000000 })
end
