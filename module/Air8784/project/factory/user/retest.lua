--[[
@module  retest
@summary 出厂返工产测：fskv 返工标记 + MODEL_RETEST 指令
@version 1.0
@date    2026.10.17
@author  王世豪
@usage
第三版(V3)出厂固件：一套固件同时含产测与正式逻辑，启动按 fskv 返工标记 -> OTP1 顺序分流。
本模块负责"返工标记"与正常模式下的 MODEL_RETEST 指令(仅此一条，防误触)：
  MODEL_RETEST#CONFIRM   校验魔法字 CONFIRM(区分大小写, 去空白后全匹配)
                         -> 写 fskv 返工标记 -> 重启进产测模式
  MODEL_RETEST?          查询返工标记状态(有/无)
产测模式(TEST_DONE#)通过后删除返工标记, 全程不动 OTP1。
注: # 在此指令中是"命令/数据分隔符"(MODEL_RETEST#CONFIRM 末尾不带 #)，
    与产测指令表"命令,数据#"的 # 结束符不同，故单独解析。
]]
local retest = {}

local KEY   = "model_retest"     -- fskv 返工标记 key
local MAGIC = "CONFIRM"          -- 固定魔法字(区分大小写)
local USB   = uart.VUART_0       -- 产测/正常模式统一用 USB 虚拟串口

-- 是否已写返工标记
function retest.is_rework()
    local v = fskv.get(KEY)
    return v == true or v == 1
end

-- 写入返工标记(写后读回校验)
function retest.set_rework()
    if not fskv.set(KEY, 1) then return false end
    return retest.is_rework()
end

-- 删除返工标记(删除后读回校验落盘)
function retest.clear_rework()
    if type(fskv.del) == "function" then
        fskv.del(KEY)
    else
        fskv.set(KEY, nil)
    end
    local v = fskv.get(KEY)
    return v == nil or v == false
end

-- 执行一条已识别的 MODEL_RETEST 指令，返回回包(不含末尾 #)
function retest.apply(kind)
    if kind == "confirm" then
        if retest.is_rework() or retest.set_rework() then
            log.info("retest", "已写入返工标记, 重启进入返工产测")
            return "OK"
        end
        log.error("retest", "写返工标记失败")
        return "ERROR"
    elseif kind == "query" then
        return retest.is_rework() and "有" or "无"
    end
    return "ERROR"
end

-- 从缓冲区识别一条完整的 MODEL_RETEST 指令
-- @return kind("confirm"/"query") 或 nil, rest(消费后剩余缓冲)
function retest.parse(buf)
    local p = buf:find("MODEL_RETEST#CONFIRM", 1, true)
    if p then
        local after = p + #"MODEL_RETEST#CONFIRM"
        while after <= #buf do
            local c = buf:sub(after, after)
            if c == "#" or c == "\r" or c == "\n" or c == " " or c == "\t" then after = after + 1 else break end
        end
        return "confirm", buf:sub(1, p - 1) .. buf:sub(after)
    end
    p = buf:find("MODEL_RETEST?", 1, true)
    if p then
        local after = p + #"MODEL_RETEST?"
        while after <= #buf do
            local c = buf:sub(after, after)
            if c == "#" or c == "\r" or c == "\n" or c == " " or c == "\t" then after = after + 1 else break end
        end
        return "query", buf:sub(1, p - 1) .. buf:sub(after)
    end
    return nil, buf
end

-- 正常模式：仅注册 MODEL_RETEST 一条指令，监听 USB VUART_0
function retest.init_normal()
    uart.setup(USB, 115200)
    local buf = ""
    uart.on(USB, "receive", function(id, len)
        while true do
            local d = uart.read(USB, 512)
            if not d or #d == 0 then break end
            buf = buf .. d
        end
        while true do
            local kind, rest = retest.parse(buf)
            if not kind then break end
            buf = rest
            local reply = retest.apply(kind)
            if reply then uart.write(USB, reply .. "#") end
            if kind == "confirm" then
                -- 等 OK# 发出后再重启，避免回包丢失
                sys.taskInit(function()
                    sys.wait(500)
                    pm.reboot()
                end)
            end
        end
        if #buf > 512 then buf = buf:sub(-128) end  -- 防止无界增长(非本指令的杂数据)
    end)
    log.info("retest", "正常模式已注册 MODEL_RETEST 指令(MODEL_RETEST#CONFIRM / MODEL_RETEST?)")
end

return retest
