local airtf = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false  -- 判断本UI DEMO 是否运行

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
        lcd.drawStr(0, 170, "循环次数: "..cycle_count)
        
        -- 显示返回按钮
        lcd.showImage(20, 360, "/luadb/back.jpg")
        lcd.flush()
        
        -- 执行当前操作
        if operation_index == 1 then
            -- 初始化SPI接口
            spi_id, pin_cs = fatfs_spi_pin()
            
            -- 启用CH390供电（GPIO140）
            local ch390_power_ok, ch390_error = pcall(function()
                gpio.setup(140, 1, gpio.PULLUP)
                sys.wait(500) -- 等待电源稳定
            end)
            
            if ch390_power_ok then
                operation_status = "CH390供电已启用"
            else
                operation_status = "CH390供电失败"
            end
            
            -- 设置SPI
            spi.setup(spi_id, nil, 0, 0, pin_cs, 400 * 1000)
            gpio.setup(pin_cs, 1)
            operation_status = operation_status..",SPI初始化完成"
            sys.wait(1000) 
            
        elseif operation_index == 2 then
            -- 挂载TF卡（带重试机制）
            mount_retry_count = mount_retry_count + 1
            local mount_ok, mount_err = fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 10 * 1000 * 1000) -- 降低SPI速率
            
            if mount_ok then
                tf_mounted = true
                operation_status = "挂载成功"
            else
                operation_status = "挂载失败("..(mount_err or "未知")..")"
                
                -- 最多重试3次
                if mount_retry_count < 3 then
                    operation_index = operation_index - 1  -- 重试当前步骤
                    operation_status = operation_status.."，重试中("..mount_retry_count.."/3)"
                else
                    operation_status = operation_status.."，已放弃"
                end
            end
            sys.wait(1000) 
            
        elseif operation_index == 3 then
            -- 创建目录
            if tf_mounted then
                if io.mkdir("/sd/io_test") then
                    operation_status = "完成"
                else
                    operation_status = "失败"
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(1000) 
            
        elseif operation_index == 4 then
            -- 创建测试文件
            if tf_mounted then
                local file = io.open("/sd/io_test/testfile.txt", "wb")
                if file then
                    file:close()
                    operation_status = "完成"
                else
                    operation_status = "失败"
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(1000)
            
        elseif operation_index == 5 then
            -- 写入内容
            if tf_mounted then
                local file = io.open("/sd/io_test/testfile.txt", "w")
                if file then
                    file:write("LuatOS TF卡测试")
                    file:close()
                    operation_status = "完成"
                else
                    operation_status = "失败"
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(1000) 
            
        elseif operation_index == 6 then
            -- 读取内容
            if tf_mounted then
                local file = io.open("/sd/io_test/testfile.txt", "r")
                if file then
                    local content = file:read("*a") or ""
                    file:close()
                    operation_status = "读取成功"
                else
                    operation_status = "失败"
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(1000) 
            
        elseif operation_index == 7 then
            -- 删除文件
            if tf_mounted then
                if os.remove("/sd/io_test/testfile.txt") then
                    operation_status = "完成"
                else
                    operation_status = "失败"
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(1000)
            
        elseif operation_index == 8 then
            -- 删除目录
            if tf_mounted then
                if io.rmdir("/sd/io_test") then
                    operation_status = "完成"
                else
                    operation_status = "失败"
                end
            else
                operation_status = "跳过(TF卡未挂载)"
            end
            sys.wait(1000) 
            
        elseif operation_index == 9 then
            -- 卸载TF卡
            if tf_mounted then
                if fatfs.unmount("/sd") then
                    tf_mounted = false
                    operation_status = "完成"
                else
                    operation_status = "失败"
                end
            else
                operation_status = "未挂载"
            end
            sys.wait(1000) 
            
        elseif operation_index == 10 then
            -- 关闭SPI
            if spi_id then
                spi.close(spi_id)
                spi_id = nil
                operation_status = "完成"
            else
                operation_status = "未初始化"
            end
            sys.wait(1000) 
        end
        
        -- 移动到下一步操作（如果未重试）
        if operation_index < #operations then
            operation_index = operation_index + 1
        else
            operation_index = 1
            mount_retry_count = 0
            cycle_count = cycle_count + 1  -- 增加循环次数
            sys.wait(1000) -- 操作完成后延时1秒再重新开始
        end
    end
    
    -- 尝试清理资源
    if tf_mounted then
        fatfs.unmount("/sd")
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
    