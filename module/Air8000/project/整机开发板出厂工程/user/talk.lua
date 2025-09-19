-- talk.lua
local talk = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")

local run_state = false
local input_method = require "InputMethod" 
local input_key = false
local g_dev_list
local airaudio  = require "airaudio"
extalk = require("extalk")
local local_id 

-- 初始化fskv
AIRTALK_TASK_NAME = "airtalk_task"
USER_TASK_NAME = "user"

SUCC = "success"
local speech_topic = nil
local event = ""
local talk_state = ""


-- 新增通讯录相关变量
local address_list_page = 1     -- 通讯录当前页码
local address_list_max_page = 1 -- 通讯录最大页码
local current_page = "main"     -- 当前页面状态
local contacts_per_page = 8     -- 每页显示的联系人数量

local function contact_list(dev_list)
    g_dev_list = dev_list
    for i=1,#dev_list do
        log.info("联系人ID:",dev_list[i]["id"],"名称:",dev_list[i]["name"])
    end
end

local function state(event_table)
    if event_table.state  == extalk.START then
        log.info("对讲开始，可以说话了")
        talk_state = "对讲开始，可以说话了"
    elseif  event_table.state  == extalk.STOP then
        log.info("对讲结束")
        talk_state = "对讲结束"
    elseif  event_table.state  == extalk.UNRESPONSIVE then
        log.info("对端未响应")
        talk_state = "对端未响应"
    elseif  event_table.state  == extalk.ONE_ON_ONE then
        for i=1,#g_dev_list do
            if g_dev_list[i]["id"] == event_table.id then
                log.info(g_dev_list[i]["name"],",来电话了")
                talk_state = g_dev_list[i]["name"]..",来电话了"
                break
            end
        end
    elseif  event_table.state  == extalk.BROADCAST then
        for i=1,#g_dev_list do
            if g_dev_list[i]["id"] == event_table.id then
                log.info(g_dev_list[i]["name"],"开始广播")
                talk_state = g_dev_list[i]["name"],"开始广播"
                break
            end
        end
    end
end

local extalk_configs = {
    key = PRODUCT_KEY,               -- 项目key，一般来说需要和main 的PRODUCT_KEY保持一致
    heart_break_time = 120,  -- 心跳间隔(单位秒)
    contact_list_cbfnc = contact_list, -- 联系人回调函数，回调信息含设备号和昵称
    state_cbfnc = state,  --状态回调，分为对讲开始，对讲结束，未响应
}




local function init_talk()
    log.info("init_call")
    airaudio.init()                           -- 初始化音频
    extalk.setup(extalk_configs)              -- airtalk 初始化
end





