--[[
@module  sd_app
@summary Air8607 TF 卡挂载应用功能模块（挂载 /sd 并列举卡上的 HZV 素材）
@version 1.0
@date    2026.10.30
@author  江访
@usage
本文件为 Air8607 播放 SD 卡 HZV 素材 demo 的 TF 卡应用功能模块，核心业务逻辑为：
1、拉高 SD_EN（GPIO74）给 TF 卡供电，SPI1 按 400kHz 低速初始化，片选 GPIO8 先拉高；
2、调用 fatfs.mount 挂载 FAT 文件系统到 /sd，挂载时钟 20MHz，挂载失败不自动格式化；
3、挂载成功后打印卡容量，卸载时关闭文件系统和 SPI 总线；
4、list_hzv 列举 /sd 根目录下的 *.hzv 素材，返回按文件名排序的列表。

本文件的对外接口有4个：
1、sd_app.mount：挂载 TF 卡到 /sd，成功返回 true，失败返回 false
2、sd_app.unmount：卸载 /sd 并关闭 SPI 总线
3、sd_app.is_mounted：查询 TF 卡是否已挂载
4、sd_app.list_hzv：返回 /sd 根目录下的 HZV 素材列表，每项为 {path=, name=, size=}
]]

local M = {}

-- Air8607 的 TF 卡接在 SPI1 上，SPI1_CS = GPIO8，SD_EN = GPIO74
local SD_SPI_ID  = 1
local SD_PIN_CS  = 8
local SD_PIN_EN  = 74

-- TF 卡 SPI 时钟，挂载成功后的通信速度
local SD_SPI_SPEED = 20 * 1000 * 1000

-- SPI 初始化时钟，低速对各品牌卡的兼容性最好
local SD_SPI_INIT_SPEED = 400 * 1000

-- TF 卡供电复位过程时间，单位 ms
local SD_POWER_DELAY = 10

-- 挂载点，也是素材路径前缀
local SD_MOUNT_POINT = "/sd"

-- 单次列举返回的最大条目数
local LIST_MAX = 100

-- HZV 素材扩展名
local HZV_SUFFIX = ".hzv"

-- 挂载状态，unmount 与 is_mounted 使用
local mounted = false

-- 挂载时使用的 SPI 总线号，unmount 时关闭
local used_spi_id = nil

--[[
挂载 TF 卡；

@api sd_app.mount()

@summary 初始化 SPI1 并把 TF 卡挂载到 /sd，重复调用直接返回 true

@return boolean 挂载成功返回 true，失败返回 false

@usage
if not sd_app.mount() then
    log.error("main", "TF 卡挂载失败")
end
]]
function M.mount()
    if mounted then
        return true
    end

    -- TF 卡供电使能脚拉高，卡进入可通信状态
    gpio.setup(SD_PIN_EN, 1, gpio.PULLUP)
    log.info("sd_app", "TF 卡供电使能", "GPIO" .. SD_PIN_EN)

    -- SPI 按低速初始化，片选由 fatfs 按 SD_PIN_CS 控制，这里先拉高避免干扰
    spi.setup(SD_SPI_ID, nil, 0, 0, 8, SD_SPI_INIT_SPEED)
    gpio.setup(SD_PIN_CS, 1)

    -- 最后一个参数 false 表示挂载失败不自动格式化，保护卡内已有数据
    local ok, err = fatfs.mount(fatfs.SPI, SD_MOUNT_POINT, SD_SPI_ID, SD_PIN_CS,
        SD_SPI_SPEED, SD_PIN_EN, SD_POWER_DELAY, false)
    if not ok then
        log.error("sd_app", "TF 卡挂载失败", err, "请检查卡是否插好、是否为 FAT32 格式")
        spi.close(SD_SPI_ID)
        return false
    end

    mounted = true
    used_spi_id = SD_SPI_ID
    log.info("sd_app", "TF 卡挂载成功", SD_MOUNT_POINT)

    local free, free_err = fatfs.getfree(SD_MOUNT_POINT)
    if free then
        log.info("sd_app", "TF 卡空间信息", json.encode(free))
    else
        log.warn("sd_app", "获取 TF 卡空间失败", free_err)
    end

    return true
