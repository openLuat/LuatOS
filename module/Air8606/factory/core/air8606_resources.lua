--[[
@module air8606_resources
@summary Air8606 共享引脚互斥和电源域引用计数
@version 1.0.0
@date 2026.11.10

camera_485: 摄像头 UART3 与两路 485 的 GPIO14 电源域互斥。
uart2: CAN2 与 RS232 共用引脚互斥。切换前必须成功关闭原拥有者。
claim/release 只管理所有权，电源由 power_on/power_off 单独管理。
]]
local M = {}
local groups = {}
local powers = {}
local cameras = {}
local request_seq = 0

local function drive(pin, level)
    if not gpio or type(gpio.setup) ~= "function" or type(gpio.set) ~= "function" then
        return false, "固件缺少 GPIO 库"
    end
    local ok, ret = pcall(gpio.setup, pin, level)
    if not ok or not ret then return false, "GPIO 初始化失败: " .. tostring(pin) end
    ok, ret = pcall(gpio.set, pin, level)
    if not ok or ret == false then return false, "GPIO 写入失败: " .. tostring(pin) end
    return true
end

-- stop 必须返回 true 才能把同一组交给另一种用途；切换中拒绝并发申请。
function M.claim(group, kind, owner, stop)
    if not group or not owner then return false, "缺少资源拥有者" end
    local state = groups[group]
    if not state then state = { owners = {} }; groups[group] = state end
    if state.busy then return false, "资源正在切换: " .. group end
    if state.owners[owner] then return true end
    state.busy = true
    local conflicts = {}
    for old, item in pairs(state.owners) do
        if item.kind ~= kind then conflicts[#conflicts + 1] = { owner=old, item=item } end
    end
    for _, old in ipairs(conflicts) do
        local ok, ret, err = pcall(old.item.stop, old.owner)
        if not ok or ret ~= true then
            state.busy = false
            return false, tostring(err or ret or "共享外设释放失败")
        end
        state.owners[old.owner] = nil
    end
    state.owners[owner] = { kind=kind, stop=stop }
    state.busy = false
    sys.publish("AIR8606_RESOURCE_CHANGED", group, kind)
    return true
end

function M.release(group, owner)
    local state = groups[group]
    if state then state.owners[owner] = nil end
end

function M.power_on(pin, owner)
    if pin == nil then return true end
    local state = powers[pin]
    if not state then state = {}; powers[pin] = state end
    local ok, err = drive(pin, 1)
    if not ok then return false, err end
    state[owner] = true
    return true
end

function M.power_off(pin, owner, hold)
    if pin == nil then return true end
    local state = powers[pin]
    if not state or not state[owner] then return true end
    local others = false
    for other in pairs(state) do
        if other ~= owner then others = true; break end
    end
    if not others and not hold then
        local ok, err = drive(pin, 0)
        if not ok then return false, err end
    end
    state[owner] = nil
    if not next(state) then powers[pin] = nil end
    return true
end

function M.power_users(pin)
    local count = 0
    for _ in pairs(powers[pin] or {}) do count = count + 1 end
    return count
end

-- UVC 页只在持有供电且准备开流时置 true，停流/人脸串口释放后置 false。
function M.camera_active(id, active)
    if active ~= nil then cameras[id] = active and true or nil end
    return cameras[id] == true
end

-- 远端命令完成后再报告成功；未收到 ACK 则返回失败，不能把已排队当作已完成。
function M.await_request(submit, timeout)
    if not (coroutine and coroutine.isyieldable and coroutine.isyieldable()) then
        return false, nil, "操作必须在 sys.taskInit 协程内执行"
    end
    request_seq = request_seq + 1
    local event = "AIR8606_REQUEST_DONE_" .. tostring(request_seq)
    local finished, success, response, reason = false, false, nil, nil
    local function done(ok, data, err)
        finished, success, response, reason = true, ok == true, data, err
        sys.publish(event)
    end
    local ok, ret, err = pcall(submit, done)
    if not ok then return false, nil, tostring(ret) end
    if not ret then return false, nil, tostring(err or "命令未发送") end
    if not finished then sys.waitUntil(event, timeout or 5500) end
    if not finished then return false, nil, "等待远端确认超时" end
    return success, response, reason
end

return M
