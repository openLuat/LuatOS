--[[
@module  board
@summary Air8380 硬件定义（唯一与硬件相关的配置文件）
@version 1.0
@date    2026.10.20

依据：Air8380_V0_20260914.pdf（V1.0，5 页原理图）
  P1 Air8000W 模组引脚
  P3 外供 3.3V LDO(U230 JW7809) / FLASH LDO(U200) / 外挂 FLASH(U231 GD5F1GM7UEYIGR)
  P4 以太网 RJ45 + CH390H(U400) + CH390H LDO(U401)

整份出厂固件里只有本文件写引脚，拿到新版原理图只改这里。
]]

local B = {}

B.model = "Air8380"
B.mcu = "Air8000W"

-- ===================== 电源使能（低电平关闭，高电平打开） =====================
-- 三路 JW7809 LDO，全部由模组 GPIO 控制，先上电再初始化 SPI 设备
B.ldo = {
    -- P3 U230：外供 3.3V（引到邮票孔，给客户外设供电）
    ext = { pin = 20, on_level = 1 },
    -- P3 U200：外挂 SPI Flash 供电
    flash = { pin = 2, on_level = 1 },
    -- P4 U401：CH390H 供电
    eth = { pin = 1, on_level = 1 },
    -- 使能后等待电源稳定的时间（ms）
    settle_ms = 50,
}

-- ===================== SPI1 总线 =====================
-- P1：SPI1_CLK=GPIO15，SPI1_MISO=GPIO14，SPI1_MOSI=GPIO13
-- 网口与 Flash 共用 SPI1，各自独立片选
B.spi = {
    id = 1,
    clk = 15,
    miso = 14,
    mosi = 13,
    -- CH390H 走 SPI1 全双工 26MHz；SPI NAND 只能半双工 2MHz，各自在 deviceSetup 里指定
    speed = 26000000,
}

-- ===================== 以太网（CH390H） =====================
-- P4：U400 CH390H，SPI1_CS = GPIO12，INT = ETH_INT(WAKEUP0)，25MHz 晶体
-- RJ45 的 LINK/ACT 灯由 CH390 的 LED1/LED2 经 470R 直接驱动，软件不参与
B.eth = {
    enabled = true,
    cs = 12,
    spi_speed = 26000000,
    irq = 17,                    -- P4 CH390H INT → GPIO17（与产测代码一致），中断模式收包
    -- P4 网口 LDO 使能见 B.ldo.eth
}

-- ===================== 板载 SPI Flash =====================
-- P3：U231 GD5F1GM7UEYIGR，SPI NAND，1Gbit(128MB)，CS = GPIO16
-- 与 CH390H 共用 SPI1；上电顺序必须先开 B.ldo.flash
B.flash = {
    enabled = true,
    cs = 16,
    spi_speed = 2000000,         -- SPI NAND 只能半双工，2MHz（产测实测值）
    -- 实板 JEDEC 实测 EF AE21 → W25N01KVZEIR（Winbond 1Gbit SPI NAND）
    -- 原理图标的是 GD5F1GM7UEYIGR，与实板不一致，此处以实测为准
    chip = "W25N01KVZEIR",
    mount = "/little_flash",
    -- 首次挂载失败时是否格式化（产线首板可用 true；已出货设备建议 false 防误擦）
    format_if_fail = true,
}

-- ===================== WiFi / BLE =====================
-- Air8000W 内置 WiFi/BLE 协处理器，固件由合宙提供（需 >= V20），不可二次开发
B.wifi = { enabled = true }
B.ble = { enabled = false }      -- 首版不开，预留

return B
