--[[
@module  main
@summary SIP/VoIP 电话应用主入口
@version 1.0.0
@date    2026.05.28
@usage
本应用实现的功能为：
1. 嵌入式物联网 SIP 交互界面
2. 支持 SIP 账户登录、注册
3. 联系人管理、通话记录、即时消息
4. 拨号盘、来电接听/拒绝
5. 集成真实 SIP 协议栈（exsip）
]]

PROJECT = "SIP_APP"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 清除可能存在的旧 .luac 缓存，确保 .lua 源码生效
-- exapp 加载模块时 .luac 优先于 .lua，修改源码后必须清除缓存
local function clear_luac_cache()
    local cache_paths = {
        "/luadb/user/sip_config.luac",
        "/luadb/user/sip_data.luac",
        "/luadb/user/sip_service.luac",
        "/luadb/user/sip_win.luac",
        "/app_store/sip/user/sip_config.luac",
        "/app_store/sip/user/sip_data.luac",
        "/app_store/sip/user/sip_service.luac",
        "/app_store/sip/user/sip_win.luac",
    }
    for _, p in ipairs(cache_paths) do
        if io and io.exists and io.exists(p) then
            local ok, err = pcall(function() os.remove(p) end)
            if ok then
                log.info("main", "清除旧 .luac 缓存:", p)
            end
        end
    end
end
clear_luac_cache()

-- 加载 SIP 业务模块和 UI 窗口
local sip_config = require "sip_config"
require "sip_data"
require "sip_service"
require "sip_win"

-- 发布消息，打开主窗口
sys.publish("OPEN_SIP_WIN")

sys.run()
