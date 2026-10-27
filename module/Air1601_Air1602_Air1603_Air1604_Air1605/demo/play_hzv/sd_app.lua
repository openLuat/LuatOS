--[[
@module  sd_app
@summary TF 卡挂载应用功能模块（参数来自 hzv_hw，用于播放 /sd 下的大文件 HZV）
@version 1.0
@date    2026.10.26
@author  拓毅恒
@usage
本文件为 HZV 播放 demo 的 TF 卡挂载应用功能模块，核心业务逻辑为：
1、按 hzv_hw.get() 返回的板型参数，初始化 TF 卡所在 SPI 总线并拉高片选；
2、按板型决定是否先拉高 TF 卡供电使能脚（SD_EN），再调用 fatfs.mount 挂载到 /sd；
3、关闭自动格式化（auto_format=false），避免挂载异常时误格式化用户卡；
4、挂载成功后打印卡容量，为 hzv_player 提供 /sd 路径的读取能力；

对外接口：
1、sd_app.mount()：挂载 TF 卡，成功返回 true，失败返回 false
2、sd_app.unmount()：卸载 TF 卡并关闭 SPI，回收资源

注意：HZV 文件只有几百 KB 到几 MB，放 /luadb 也能播；
      视频更长时建议放 TF 卡顺序读取，播放更稳。
]]

-- 加载硬件环境配置模块，SPI 与 SD_EN 引脚全部从参数表读取
local hzv_hw = require "hzv_hw"

local M = {}

-- 挂载状态与总线信息，unmount 时使用
local mounted = false
local spi_id = nil

--[[
挂载 TF 卡；

@api sd_app.mount()
@summary 按板型参数初始化 SPI 并挂载 FAT 文件系统到 /sd
@return boolean 挂载成功返回 true，失败返回 false

@usage
if sd_app.mount() then
    log.info("main", "TF 卡已挂载，可以播放 /sd 下的 HZV")
end
]]
function M.mount()
    if mounted then
        return true
    end

    local cfg = hzv_hw.get()
    local sd_cfg = cfg.sd
    -- 部分板型出厂就没有 SD 卡座（如 Air8607A），参数表里 sd 为 nil
    if not sd_cfg then
        log.warn("sd_app", "当前板型没有配置 SD 卡，跳过挂载", cfg.name)
        return false
    end
    spi_id = sd_cfg.spi_id

    -- TF 卡供电使能脚先拉高（部分板型没有这个脚，pin_sd_en 为 nil）
    if sd_cfg.pin_sd_en then
        gpio.setup(sd_cfg.pin_sd_en, 1, gpio.PULLUP)
        log.info("sd_app", "TF 卡供电使能", "GPIO" .. sd_cfg.pin_sd_en)
    end

    -- SPI 先按 400kHz 低速初始化：不同品牌的卡用低速通信兼容性最好
    spi.setup(spi_id, nil, 0, 0, 8, 400000)
    -- 同一 SPI 总线上的从设备初始化前必须先拉高片选，防止互相干扰
    gpio.setup(sd_cfg.pin_cs, 1)

    -- 挂载文件系统：power_pin/power_on_delay 由驱动做一次完整断电-上电复位
    -- 最后一个参数 false 表示挂载失败不自动格式化，保护卡内已有数据
    local ok, err = fatfs.mount(fatfs.SPI, "/sd", spi_id, sd_cfg.pin_cs,
        sd_cfg.speed, sd_cfg.pin_sd_en, 10, false)
    if not ok then
        log.error("sd_app", "TF 卡挂载失败", err, "请检查卡是否插好、是否为 FAT32 格式")
        -- 挂载失败也要关掉 SPI，避免后续重复挂载时总线状态异常
        spi.close(spi_id)
        return false
    end

    mounted = true
    log.info("sd_app", "TF 卡挂载成功", "/sd")

    -- 打印可用空间，方便判断卡是否正常识别（如不需可注释掉）
    local free, free_err = fatfs.getfree("/sd")
    if free then
        log.info("sd_app", "TF 卡空间信息", json.encode(free))
    else
        log.warn("sd_app", "获取 TF 卡空间失败", free_err)
    end

    return true
end

--[[
卸载 TF 卡并关闭 SPI；

@api sd_app.unmount()
@summary 卸载 /sd 文件系统并关闭 SPI 总线，播放结束需要释放资源时调用
@return nil

@usage
sd_app.unmount()
]]
function M.unmount()
    if not mounted then
        return
    end

    if fatfs.unmount("/sd") then
        log.info("sd_app", "TF 卡卸载成功")
    else
        log.error("sd_app", "TF 卡卸载失败")
    end
    mounted = false

    if spi_id then
        spi.close(spi_id)
        log.info("sd_app", "SPI 总线已关闭", spi_id)
        spi_id = nil
    end
end

--[[
查询 TF 卡是否已挂载；

@api sd_app.is_mounted()
@summary 供业务模块判断 /sd 路径是否可读
@return boolean 已挂载返回 true
]]
function M.is_mounted()
    return mounted
end

return M
