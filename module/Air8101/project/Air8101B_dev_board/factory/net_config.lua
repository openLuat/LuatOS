--[[
@module  net_config
@summary 多网融合优先级配置（存 fskv，改完立即生效）
@version 1.0
@date    2026.10.19
@usage
结构与 Air8301 出厂固件一致（net_config + multi_net_win）：
    列表顺序 = 优先级，第一项最高
    上移/下移 → save() → 发布 NET_CONFIG_UPDATED
    → app_net 收到后在 task 里重新 exnetif.set_priority_order（增量重排，不用重启）

对外接口
1. net_config.load()          → { "eth", "wifi", "4g" } 之类（已规范化）
2. net_config.save(list)      → 保存并广播，返回规范化后的列表
3. net_config.reset()         → 恢复默认顺序
4. net_config.name(key)       → 显示名
5. net_config.ITEMS           → { {key, name}, ... } 全部可选网卡（固定顺序，仅用于展示）
]]

local M = {}

local KEY = "net_priority"

-- 全部可选网卡（只用于展示与补全，不代表优先级）
M.ITEMS = {
    { key = "eth",  name = "以太网" },
    { key = "wifi", name = "WiFi" },
    { key = "4g",   name = "4G" },
}

-- 默认优先级：以太网 > WiFi > 4G（与改动前 app_net 的固定顺序一致）
M.DEFAULT = { "eth", "wifi", "4g" }

local function valid_key(key)
    for _, it in ipairs(M.ITEMS) do
        if it.key == key then return true end
    end
    return false
end

--- 规范化：过滤非法项、去重，再按 ITEMS 补齐缺失项（补在末尾）
local function normalize(list)
    local out, seen = {}, {}
    if type(list) == "table" then
        for _, key in ipairs(list) do
            if valid_key(key) and not seen[key] then
                seen[key] = true
                out[#out + 1] = key
            end
        end
    end
    for _, it in ipairs(M.ITEMS) do
        if not seen[it.key] then
            out[#out + 1] = it.key
        end
    end
    return out
end

--- 读取当前优先级（fskv 里存的是逗号分隔字符串，兼容旧固件）
function M.load()
    local raw = nil
    local ok, v = pcall(fskv.get, KEY)
    if ok then raw = v end

    local list = {}
    if type(raw) == "string" and raw ~= "" then
        for key in raw:gmatch("[^,]+") do
            list[#list + 1] = key
        end
    elseif type(raw) == "table" then
        list = raw
    end
    return normalize(list)
end

function M.save(list)
    list = normalize(list)
    local old = M.load()
    local changed = table.concat(old, ",") ~= table.concat(list, ",")
    if not changed then
        log.info("net_config", "优先级未变化:", table.concat(list, " > "))
        return list, false
    end

    local ok = pcall(fskv.set, KEY, table.concat(list, ","))
    if not ok then
        log.warn("net_config", "优先级写入 fskv 失败（本次仍会生效，重启后丢失）")
    end
    log.info("net_config", "优先级已保存:", table.concat(list, " > "))
    sys.publish("NET_CONFIG_UPDATED", list)
    return list, true
end

--- 恢复默认顺序
function M.reset()
    return M.save(M.DEFAULT)
end

--- 网卡 key → 显示名
function M.name(key)
    for _, it in ipairs(M.ITEMS) do
        if it.key == key then return it.name end
    end
    return tostring(key)
end

return M