end

--[[
卸载 TF 卡；

@api sd_app.unmount()

@summary 卸载 /sd 文件系统并关闭 SPI 总线，释放资源

@return nil

@usage
sd_app.unmount()
]]
function M.unmount()
    if not mounted then
        return
    end

    -- fatfs.unmount 成功返回 0，其他返回值是失败码
    if fatfs.unmount(SD_MOUNT_POINT) == 0 then
        log.info("sd_app", "TF 卡卸载成功")
    else
        log.error("sd_app", "TF 卡卸载失败")
    end
    mounted = false

    if used_spi_id then
        spi.close(used_spi_id)
        log.info("sd_app", "SPI 总线已关闭", used_spi_id)
        used_spi_id = nil
    end
end

--[[
查询 TF 卡是否已挂载；

@api sd_app.is_mounted()

@summary 供业务模块判断 /sd 路径是否可读

@return boolean 已挂载返回 true，否则返回 false

@usage
if sd_app.is_mounted() then
    log.info("main", "TF 卡可用")
end
]]
function M.is_mounted()
    return mounted
end

--[[
素材列表排序函数；

@summary 按文件名字典序升序排列，保证每次上电的播放顺序一致

@param table a 列表元素
@param table b 列表元素
@return boolean a 排在 b 前面返回 true
]]
local function sort_by_name(a, b)
    return a.name < b.name
end

--[[
列举目录下的 HZV 素材；

@summary 只取普通文件，扩展名不区分大小写，条目名统一取最后一段文件名

@param string dir 目录路径
@param table list 结果收集表，命中项会被追加进去
@return nil
]]
local function list_dir_hzv(dir, list)
    -- luadb 与 fatfs 的挂载前缀写法不同，两种写法都试一次
    local data = nil
    local candidates = { dir .. "/", dir }
    for i = 1, #candidates do
        local ret, list_data = io.lsdir(candidates[i], LIST_MAX, 0)
        if ret and type(list_data) == "table" and #list_data > 0 then
            data = list_data
            break
        end
    end
    if not data then
        return
    end

    for i = 1, #data do
        local item = data[i]
        -- type == 0 表示普通文件
        if item.type == 0 and item.name then
            local raw = tostring(item.name)
            local name = raw:match("([^/\\]+)$") or raw
            if name:lower():sub(-#HZV_SUFFIX) == HZV_SUFFIX then
                local path = dir .. "/" .. name
                if not io.exists(path) then
                    -- 条目名本身就带完整路径时，直接用条目名
                    if io.exists(raw) then
                        path = raw
                    else
                        log.warn("sd_app", "跳过打不开的条目", raw)
                        path = nil
                    end
                end
                if path then
                    list[#list + 1] = {
                        path = path,
                        name = name,
                        size = io.fileSize(path) or item.size or 0,
                    }
                end
            end
        end
    end
end

--[[
列举 TF 卡上的 HZV 素材；

@api sd_app.list_hzv()

@summary 返回 /sd 根目录下的 *.hzv 列表，按文件名升序排列，TF 卡未挂载时返回空表

@return table 素材列表，每项为 {path=, name=, size=}

@usage
local files = sd_app.list_hzv()
log.info("main", "TF 卡上的 HZV 素材数量", #files)
]]
function M.list_hzv()
    local list = {}
    if not mounted then
        log.warn("sd_app", "TF 卡未挂载，素材列表为空")
        return list
    end

    list_dir_hzv(SD_MOUNT_POINT, list)
    table.sort(list, sort_by_name)

    log.info("sd_app", "扫描到 HZV 素材数量", #list)
    for i = 1, #list do
        log.info("sd_app", "素材", list[i].name, math.floor(list[i].size / 1024) .. "KB")
    end
    return list
end

return M
