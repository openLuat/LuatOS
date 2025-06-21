local aircall = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false -- 判断本UI DEMO 是否运行
local airaudio  = require "airaudio"
local phone_number = "13917187172"

local function init_call()
    log.info("init_call")
    local up1 = zbuff.create(6400, 0) -- 上行数据保存区1
    local up2 = zbuff.create(6400, 0) -- 上行数据保存区2
    local down1 = zbuff.create(6400, 0) -- 下行数据保存区1
    local down2 = zbuff.create(6400, 0) -- 下行数据保存区2
    local cnt = 0

    airaudio.init() 

    cc.record(true, up1, up2, down1, down2)

    cc.init(multimedia_id) -- 初始化电话功能

end

local function stop_call()
    log.info("挂断电话")
    cc.hangUp(0)
end

local function recv_call()
    log.info("recv_call")
    log.info("来电号码", cc.lastNum())
    log.info("接电话", cc.accept(0))

end

local function start_call()
    log.info("开始打电话")
    cc.dial(0, phone_number) -- 拨打电话
end

function aircall.run()
    log.info("aircall.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
    run_state = true

    init_call() -- 初始化电话功能相关配置

    while true do
        sys.wait(10)
        -- airlink.statistics()
        lcd.clear(_G.bkcolor)
        lcd.drawStr(0, 80, "需要代码内修改拨打的号码")
        if cc.lastNum() then
            lcd.drawStr(0, 90, "当前来电号码：" .. cc.lastNum())
        else
            lcd.drawStr(0, 90, "当前没有来电号码")
        end

        -- [
        -- 此处可填写demo ui
        -- ]

        lcd.showImage(20, 360, "/luadb/back.jpg")
        lcd.showImage(130, 303, "/luadb/stop.jpg") -- 挂断&拒接电话
        lcd.showImage(130, 350, "/luadb/start.jpg") -- 接电话
        lcd.showImage(130, 397, "/luadb/start.jpg") -- 拨打电话

        lcd.showImage(0, 448, "/luadb/Lbottom.jpg")
        lcd.flush()

        if not run_state then -- 等待结束，返回主界面
            return true
        end
    end
end

function aircall.tp_handal(x, y, event)
    if x > 20 and x < 100 and y > 360 and y < 440 then
        run_state = false
    elseif x > 130 and x < 230 and y > 303 and y < 350 then
        sysplus.taskInitEx(stop_call, "stop_call")
    elseif x > 130 and x < 230 and y > 350 and y < 397 then
        sysplus.taskInitEx(recv_call, "recv_call")
    elseif x > 130 and x < 230 and y > 397 and y < 444 then
        sysplus.taskInitEx(start_call, "start_call")
    end
end

return aircall
