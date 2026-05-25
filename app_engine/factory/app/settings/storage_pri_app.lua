--[[
@module  storage_pri_app
@summary 外部存储初始化（SD卡 / NAND Flash / little_flash，PC 模拟）
@version 2.0
@date    2026.05.22
@author  江访
@usage
读取 project_config.features + storage 配置，按需初始化外部存储。
]]
local cfg = _G.project_config or {}
local fe = cfg.features or {}
local st = cfg.storage or {}

-- PC 模拟器：创建全部挂载点
if _G.is_pc then
    exapp.init("custom", { storage_type = "sd_tf" })
    exapp.init("custom", { storage_type = "little_flash" })
    exapp.init("custom", { storage_type = "nand_flash" })
    return
end

-- NAND Flash 初始化
if fe.nand_flash and st.nand_flash then
    local nf = st.nand_flash
    if nf.pin_pwr then
        gpio.setup(nf.pin_pwr, 1)
        gpio.set(nf.pin_pwr, 1)
    end
    exapp.init("custom", {
        storage_type = "nand_flash",
        spi_id = nf.spi_id,
        pin_cs = nf.pin_cs,
        speed = nf.speed or 20000000,
    })
    log.info("storage_pri", "NAND Flash 初始化完成 spi=" .. nf.spi_id .. " cs=" .. nf.pin_cs)
end

-- SD/TF 卡初始化
if fe.sd_card and st.sd_card then
    local sd = st.sd_card
    exapp.init("custom", {
        storage_type = "sd_tf",
        spi_id = sd.spi_id,
        pin_cs = sd.pin_cs,
        speed = sd.speed or 20000000,
    })
    log.info("storage_pri", "SD/TF 卡初始化完成 spi=" .. sd.spi_id .. " cs=" .. sd.pin_cs)
end
