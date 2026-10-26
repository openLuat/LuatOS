--[[
@module  retest
@summary V3 工厂返工/首测中途保护模块（MODEL_RETEST + model_firsttest）
@version 1.1
@date    2026.10.20
@usage
V3 一套固件，正常模式与产测模式共用本模块。

一、返工指令（USB，文本风格 命令#数据，大小写敏感，去首尾空白后全匹配）：
  MODEL_RETEST#CONFIRM   校验固定魔法字 CONFIRM 后写 fskv 返工标记 model_retest 并重启；
                         不带魔法字 / 魔法字错误 → ERROR（防误触）
  MODEL_RETEST?          查询当前返工标记状态：HAS（有标记）/ NONE（无标记）
  响应风格：成功纯 OK，失败纯 ERROR（查询为 HAS/NONE），详细原因只进 log.error。

二、首测中途保护标记 model_firsttest（纯固件内部，工具无感）：
  裸板（OTP1 空）首次进产测时由 main.lua 自动写入，TEST_DONE 通过后由 factory.lua 删除。
  作用：MODEL/HVERSION 写 OTP1 之后，看门狗/复位类测试会重启设备，
       有此标记兜底，重启后仍进产测而不是误入正常模式；未走完流程的板子永远回产测。

启动分流由 main.lua 完成：fskv 命中 model_retest 或 model_firsttest → 产测。
产测通过后由 factory.lua 删除对应标记，重启恢复正常模式。
]]

local retest = {}

-- fskv 返工标记 key（main.lua / factory.lua / retest.lua 三处统一）
retest.KEY = "model_retest"
-- fskv 首测进行中标记 key（首次产测中途复位保护）
retest.FIRST_KEY = "model_firsttest"
-- 固定魔法字（区分大小写）
retest.MAGIC = "CONFIRM"

-- ====== 标记通用底层操作：写/删均带读回校验，防未持久化即复位 ======
local function flag_set(key)
    local ok = fskv.set(key, true)
    if not ok then
        return false, "fskv.set " .. key .. " failed"
    end
    if not fskv.get(key) then
        return false, key .. " verify failed"
    end
    return true
end

local function flag_clear(key)
    if not fskv.get(key) then
        return true -- 本来就没有标记，幂等视为成功
    end
    local ok = fskv.del(key)
    if not ok then
        return false, "fskv.del " .. key .. " failed"
    end
    if fskv.get(key) then
        return false, key .. " still exists after del"
    end
    return true
end

-- 是否已处于返工待产测状态
function retest.is_set()
    return fskv.get(retest.KEY) and true or false
end

-- 写入返工标记；返回 true 成功，false+原因 失败
function retest.set_flag()
    return flag_set(retest.KEY)
end

-- 删除返工标记；返回 true 成功，false+原因 失败（产测通过收尾用）
function retest.clear_flag()
    return flag_clear(retest.KEY)
end

-- ====== 首测中途保护标记 ======
-- 是否处于首测进行中状态
function retest.first_is_set()
    return fskv.get(retest.FIRST_KEY) and true or false
end

-- 写入首测进行中标记；返回 true 成功，false+原因 失败
function retest.first_set()
    return flag_set(retest.FIRST_KEY)
end

-- 删除首测进行中标记；返回 true 成功，false+原因 失败（TEST_DONE 收尾用）
function retest.first_clear()
    return flag_clear(retest.FIRST_KEY)
end

--[[
解析并执行一帧返工指令
@string frame 已去首尾空白的一帧文本（可能带或不带结尾 #）
@return string|nil reply 需要回给上位机的纯文本（OK/ERROR/HAS/NONE）；非本指令返回 nil
@return bool handled 是否为 MODEL_RETEST 指令（命中即拦截，不再透传）
]]
function retest.on_data(frame)
    if type(frame) ~= "string" then return nil, false end
    local s = frame:gsub("^%s*", ""):gsub("%s*$", "")
    if s == "" then return nil, false end

    -- 查询：MODEL_RETEST?（允许带结尾 #）
    if s == "MODEL_RETEST?" or s == "MODEL_RETEST?#" then
        return retest.is_set() and "HAS" or "NONE", true
    end

    -- 必须以 MODEL_RETEST# 起头，且去尾后整帧只有一段（防止前缀误匹配透传数据）
    local prefix = "MODEL_RETEST#"
    if s:sub(1, #prefix) ~= prefix then
        return nil, false
    end

    -- 取 # 之后的数据，去掉可能的结尾 # 和首尾空白后与魔法字全匹配（区分大小写）
    local arg = s:sub(#prefix + 1):gsub("#+$", "")
    arg = arg:gsub("^%s*", ""):gsub("%s*$", "")
    if arg ~= retest.MAGIC then
        log.error("retest", "魔法字校验失败，拒绝写返工标记:", arg)
        return "ERROR", true
    end

    local ok, err = retest.set_flag()
    if not ok then
        log.error("retest", "写返工标记失败:", err)
        return "ERROR", true
    end

    log.info("retest", "返工标记已写入，800ms 后重启进产测模式")
    if pm and pm.reboot then
        sys.timerStart(pm.reboot, 800) -- 留足时间把 OK 发出去再重启
    else
        log.error("retest", "固件不支持 pm.reboot，标记已写入，请手动重启")
    end
    return "OK", true
end

return retest
