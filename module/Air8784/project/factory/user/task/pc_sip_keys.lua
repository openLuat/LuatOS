-- Windows 控制台键盘；只发布业务事件，不直接操作 SIP/VoIP。
local M = {}
function M.new(publish, show)
    local state, editing, number, pending = "INIT", false, "", false
    local C = {}
    function C.state(value)
        state, pending = value, false
        editing, number = false, ""
        if value == "INCOMING" then show("来电：回车接听，退格拒接")
        elseif value == "READY" then show("回车输入 SIP 号码")
        elseif value == "CONNECTED" then show("通话中：退格挂断") end
    end
    function C.key(key)
        if pending then return end
        if state == "INCOMING" then
            if key == "enter" or key == "backspace" then
                pending = true
                publish(key == "enter" and "SIP_APP_MAIN_ACCEPT_REQ" or "SIP_APP_MAIN_HANGUP_REQ")
            end
        elseif state == "DIALING" or state == "ANSWERING" or state == "CONNECTED" then
            if key == "backspace" then pending=true;publish("SIP_APP_MAIN_HANGUP_REQ") end
        elseif state == "READY" then
            if key == "enter" then
                if not editing then editing=true;show("请输入 SIP 号码，回车拨号，退格编辑")
                elseif #number > 0 then
                    local target=number
                    pending,editing,number=true,false,""
                    show("拨号："..target)
                    publish("SIP_APP_MAIN_DIAL_REQ", "pc-keyboard", target)
                else show("号码为空，请输入 SIP 号码") end
            elseif editing and key == "backspace" then
                if #number == 0 then editing=false;show("已取消号码输入")
                else number=number:sub(1,-2);show("SIP 号码："..number) end
            elseif editing and #key == 1 and key:match("^[A-Za-z0-9+*#_.%-]$") then
                if #number < 64 then number=number..key;show("SIP 号码："..number)
                else show("SIP 号码最多 64 字符") end
            end
        elseif key == "enter" then show("尚未注册或音频未就绪，暂不可拨号") end
    end
    return C
end
function M.start()
    if not pcconsole then log.warn("pc_sip_keys", "请更新模拟器以启用键盘接听/拨号");return end
    local ok,err=pcconsole.open()
    if not ok then log.warn("pc_sip_keys",err);return end
    local controller=M.new(sys.publish,function(message) log.info("pc_sip_keys",message) end)
    sys.subscribe("SIP_APP_STATE",controller.state)
    sys.timerLoopStart(function()
        for _,key in ipairs(pcconsole.poll()) do controller.key(key) end
    end,20)
    log.info("pc_sip_keys","键盘已启用：回车接听/输入/拨号，退格拒接/挂断/删除")
end
return M
