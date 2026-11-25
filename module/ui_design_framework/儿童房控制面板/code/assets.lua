--[[
@module  assets
@summary 卡通贴图三级解析：TF 卡 → 脚本区 → 几何降级
@version 1.0.0
@note 解析顺序（第一个存在的就是答案）：
        1) /sd/kidsroom/<name>.png   —— 用户可自己换图，插卡即生效；
        2) /luadb/<name>.png         —— 随工程打包的兜底图；
        3) nil                       —— 调用方画几何占位，界面不崩、不留空框。
      SD 卡没插 / 没格式化 / 固件无 fatfs 都只是「可降级」情况：记一次原因，不打断启动。

      贴图命名契约（docs/gen_assets.py 产出，改名字必须两边一起改）：
        ch_<theme>_<0..4>_big.png   角色大图 170x170（页1 大角色 / 页2 预览圆 / 页3 封面）
        ch_<theme>_<0..4>_sm.png    角色小图 56x56（弧上小人 / 顶栏头像 / 磁贴）
        st_<theme>_<0..5>.png       装饰贴纸 96x96（六格套图，同一张按 w/h 缩放使用）
        ic_<name>.png               功能图标 72x72（Twemoji，CC-BY 4.0）
      theme ∈ toy/bear/hero/pocket/sheep。真机图片缓存默认 1MB，
      单主题同屏解码峰值 ≈500KB（角色 5 张 + 装饰 8 张 + 图标 8 张），留足余量。
]]
local M = {}

local SD_DIR = "/sd/kidsroom/"
local LUADB_DIR = "/luadb/"
local cache = {}          -- name -> path | false
local degraded = {}       -- name -> true（只记一次日志）

local function exists(p)
    if type(io.exists) == "function" then
        local ok, r = pcall(io.exists, p)
        if ok and r then return true end
    end
    if type(io.dexist) == "function" then
        local ok, r = pcall(io.dexist, p)
        if ok and r then return true end
    end
    return false
end

--- 解析贴图路径（带缓存；失败只记一次）
--- @param name string 不含扩展名，如 "kid_moon"
--- @return string|nil path
function M.resolve(name)
    if not name then return nil end
    local hit = cache[name]
    if hit ~= nil then
        return hit or nil
    end

    local sd = SD_DIR .. name .. ".png"
    if exists(sd) then
        cache[name] = sd
        return sd
    end

    local flash = LUADB_DIR .. name .. ".png"
    if exists(flash) then
        cache[name] = flash
        return flash
    end

    cache[name] = false
    if not degraded[name] then
        degraded[name] = true
        log.warn("assets", "贴图缺失，使用几何占位", name, "已找", sd, flash)
    end
    return nil
end

--- 贴图来源统计（启动日志用，不逐帧调用）
function M.stats()
    local n_sd, n_flash, n_none = 0, 0, 0
    for _, v in pairs(cache) do
        if v == false then
            n_none = n_none + 1
        elseif type(v) == "string" and v:sub(1, 4) == "/sd/" then
            n_sd = n_sd + 1
        elseif type(v) == "string" then
            n_flash = n_flash + 1
        end
    end
    return n_sd, n_flash, n_none
end

M.sd_dir = SD_DIR
return M
