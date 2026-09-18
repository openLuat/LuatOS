--[[
@module  factory_app
@summary 应用工厂业务层入口（语音生成 APP 容器）
@version 4.0
@date    2026.08.13
@author  江访
@usage
应用工厂是引擎主机内置应用，当前主功能为"语音生成 APP"：
- 进入应用工厂直接打开语音生成 APP 窗口（factory_win），无功能列表主页
- 录音→停止→生成：上传录音与设备信息到服务端生成 APP，轮询进度，成功后点击安装
本模块负责：
1. 级联加载各功能子业务模块（factory_rec：录音 + 应用生成上传/轮询/安装）
2. 提供功能列表数据源（保留接口，当前仅一个功能，UI 直接进入窗口）

将来扩展：新增功能时按需恢复功能列表主页模式。
]]

local M = {}

-- ==================== 功能列表（应用工厂的入口功能） ====================
-- 当前 UI 直接进入生成 APP 窗口，列表仅作数据源保留
local features = {
    { id = "chat", name = "语音生成APP", icon = "/luadb/app_factory.png", win = "FACTORY" },
}

--[[
获取功能列表
@return table 功能列表
]]
function M.get_features()
    return features
end

--[[
按 id 获取功能项
@param id string 功能 id
@return table|nil 功能项
]]
function M.get_feature(id)
    for _, f in ipairs(features) do
        if f.id == id then
            return f
        end
    end
    return nil
end

-- ==================== 级联加载子业务模块 ====================
-- 录音 + 应用生成业务（exaudio + make_app）：订阅 FACTORY_REC_* / FACTORY_MAKE_* 事件
require "factory_rec"

return M
