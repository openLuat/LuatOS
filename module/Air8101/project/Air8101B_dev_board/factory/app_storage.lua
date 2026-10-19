--[[
@module  app_storage
@summary 用户模式外部存储：把可用的 TF 卡 / SPI NAND 挂到固定路径，供文件浏览、音频播放读取
@version 1.0
@date    2026.10.16
@usage
user_main 的 task 里调用（内部会 sys.wait，必须在 task 中）：
    require("app_storage").init()

挂载点约定（ui_file / ui_audio 按这些路径扫描）
    /sd        TF 卡（fatfs.mount(fatfs.SDIO, ...)）
    /nand      SPI NAND（little_flash，按需挂载：流程见 prod_nand.lua）
    /luadb     脚本区，随脚本烧入（只读，不在这里挂）

为什么需要这个模块
1. 产测的 SD_TEST# / NAND_TEST# 是"测完就卸"，用户模式没人挂载，
   于是文件浏览、音频列表里永远看不到卡里的东西（脚本区又放不下音乐）；
2. 音乐这类大文件就该放 TF 卡，别随脚本烧进 luadb —— 脚本区只有 512 KB。

注意
1. 挂载失败不是错误：没插卡 / VBAT_SD 拨码没打开 / 卡没格式化都会失败，
   界面照常工作，只是列表里看不到卡里的文件；
2. 只挂不卸：用户模式下界面随时可能读这两个存储，卸载没有意义。
]]

local M = {}

local mounted = {}

local function cfg_sd()
    return ((_G.project_config or {}).hw or {}).sd or {}
end

--- 挂载 TF 卡到 /sd；成功（或已挂载）返回 true
function M.mount_sd()
    if mounted["/sd"] then return true end

    local c = cfg_sd()
    if not c.en then
        log.warn("app_storage", "config 没有 sd.en，跳过 TF 卡挂载")
        return false
    end

    gpio.setup(c.en, 1)      -- SD_EN 供电
    sys.wait(50)

    local ok = fatfs.mount(fatfs.SDIO, "/sd", 24000)
    if not ok then
        sys.wait(100)        -- 首次挂载偶发失败，重试一次
        ok = fatfs.mount(fatfs.SDIO, "/sd", 24000)
    end

    if ok then
        mounted["/sd"] = true
        log.info("app_storage", "TF 卡已挂载到 /sd")
    else
        log.warn("app_storage", "TF 卡挂载失败（没插卡 / VBAT_SD 拨码 / 卡未格式化）")
    end
    return ok and true or false
end

--- 查询挂载状态（ui_audio / ui_file 判断要不要扫 /sd）
function M.is_mounted(path)
    return mounted[path] == true
end

--- 挂载所有可用存储：失败只告警，不阻塞启动
function M.init()
    M.mount_sd()
    -- SPI NAND（/nand）暂不在用户模式挂载：等确认真要用再照 prod_nand.lua 的流程加
    return M
end

return M
