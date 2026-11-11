--[[
@module  pin_share
@summary 共享 GPIO 职能仲裁：一根物理脚被多个外设职能共用时的互斥切换
@version 1.0
@date    2026.11.11
@author  江访

=== 背景 ===

8603W3~W5 / M3~M5 六型号的 PIN48 = GPIO58 一根脚两个职能：UVC_EN（摄像头供电开启）
与 485_EN2（UART2 那路隔离 485 的 DE 方向脚）。同一时刻只干一个活——拉高给摄像头
供电时 485 收发器被顶在发送态；做 DE 停在接收态（低电平）时摄像头没电。
两个功能做成**相互切换、互不影响**：谁要用谁认领，进谁的测试页脚就切给谁，
退出归还；切换时把原职能停干净再易主，反复切换互不留影响。

=== 接口 ===

M.claim(pin, role, owner, on_lost) → ok
    认领一脚。pin 当前归别的 role 时先触发该 role 全部持主的 on_lost(pin, owner)
    交接（原主自行停干净），再换新 role 挂牌；同 role 多个持主共存（如同一 uart
    多路 485 共用一根 DE），互不打搅
M.release(pin, owner)      归还；owner 不匹配（已被别人接管）则忽略
M.role(pin)         → role|nil   当前职能，形如 "uvc_en" / "rs485_de"
M.reset()                  清空全部认领（测试复位用）

=== 约定 ===

- role 是职能名（"uvc_en" / "rs485_de"），owner 是持主实例（"uvc:uvc1" / "rs485:485_2"）；
  同 role 认领共存，异 role 认领即切换
- 同一 owner 重复 claim 只刷新 on_lost，不打断自己
- on_lost 在旧持主已被摘牌后、新主挂牌前同步调用：旧主停干净后不必再 release
  （已摘牌，落空无害），也**不要动这根脚的电平**——电平由新主认领后自己写
- on_lost 抛错被 pcall 吞掉记日志，不阻断切换；on_lost 里不要再 claim 同一脚
- 本模块只管「谁在用」，不动任何 GPIO 电平
]]

local M = {}

-- pin → { role = 职能名, owners = { [owner] = on_lost|nil, ... } }
local holders = {}

--[[
认领一脚（异 role 即职能切换，先让旧职能交接）
@param number|string pin  GPIO 编号
@param string role  职能名，如 "uvc_en" / "rs485_de"
@param string owner  持主实例，如 "uvc:uvc1" / "rs485:485_2"
@param function|nil on_lost  被别的职能切走时的交接回调 on_lost(pin, owner)
@return boolean
]]
function M.claim(pin, role, owner, on_lost)
    if pin == nil or not role or not owner then return false end
    local rec = holders[pin]
    if rec and rec.role ~= role then
        -- 职能切换：旧 role 的全部持主先交接（摘牌后回调，回调里停干净、不动脚电平）
        log.info("pin_share", "GPIO" .. tostring(pin), "职能切换", rec.role .. " → " .. role,
                 "新主 " .. tostring(owner))
        local old = rec.owners
        holders[pin] = nil
        for old_owner, fn in pairs(old) do
            if type(fn) == "function" then
                local ok, err = pcall(fn, pin, old_owner)
                if not ok then
                    log.warn("pin_share", "交接回调出错", tostring(old_owner), tostring(err))
                end
            end
        end
        rec = nil
    end
    if not rec then
        rec = { role = role, owners = {} }
        holders[pin] = rec
    end
    rec.owners[owner] = on_lost
    return true
end

--[[
归还一脚；owner 不匹配（已被别人接管）则忽略
@param number|string pin  GPIO 编号
@param string owner  持主实例
@return boolean
]]
function M.release(pin, owner)
    local rec = holders[pin]
    if not rec or not owner then return false end
    if rec.owners[owner] == nil then return false end
    rec.owners[owner] = nil
    if next(rec.owners) == nil then holders[pin] = nil end
    return true
end

--[[
当前持用该脚的职能
@param number|string pin  GPIO 编号
@return string|nil  职能名，无人占用为 nil
]]
function M.role(pin)
    local rec = holders[pin]
    return rec and rec.role or nil
end

-- 清空全部认领（测试复位用）
function M.reset()
    holders = {}
    return true
end

return M
