--[[
@module  cfg_fetch
@summary 服务端配置持久化加载（db 存储）
开机流程：cfg_fetch.init() 从文件系统加载持久化配置，有则供应用直接使用。
]]
local cfg_fetch = {}

local db = require("db")
local cfg

-- 配置文件路径
local CFG_PATH = "/luadb/air8201.cfg"

-- 初始化：从文件系统加载持久化配置
-- @return table|nil 返回配置表，nil 表示无本地配置
function cfg_fetch.init()
    cfg = db.new(CFG_PATH)
    local sheet = cfg:export()
    if type(sheet) == "table" and sheet.uconf then
        log.info("cfg_fetch", "从文件系统加载配置成功，param_ver:", sheet.param_ver)
        -- 应用配置中的 project_key
        if sheet.project_key then
            _G.PRODUCT_KEY = sheet.project_key
        end
        return sheet
    else
        log.info("cfg_fetch", "无本地持久化配置")
        return nil
    end
end

return cfg_fetch
