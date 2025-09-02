-- ==========================
-- SD卡初始化模块
-- ==========================

local ETH3V3_EN =140--以太网供电
local SPI_TF_CS = 20--SD卡片选
local SPI_ETH_CS = 12--以太网片选

-- 注：开发板上TF和以太网是同一个SPI，使用TF时必须要将以太网拉高
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

    -- 列出SD卡根目录下的文件和文件夹，最多列出50个（系统限制），从第0个开始
    local ret, data = io.lsdir("/sd/", 50, 0)

    log.info("SDCARD", "SD卡初始化完成")
end

-- 启动SD卡配置任务
sys.taskInit(sdcard_init)

return {
    sdcard_init = sdcard_init,
    SPI_TF_CS = SPI_TF_CS
}
