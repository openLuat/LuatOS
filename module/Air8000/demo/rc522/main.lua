-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "RC522"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)
sys = require("sys")
local rc522 = require "rc522"

local SPI_ID = 1
local CS_PIN = 12
local RST_PIN = 21

-- SPI初始化配置
sys.taskInit(function()
    -- 配置SPI总线
    -- spi_rc522 = spi.setup(
    --     SPI_ID,--spi_id
    --     nil,
    --     0,--CPHA
    --     0,--CPOL
    --     8,--数据宽度
    --     10000000--,10MHz频率
    --     -- spi.MSB,--高低位顺序    可选，默认高位在前
    --     -- spi.master,--主模式     可选，默认主
    --     -- spi.full--全双工       可选，默认全双工
    -- )
    spi_rc522 = spi.setup(SPI_ID, nil, 0, 0, 8, 10 * 1000 * 1000)

    -- RC522模块初始化
    if rc522.init(SPI_ID, CS_PIN, RST_PIN) then
        log.info("RC522", "初始化成功")
    else
        log.error("RC522", "初始化失败，请检查接线")
        return
    end

    -- 主循环读取卡片
    while true do
        -- 检测卡片并获取UID
        local status, array_id = rc522.request(rc522.reqall)
        log.info("rc522.request:", status, array_id)
        if status then
            local success, uid = rc522.anticoll(array_id)
            log.info("rc522.anticoll:", success, uid:toHex())
        end
        sys.wait(500) -- 降低轮询频率
    end
end)

sys.run()
