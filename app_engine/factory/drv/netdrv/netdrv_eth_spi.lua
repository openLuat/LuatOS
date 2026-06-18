--[[
@module  netdrv_eth_spi
@summary SPI 以太网（CH390H）驱动模块，由 project_config 驱动参数
@version 2.0
@date    2026.06.09
@author  江访
@usage
通过 SPI 外挂 CH390H 芯片的以太网卡驱动，从 project_config 读取参数。
require 即自动运行，内部按 features.ethernet 自检。

配置示例（evb_8101_10i_v0.lua）：
  features = { ethernet = true, ... }
  ethernet = {
      spi_id = 0,          -- SPI 接口 ID
      pin_cs  = 34,        -- 片选 CS 引脚 GPIO
      pin_pwr = 53,        -- [可选] 供电使能 GPIO（如已在 power_on 处理则省略）
  }

本模块不订阅 IP_READY/IP_LOSE 事件，统一由 net_init 模块处理。

require 规范：
  - 在 app_main.lua 中直接 require "netdrv_eth_spi"
  - 不要加路径，不要加文件名后缀
]]
local exnetif = require "exnetif"

-- ==================== 自检：features.ethernet 是否开启 ====================
local config = _G.project_config or {}
if not config.features or not config.features.ethernet then
    return
end

-- ==================== 从 config 读取参数 ====================
local eth_cfg = config.ethernet
if not eth_cfg then
    log.warn("netdrv_eth_spi", "features.ethernet=true 但未配置 ethernet 参数段，跳过")
    return
end

local spi_id = eth_cfg.spi_id
local pin_cs = eth_cfg.pin_cs
local pin_irq = eth_cfg.pin_irq
local pin_pwr = eth_cfg.pin_pwr

if spi_id == nil or pin_cs == nil then
    log.error("netdrv_eth_spi", "配置不完整，缺少 spi_id 或 pin_cs")
    return
end

log.info("netdrv_eth_spi", "初始化: spi=", spi_id, "cs=", pin_cs, "irq=", pin_irq or "-", "pwr=", pin_pwr or "-")

-- ==================== 以太网初始化 ====================
-- SPI 总线可能与其他外设共用，CS 引脚已由 power_on 初始化为高电平
-- pin_pwr 可选：如果供电已在 power_on 处理则不传，避免重复 gpio.setup
-- pin_irq 可选：传 interrupt 引脚可降低功耗（中断模式），不传则轮询模式
sys.taskInit(function()
    local eth_opts = {spi = spi_id, cs = pin_cs}
    if pin_irq then
        eth_opts.irq = pin_irq
    end
    local eth_param = {
        tp = netdrv.CH390,
        opts = eth_opts,
    }
    if pin_pwr then
        eth_param.pwrpin = pin_pwr
    end

    exnetif.set_priority_order({
        { ETHERNET = eth_param },
    })
end)
