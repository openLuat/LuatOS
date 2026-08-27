--[[
@module  epd_drv
@summary epd墨水屏显示驱动模块，基于epd核心库
@version 1.0
@date    2026.08.19
@author  江访
@usage
本模块为epd墨水屏显示驱动功能模块，主要功能包括：
1、使用epd库custom模式初始化微雪2.13寸墨水屏(2.13inch e-Paper V4，122x250)；
2、配置SPI通信参数和设备对象；
3、将屏幕旋转为横屏(250x122)使用；
4、初始化hzfont矢量字体，供各页面绘制中英文字符；

本文件无对外接口,require "epd_drv"即可加载运行
]]

--[[
初始化epd显示驱动；

@api epd_drv.init()
@summary 配置并初始化微雪2.13寸墨水屏
@return boolean 初始化成功返回true，失败返回false

@usage
-- 初始化epd显示
local result = epd_drv.init()
if result then
    log.info("epd初始化成功")
else
    log.error("epd初始化失败")
end
]]

-- 屏幕画布尺寸（旋转后横屏）
local SCREEN_W = 250
local SCREEN_H = 122

-- 全局变量：panel 面板对象（各页面复用）
-- 全局变量：spi_epd SPI设备对象（不加local，供模块复用）
panel = nil

local function epd_drv_init()
    -- 初始化hzfont内置矢量字体库（V2050 14号固件内置ttf）
    -- 供各页面用panel:drawHzfont()绘制中英文字符
    if hzfont then
        local hz_ok = hzfont.init()
        if hz_ok then
            log.info("epd_drv", "hzfont init ok")
        else
            log.warn("epd_drv", "hzfont init failed")
        end
    else
        log.warn("epd_drv", "hzfont not compiled")
    end

    -- 按接线引脚正确配置GPIO号（Air780EHM 使用 SPI0）
    local spi_id = 0
    local pin_cs   = 8    -- 片选引脚
    local pin_dc   = 10   -- 数据/命令引脚
    local pin_rst  = 1    -- 复位引脚
    local pin_busy = 2    -- 忙检测引脚

    -- 注意:epd.open()之前需要先初始化spi，使用spi对象方式初始化
    spi_epd = spi.deviceSetup(spi_id, pin_cs, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 0)
    if spi_epd == nil then
        log.error("epd_drv", "spi.deviceSetup failed")
        return false
    end

    -- 使用epd库custom模式配置微雪2.13寸e-Paper V4（122x250）
    -- 时序对照官方EPD_2in13_V4.c：无外部LUT，波形由内置温度传感器自动生成
    local p, err = epd.open("custom", {
        port = "device",
        pin_dc = pin_dc,
        pin_rst = pin_rst,
        pin_busy = pin_busy,
        width = 122,
        height = 250,
        busy_level = 0,
        busy_timeout = 30000,
        -- 初始化序列：对应官方EPD_2in13_V4_Init()
        -- Reset：HIGH 20ms → LOW 2ms → HIGH 20ms
        init = {
            {reset = {high = 20, low = 2, high2 = 20}},
            {busy = 0},
            {cmd = 0x12},                          -- SWRESET
            {busy = 0},
            {cmd = 0x01, data = {0xF9, 0x00, 0x00}},  -- Driver output control
            {cmd = 0x11, data = {0x03}},              -- data entry mode
            {cmd = 0x44, data = {0x00, 0x0F}},        -- Set RAM X
            {cmd = 0x45, data = {0x00, 0x00, 0xF9, 0x00}},  -- Set RAM Y
            {cmd = 0x4E, data = {0x00}},              -- Set RAM X counter
            {cmd = 0x4F, data = {0x00, 0x00}},        -- Set RAM Y counter
            {cmd = 0x3C, data = {0x05}},              -- BorderWavefrom
            {cmd = 0x21, data = {0x00, 0x80}},        -- Display update control
            {cmd = 0x18, data = {0x80}},              -- Read built-in temperature sensor
            {busy = 0},
        },
        -- 刷新序列：full全刷 / partial局部刷
        refresh = {
            full = {
                {cmd = 0x44, data = {0x00, 0x0F}},
                {cmd = 0x45, data = {0x00, 0x00, 0xF9, 0x00}},
                {cmd = 0x4E, data = {0x00}},
                {cmd = 0x4F, data = {0x00, 0x00}},
                {write_ram = 0x24},
                {write_ram2 = 0x26},
                {cmd = 0x22, data = {0xF7}},
                {cmd = 0x20},
                {busy = 0},
            },
            partial = {
                {reset = {high = 0, low = 1, high2 = 20}},
                {cmd = 0x3C, data = {0x80}},
                {cmd = 0x01, data = {0xF9, 0x00, 0x00}},
                {cmd = 0x11, data = {0x03}},
                {cmd = 0x44, data = {0x00, 0x0F}},
                {cmd = 0x45, data = {0x00, 0x00, 0xF9, 0x00}},
                {cmd = 0x4E, data = {0x00}},
                {cmd = 0x4F, data = {0x00, 0x00}},
                {write_ram = 0x24},
                {cmd = 0x22, data = {0xFF}},
                {cmd = 0x20},
                {busy = 0},
            },
        },
        -- 休眠序列：深度睡眠
        sleep = {
            deep = {
                {cmd = 0x10, data = {0x01}},
                {delay = 100},
            },
        },
    }, spi_epd)
    if not p then
        log.error("epd_drv", "epd.open failed", err)
        return false
    end
    panel = p

    -- 初始化屏幕
    if not panel:init() then
        log.error("epd_drv", "panel:init failed")
        return false
    end

    -- 旋转90度，将122x250竖屏变为250x122横屏使用
    panel:setRotation(90)

    log.info("epd_drv", "epd init ok, size", SCREEN_W, SCREEN_H)
    return true
end

epd_drv_init()
