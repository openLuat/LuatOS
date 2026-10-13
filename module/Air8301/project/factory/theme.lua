--[[
@module  theme
@summary UI 共享主题模块（Air8301 出厂固件）— 向后兼容桥接层（极简版）
@version 2.0
@date    2026.10.10
@author  江访

@usage
本模块原为「向后兼容桥接层」，承载旧版 iOS 风格主题的颜色/布局/字号常量
以及 titlebar / info_card / btn_primary / btn_danger / btn_success /
toggle_btn / toggle_switch / toggle_switch_update 等 UI 构建函数。

经全工程逐文件核对：全部页面（业务 20 页 + 产测 14 页 + 开机画面）已统一
使用新设计系统 ui_theme，上述常量与函数的调用点仅剩 with_beep 一处，
为压缩脚本体积（变更 25）已全部删除，本模块仅保留：

  T.with_beep(fn)   包装点击回调：先发非阻塞按键音，再执行原回调
                    供 idle_win / comm_win / sys_win / io_win / prod_idle_win 磁贴使用

@note 新页面请直接 require "ui_theme" 并使用其组件与页面骨架，不要再向本模块新增接口。
]]

local T = {}

-- ==================== 按键音兜底 ====================

local buzzer_mod = nil

--[[按需加载蜂鸣器驱动（加载失败返回 nil，不影响点击主逻辑）]]
local function load_buzzer()
    if buzzer_mod == nil then
        local ok, drv = pcall(require, "buzzer_drv")
        buzzer_mod = ok and drv or false
    end
    return buzzer_mod or nil
end

--[[
包装点击回调：先发非阻塞提示音，再执行原回调

@param function fn 原点击回调
@return function   包装后的回调（fn 非法时原样返回）
]]
function T.with_beep(fn)
    if type(fn) ~= "function" then return fn end
    local function wrapped()
        local drv = load_buzzer()
        if drv and drv.beep_bg then drv.beep_bg(40) end
        fn()
    end
    return wrapped
end

_G.T = T

return T
