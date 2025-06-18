local airsms = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false  -- 判断本UI DEMO 是否运行
local msg_status
local showdatan=""
local showdatat_top=""
local showdatat_mid=""
local showdatat_last=""
local msg_Quantity = 0
local send_sms_num = "13316920513"
local send_sms_txt = "我是测试短信"

function start_send_sms()                                       --创建“发短信”功能函数
     msg_status = sms.send(send_sms_num, send_sms_txt) 
    --  log.info("状态：",msg_status)         --发送短信到10001，内容102
     return msg_status
end 

function split( str,reps )                                      --创建正则表达式分割函数，用于分割外部文件内容，截取关键信息，str:外部文件内容，reps：分隔符
    local resultStrList = {}                                    --创建resultStrList的table表用于接收分割后的全部数据，便于调取
    string.gsub(str,'[^..'..reps..'..]+',function ( w )         --正则表达式方式匹配str中的数据，可加回调函数。
    table.insert(resultStrList,w)                               --将分割出来的数据放入resultStrList，根据数据段落使用resultStrList[？]来调用，附带回调函数。
    end)
    return resultStrList                                        --返回resultStrList表
end

function airsms.run()       
    log.info("airsms.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
    run_state = true
    spi_init()
    sys.taskInit(read_msg_table)                                                   --执行read_msg_table功能函数，进入waitUntil状态等待信息
    sys.taskInit(read_msg) 
    while true do
        sys.wait(10)
        -- airlink.statistics()
        lcd.clear(_G.bkcolor) 
        lcd.drawStr(0,80,"按下方  开始  键,您将向"..send_sms_num.."发送短信.")
        lcd.drawStr(0,100,"内容为 : ".. send_sms_txt)
        --短信发送状态
        lcd.drawStr(0,120,"发送状态 : " )
        if msg_status then 
            lcd.drawStr(65,120,"发送成功" )
        elseif msg_status == nil then
            lcd.drawStr(65,120,"等待发送" )
        else
            lcd.drawStr(65,120,"发送失败" )
        end
        --短信内容
        lcd.drawStr(0,140,"来信号码 : "..showdatan)
        lcd.drawStr(0,155,"来信内容 : ")
        lcd.drawStr(0,175,showdatat_top)
        lcd.drawStr(0,195,showdatat_mid)
        lcd.drawStr(0,205,showdatat_last)
        lcd.drawStr(0,235,"已接收短信数量 : "..msg_Quantity)

        lcd.showImage(20,360,"/luadb/back.jpg")
        if ap_state then
            lcd.showImage(130,370,"/luadb/stop.jpg")
        else
            lcd.showImage(130,370,"/luadb/start.jpg")
        end
        lcd.showImage(0,448,"/luadb/Lbottom.jpg")
        lcd.flush()
        
        if not  run_state  then    -- 等待结束，返回主界面
            return true
        end
    end
end



function airsms.tp_handal(x,y,event)          -- 此处处理UI 的发送短信按钮
    if x > 20 and  x < 100 and y > 360  and  y < 440 then   -- 返回主界面
        run_state = false
    elseif x > 130 and  x < 230 and y > 370  and  y < 417 then
        sysplus.taskInitEx(start_send_sms, "start_send_sms")
    end
end

function spi_init()                                                             --创建SPI初始化功能函数
    --方式一：使用TF卡记录短信信息                                         
    --     gpio.setup(140, 1)                                                       --初始化SPI
    --     sys.wait(2000)
    --     local spi_id, pin_cs = 1,20 
    --     -- 仅SPI方式需要自行初始化spi, sdio不需要
    --     spi.setup(spi_id, nil, 0, 0, pin_cs, 400 * 1000)
    --     gpio.setup(pin_cs, 1)
    --     fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)          --挂载TF卡，并创建主目录/sd
    --     local data, err = fatfs.getfree("/sd")                                   --获取TF卡剩余内存空间，用于区分是否挂载成功。
    --     if data then
    --         log.info("fatfs", "getfree", json.encode(data))
    --     else
    --         log.info("fatfs", "err", err)
    --     end
    ------------------------------------------------------------------------------------------------------
    --方式二：使用Air8000内部文件空间记录短信信息
    --初始化SPI，挂载SD卡
    local f = io.open("/text.txt","w")                                         --使用"w"写入模式打开文件/text.txt，如没有该文件则创建，如有这个文件则覆盖原文件重新创建。确保开机时有这个文件。
    if f then                                                                  --判断是否正常打开，再执行写入。
    -- f:write("无信息")                                                          --写入初始信息"无信息"。
    f:close()                                                                  --每次使用后需要关闭文件。
    log.info("文件创建成功")
    end
