local airtf = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false  -- 判断本UI DEMO 是否运行
local fail = 0
local sucess = 0
local function fatfs_spi_pin()
    return 1, 20 -- Air8000整机开发板上的pin_cs为gpio20，spi_id为1
end

function airtf.run()       
    log.info("airtf.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
    run_state = true
    
    -- TF卡操作步骤
    local operations = {
        "初始化SPI接口",
        "挂载TF卡",
        "创建目录",
        "创建测试文件",
        "写入内容",
        "读取内容",
        "删除文件",
        "删除目录",
        "卸载TF卡",
        "关闭SPI"
    }
    
    local operation_index = 1
    local operation_status = ""
    local spi_id, pin_cs
    local tf_mounted = false
    local mount_retry_count = 0  -- 挂载重试计数器
    local cycle_count = 0  -- 循环次数计数器
    
    while run_state do
        sys.wait(10)
        lcd.clear(_G.bkcolor) 
        lcd.drawStr(0, 80, "TF卡测试")
        
        -- 显示当前操作状态
        lcd.drawStr(0, 110, operations[operation_index]..": "..operation_status)
        
        -- 显示进度
        local progress = math.floor(operation_index * 100 / #operations)
        lcd.drawStr(0, 140, "进度: "..progress.."%")
        
        -- 显示循环次数
        lcd.drawStr(0, 170, "循环次数: "..cycle_count  )
        lcd.drawStr(0, 190, "成功次数: "..sucess )
        lcd.drawStr(0, 210, "失败次数:".. fail )

        -- 显示返回按钮
        lcd.showImage(20, 360, "/luadb/back.jpg")
        lcd.flush()
        
        -- 执行当前操作
        if operation_index == 1 then
            -- 初始化SPI接口
            spi_id, pin_cs = fatfs_spi_pin()
        

            spi.setup(spi_id, nil, 0, 0, 8, 400 * 1000)      --  初始化SPI 接口
      
            operation_status = "SPI初始化完成"
            sys.wait(50) 
            
        elseif operation_index == 2 then
            -- 挂载TF卡（带重试机制）
            mount_retry_count = mount_retry_count + 1
            
            fatfs.unmount("/sd")
            local mount_ok, mount_err = fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 10 * 1000 * 1000) -- 传输tf 卡的片选
            

            if  mount_ok then
                tf_mounted = true
                operation_status = "挂载成功"
                os.remove("/sd/io_test/testfile.txt")
                io.rmdir("/sd/io_test")
            else
                operation_status = "挂载失败("..(mount_err or "未知")..")"
                log.info(operation_status)
                fail = fail + 1
                operation_index = 1
                -- 最多重试3次
                if mount_retry_count < 3 then
                    operation_index = operation_index - 1  -- 重试当前步骤
                    operation_status = operation_status.."，重试中("..mount_retry_count.."/3)"
                else
                    operation_status = operation_status.."，已放弃"
                end
            end
            sys.wait(50) 
            
        elseif operation_index == 3 then
            -- 创建目录
            if tf_mounted then
                if io.mkdir("/sd/io_test") then
                    operation_status = "创建目录完成"
                else
                    operation_status = "创建目录失败1"
                    log.info(operation_status)
                    fail = fail + 1
                    operation_index = 1
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(50) 
            
        elseif operation_index == 4 then
            -- 创建测试文件
            if tf_mounted then
                local file = io.open("/sd/io_test/testfile.txt", "wb")
                if file then
                    file:close()
                    operation_status = "创建测试文件完成"
                else
                    operation_status = "创建测试文件失败"
                    log.info(operation_status)
                    fail = fail + 1
                    operation_index = 1
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(50)
            
        elseif operation_index == 5 then
            -- 写入内容
            if tf_mounted then
                local file = io.open("/sd/io_test/testfile.txt", "w")
                if file then
                    file:write("LuatOS TF卡测试")
                    file:close()
                    operation_status = "写入内容完成"
                else
                    operation_status = "写入内容失败"
                    log.info(operation_status)
                    fail = fail + 1
                    operation_index = 1
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(50) 
            
        elseif operation_index == 6 then
            -- 读取内容
            if tf_mounted then
                local file = io.open("/sd/io_test/testfile.txt", "r")
                if file then
                    local content = file:read("*a") or ""
                    file:close()
                    operation_status = "读取成功"
                else
                    operation_status = "读取失败"
                    log.info(operation_status)
                    fail = fail + 1
                    operation_index = 1
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(50) 
            
        elseif operation_index == 7 then
            -- 删除文件
            if tf_mounted then
                if os.remove("/sd/io_test/testfile.txt") then
                    operation_status = "删除文件完成"
                else
                    operation_status = "删除文件失败"
                    log.info(operation_status)
                    fail = fail + 1
                    operation_index = 1
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(50)
            
        elseif operation_index == 8 then
            -- 删除目录
            if tf_mounted then
                if io.rmdir("/sd/io_test") then
                    operation_status = "删除目录完成"
                else
                    operation_status = "删除目录失败"
                    log.info(operation_status)
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(50) 
            
        elseif operation_index == 9 then
            -- 卸载TF卡
            if tf_mounted then
                if fatfs.unmount("/sd") then
                    tf_mounted = false
                    operation_status = "卸载TF卡完成"
                else
                    operation_status = "卸载TF卡失败"
                    log.info(operation_status)
                    fail = fail + 1
                    operation_index = 1
                end
            else
                operation_status = "未挂载"
            end
            sys.wait(50) 
            
        elseif operation_index == 10 then
            -- 关闭SPI
            if spi_id then
                spi.close(spi_id)
                spi_id = nil
                operation_status = "关闭SPI完成"
                sucess = sucess +1
            else
                operation_status = "关闭SPI失败"
                log.info(operation_status)
                fail = fail + 1
                operation_index = 1
            end
            sys.wait(50) 
        end
        
        -- 移动到下一步操作（如果未重试）
        if operation_index < #operations then
            operation_index = operation_index + 1
        else
            operation_index = 1
            mount_retry_count = 0
            cycle_count = cycle_count + 1  -- 增加循环次数
            sys.wait(50) -- 操作完成后延时1秒再重新开始
        end
    end
    
    -- 尝试清理资源
    if tf_mounted then
        fatfs.unmount("/sd")
        tf_mounted = false
    end
    if spi_id then
        spi.close(spi_id)
    end
    
    return true
end

function airtf.tp_handal(x, y, event)       
    if x > 20 and x < 100 and y > 360 and y < 440 then   -- 返回主界面
        run_state = false
    end
end

return airtf
    