-- 绘制通讯录页面
local function draw_address_list()
    lcd.clear(_G.bkcolor)
    
    -- 绘制返回按钮 (左上角)
    lcd.showImage(10, 10, "/luadb/back.jpg")
    
    -- 绘制标题 (居中)
    lcd.drawStr(120, 30, "通讯录")
    
    -- 计算当前页的联系人起始和结束索引
    local start_index = (address_list_page - 1) * contacts_per_page + 1
    local end_index = math.min(start_index + contacts_per_page - 1, #g_dev_list)
    
    -- 绘制联系人列表
    local y_pos = 78
    for i = start_index, end_index do
        local contact = g_dev_list[i]
        
        -- 绘制ID
        lcd.drawStr(10, y_pos, "ID: " .. (contact["id"] or ""))
        
        -- 绘制名称
        lcd.drawStr(10, y_pos + 15, "名称: " .. (contact["name"] or "未知"))
        
        -- 绘制分隔线
        lcd.drawLine(5, y_pos + 35-12, 315, y_pos + 35-12)
        
        y_pos = y_pos + 40  -- 每个联系人占40像素高度
    end
    
    -- 绘制翻页按钮 (底部居中)
    local page_btn_y = 412
    if address_list_page > 1 then
        lcd.drawStr(50, page_btn_y, "上一页")
    end
    
    if address_list_page < address_list_max_page then
        lcd.drawStr(220, page_btn_y, "下一页")
    end
    
    -- 绘制页码信息 (底部居中)
    lcd.drawStr(140, page_btn_y, address_list_page .. "/" .. address_list_max_page)
    
    -- 如果正在通话，绘制停止按钮 (底部居中)
    if g_state == SP_T_CONNECTED then
        lcd.fill(120, 435, 200, 465,0xF061)  -- 绘制停止按钮边框
        lcd.drawStr(130, 462, "停止通话")
    end
    
    lcd.flush()
end

function talk.run()
    log.info("talk.run",airtalk.PROTOCOL_DEMO_MQTT_16K,mobile.imei())
    lcd.setFont(lcd.font_opposansm12_chinese)
    
    run_state = true
    local_id = mobile.imei()
    sys.taskInitEx(init_talk, USER_TASK_NAME)
    speech_topic = fskv.get("talk_number")
    log.info("get  speech_topic",speech_topic)

    while run_state do
        sys.wait(100)
        if input_method.is_active() then
            input_method.periodic_refresh()
        else
            if current_page == "main" then
                lcd.clear(_G.bkcolor) 
                if  speech_topic  == nil then
                    lcd.drawStr(0, 80, "所有要对讲的设备，要保持在线")
                    lcd.drawStr(0, 100, "方案介绍:airtalk.luatos.com")
                    lcd.drawStr(0, 120, "平台端网址:airtalk.openluat.com/talk/")
                    lcd.drawStr(0, 140, "本机ID:" .. local_id)
                    lcd.showImage(32, 250, "/luadb/input_topic.jpg")
                    lcd.showImage(32, 300, "/luadb/broadcast.jpg")
                    lcd.showImage(104, 400, "/luadb/stop.jpg")
                    
                else
                    -- lcd.drawStr(0, 80, "对端ID:"..speech_topic )
                    lcd.drawStr(0, 100, "方案介绍:airtalk.luatos.com")
                    lcd.drawStr(0, 120, "平台端网址:airtalk.openluat.com/talk/")
                    lcd.drawStr(0, 140, "所有要对讲的设备，要保持在线")
                    lcd.drawStr(0, 160, talk_state)
                    lcd.drawStr(0, 180, "事件:" .. event)
                    lcd.drawStr(0, 200, "本机ID:" .. local_id)
                    lcd.drawQrcode(185, 148, "https://airtalk.openluat.com/talk/", 82)
                    lcd.drawStr(185, 242, "扫码进入网页端",0x0000)
                    -- 显示输入法入口按钮
                    lcd.showImage(175, 300, "/luadb/datacall.jpg")
                    lcd.showImage(32, 300, "/luadb/broadcast.jpg")
                    lcd.showImage(104, 400, "/luadb/stop.jpg")
                    lcd.showImage(0, 448, "/luadb/Lbottom.jpg")
                end
                
                -- 显示通讯录按钮 (位置x10,y250)
                lcd.showImage(175, 250, "/luadb/addresslist.jpg")
                
                lcd.showImage(0,0,"/luadb/back.jpg")
                lcd.flush()
            elseif current_page == "address_list" then
                draw_address_list()
            end
        end

        if not run_state then
            return true
        end
    end
end


local function stop_talk()
    talk_state = "停止对讲"
    extalk.stop()     --   停止对讲
end


local function start_talk()
    if extalk.start(speech_topic) then
        talk_state = "发起一对一通话中...."
    end
end

local function start_broadcast()
    talk_state = "语音采集上传中,正在广播"
    extalk.start()     --   开始广播
end




-- 打开通讯录
local function open_address_list()
    if g_dev_list == nil or  #g_dev_list  == 0 then
        talk_state = "联系人列表获取失败,检测key和群组是否建立"
        log.info("联系人列表获取失败,检测key和群组是否建立")
        return false
    else 
        current_page = "address_list"
        address_list_page = 1
    end
end

-- 返回主页面
local function back_to_main()
    current_page = "main"
end

-- 选择联系人
local function select_contact(index)
    local contact_index = (address_list_page - 1) * contacts_per_page + index
    if contact_index <= #g_dev_list then
        local contact = g_dev_list[contact_index]
        if contact and contact["id"] then
            speech_topic = contact["id"]
            fskv.set("talk_number", speech_topic)
            start_talk()
            -- 对讲开始后返回到主页面
            back_to_main()
        end
    end
end

-- 处理通讯录页面的触摸事件
local function handle_address_list_touch(x, y)
    -- 返回按钮区域 (左上角)
    if x > 10 and x < 50 and y > 10 and y < 50 then
        back_to_main()
        return
    end
    
    -- 上一页按钮区域 (底部左侧)
    if address_list_page > 1 and x > 40 and x < 90 and y > 390 and y < 420 then
        address_list_page = address_list_page - 1
        return
    end
    
    -- 下一页按钮区域 (底部右侧)
    if address_list_page < address_list_max_page and x > 210 and x < 260 and y > 390 and y < 420 then
        address_list_page = address_list_page + 1
        return
    end
    
    -- 停止通话按钮区域 (底部居中)
    if g_state == SP_T_CONNECTED and x > 120 and x < 200 and y > 435 and y < 465 then
        stop_talk()
        return
    end
    
    -- 联系人选择区域 (60-380像素高度)
    if y >= 60 and y <= 380 then
        local contact_index = math.floor((y - 60) / 40) + 1
        if contact_index >= 1 and contact_index <= contacts_per_page then
            select_contact(contact_index)
        end
    end
end

function talk.tp_handal(x, y, event)
    if input_key then
        input_method.process_touch(x, y)
    else
        if current_page == "main" then
            if x > 0 and x < 80 and y > 0 and y < 80 then
                run_state = false 
            elseif x > 173 and x < 284 and y > 300 and y < 345 then
                sysplus.taskInitEx(start_talk, "start_talk")
            elseif x > 32 and x < 133 and y > 300 and y < 345 then
                sysplus.taskInitEx(start_broadcast, "start_broadcast")
            elseif x > 104 and x < 215 and y > 397 and y < 444 then
                sysplus.taskInitEx(stop_talk, "stop_talk")
            elseif x > 175 and x < 286 and y > 250 and y < 295 then  -- 通讯录按钮
                sysplus.taskInitEx(open_address_list, "open_address_list")
            end
        elseif current_page == "address_list" then
            handle_address_list_touch(x, y)
        end
    end
end

return talk