end

function read_msg()                                                            --创建接收信息功能函数，在4G接收到信息后触发响应，将信息写入外部储存文件。   
    while 1 do                                                                 --该功能在处理完当前收到的短信后需要再回到等待底层消息的状态，所以使用无限循环。
        local ret, num, txt = sys.waitUntil("SMS_INC")                         --创建变量用于接收底层publish过来的"SMS_INC"信息，表示底层接收到了文件，返回“状态”，“来信号码”，“短信文本内容”
        log.info("收到短信,信息为：",num,"号码：",txt,ret)
        showdatat=txt
        showdatan=num
        local fd1 = io.open("/text.txt","a")                                   --使用"a"追加模式打开文件/text.txt
        if fd1 then                                     
            fd1:write(num.."*&*"..txt.."\r\n")                                 --将信息写入文件，格式为：来信号码*&*短信内容（\r\n）回车换行，*&*为分隔符。
            log.info("写入完成","号码 =",num,"内容 =",txt)
            fd1:close()                                                        --关闭文件
            sys.publish("new_msg")                                             --推送"new_msg"信息，告诉订阅方来了信的消息并且写到了文件中。
            msg_Quantity = msg_Quantity + 1
        end
    end
         
    return num , txt                                                           --该函数执行完毕后返回来信号码和短信内容，可以变量调用。
end


function read_msg_table()                                                      --创建读取文件中短信信息的功能函数
    --定义所需变量
    local msg_temp = 0     --短信临时文件
    local num_new          --最近一次来信号码
    local txt_new          --最近一次来信内容
    while 1 do                                                                 --该功能在处理完当前的信息后需要回到等待新的信息被写入文件再执行，所以此处使用无限循环
        sys.waitUntil("new_msg")                                               --等待"new_msg"消息
        local fd2 = io.open("/text.txt", "r+")                                 --使用"r+"读写模式打开已存在的/text.txt文件
        if fd2 then                                                           
            while true do                                                      --因为read()函数一次只能读一条，所以需要循环逐条输出，直到最后一条信息为nill后跳出循环。
                msg_temp = fd2:read("l")                                       --使用read()函数输出文件中的数据赋值给msg_temp，"l"模式读取下一行，在文件尾 (EOF) 处返回 nil
                if msg_temp and #msg_temp ~= 0 then                            --判断msg_temp收到信息
                    local msglist = split(msg_temp, "\\*&\\*")                 --使用正则表达式分割函数将获取到的文件原始信息分割，赋值给msglist。
                    num_new = msglist[1]                                       --msglist的第一组数据为来信号码
                    txt_new = msglist[2]                                       --msglist的第二组数据为来信内容
                else
                    break                                                      --如果msg_temp没收到信息则跳出循环。
                end
                -- log.info("最新短信：",num_new,txt_new)
                -- sys.wait(1000)
            end
            
        log.info("最新短信：",num_new,txt_new)
        fd2:close()                                                            --关闭文件
        showdatat_top = string.sub(txt_new,1,60)
        showdatat_mid = string.sub(txt_new,61,120)
        showdatat_last = string.sub(txt_new,121)
        end
    end                                              
end 
                                                        --执行read_msg功能函数，进入waitUntil状态等待信息

return airsms
