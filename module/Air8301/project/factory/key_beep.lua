--[[
@module  key_beep
@summary 全局按键音注入模块，一处改动覆盖全部按钮（Air8301 出厂固件）
@version 2.0
@date    2026.10.08
@author  江访
@usage
本模块的目标是「点击任意 UI 按钮响一下 80ms 按键音」，分两层实现，任一层成功即生效：

第一层（单点接管，覆盖最广）：
  包装 airui.container，凡通过 airui.container 创建、且配置了 on_click 的容器，
  被点击时都会先发布 KEY_BEEP_REQUEST，再执行原有回调，原有业务逻辑完全不受影响。
  该层要求 airui 是可写 table；若 airui 不是 table（例如 userdata），则自动放弃该层。

第二层（theme 级兜底，确定性）：
  无论 airui 是什么类型，theme.lua 的全部按钮封装（T.titlebar/T.btn_primary/
  T.btn_danger/T.btn_success/T.toggle_btn/T.toggle_switch）以及两个首页的网格菜单
  都会在点击时检查 _G.KEY_BEEP_ACTIVE：
    - 第一层已接管（_G.KEY_BEEP_ACTIVE == true）：由第一层统一发声，第二层不重复发声；
    - 第一层未接管：由第二层发声。
  因此一次点击永远只响一声。

安装时机：
  airui 是 LuatOS 核心库，需 airui.init() 之后才可用，故 require 时若尚未就绪，
  转入协程在 60 秒内持续重试（airui 一就绪立即完成判断与接管）。

注意：
1、本模块必须在各 UI 页面模块之前 require（main.lua 中紧跟 exwin 之后）；
2、本模块不提供对外接口，require 即完成注入；
3、本模块不直接操作 PWM，只发布 KEY_BEEP_REQUEST，发声由 buzzer_app/buzzer_drv 完成。
]]

-- ==================== 参数 ====================
local RETRY_INTERVAL_MS = 200     -- 重试间隔(ms)
local RETRY_TOTAL_MS    = 60000   -- 重试总时长上限(ms)，airui 就绪后立即结束重试

-- ==================== 内部状态 ====================
local resolved = false            -- 是否已得出最终结论（接管成功 / 确认无法接管）

--[[
把原始 on_click 回调替换为「带按键音的回调」
第一层已接管时不重复发声，交由第二层（theme 级）或本层统一发声

@local
@function wrap_container_func
@param function raw_container 原始 airui.container 函数
@return function 包装后的 airui.container 函数
]]
local function wrap_container_func(raw_container)
    local function container_with_beep(config)
        local on_click = config and config.on_click
        -- 只处理"带点击回调"的容器（其余容器保持原样，零开销）
        if type(on_click) == "function" then
            -- 命名局部函数（非匿名函数）：先响按键音，再执行原有回调
            local function on_click_with_beep(container)
                if not _G.KEY_BEEP_ACTIVE then
                    sys.publish("KEY_BEEP_REQUEST")
                end
                on_click(container)
            end
            config.on_click = on_click_with_beep
        end
        return raw_container(config)
    end
    return container_with_beep
end

--[[
第一层尝试：单点接管 airui.container

airui 就绪判断与类型判断均"类型无关"：
  - airui 尚未出现（nil）→ 返回 false，继续重试；
  - airui 不是 table（例如 userdata）→ 无法单点接管，交给 theme 级兜底，结束重试；
  - airui 是 table 且 container 可写 → 接管成功，置 _G.KEY_BEEP_ACTIVE = true。

@local
@function try_install
@return boolean true=已得出最终结论（无需再重试）
]]
local function try_install()
    if resolved then return true end

    -- 全局读取 airui（airui 未初始化时为 nil）
    local ui = airui
    if ui == nil then
        return false
    end

    local ui_type = type(ui)
    if ui_type ~= "table" then
        -- 非 table（userdata 等）：不冒险接管核心库对象，交由 theme 级按键音兜底
        resolved = true
        log.warn("key_beep", "airui 类型为", ui_type, "，无法单点接管，改由 theme 级按键音兜底")
        return true
    end

    if type(ui.container) ~= "function" then
        -- airui 出现但 container 尚未注册，继续重试
        return false
    end

    local wrapped = wrap_container_func(ui.container)
    local ok = pcall(function() ui.container = wrapped end)
    if not ok or ui.container ~= wrapped then
        -- 只读或写入被忽略：不接管，交由 theme 级兜底
        resolved = true
        log.warn("key_beep", "airui.container 只读，无法单点接管，改由 theme 级按键音兜底")
        return true
    end

    resolved = true
    _G.KEY_BEEP_ACTIVE = true
    log.info("key_beep", "按键音注入完成（airui.container 单点接管，全部按钮生效）")
    return true
end

--[[
重试协程：airui 尚未就绪时，在 RETRY_TOTAL_MS 内按 RETRY_INTERVAL_MS 重试

@local
@function install_task
]]
local function install_task()
    local waited = 0
    while waited < RETRY_TOTAL_MS do
        if try_install() then return end
        sys.wait(RETRY_INTERVAL_MS)
        waited = waited + RETRY_INTERVAL_MS
    end
    -- 超时仍未接管：theme 级兜底仍然生效，这里只提示
    log.warn("key_beep", "airui 超时未就绪，单点接管未完成，theme 级按键音兜底仍生效")
end

-- require 即尝试安装；airui 尚未就绪时转入协程重试
if not try_install() then
    log.info("key_beep", "airui 尚未就绪，转入重试安装")
    sys.taskInit(install_task)
end
