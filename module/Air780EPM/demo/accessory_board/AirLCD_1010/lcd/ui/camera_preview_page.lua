--[[
@module  camera_preview_page
@summary 摄像头页面：进入即预览，点击拍照，照片可保存/删除（AirLCD_1010触摸版，Air780EPM 自定义字体）
@version 1.0
@date    2026.06.24
@author  陈取德
]]

require "gc032a"
local excamera = require "excamera"

local camera_preview_page = {}

-- 硬件参数（Air780EPM：i2c1, camera_pwr=2）
local I2C_ID = 1
local CAM_PWR = 2
local CAM_PWDN = 5

-- 页面状态
local page_state = "idle"       -- idle / preview / taking_photo / show_photo
local camera_opened = false
local photo_saved = false
local preview_task_running = false

-- 左上角返回（show_photo时有效）
local back_button = { x1 = 10, y1 = 10, x2 = 80, y2 = 50 }

-- 显示照片页按钮（保存和删除，下方两个按钮）
local photo_buttons = {
    save   = { x1 = 30,  y1 = 380, x2 = 140, y2 = 450 },
    delete = { x1 = 180, y1 = 380, x2 = 290, y2 = 450 }
}

-- Air780EPM 使用自定义点阵字体，不依赖系统内置中文字体
local function set_cn_font()
    lcd.setFontFile("/luadb/customer_font_12.bin")
end


local function is_in_button(x, y, btn)
    return x >= btn.x1 and x <= btn.x2 and y >= btn.y1 and y <= btn.y2
end


-- 启动预览→拍照→显图的完整流程task
local function start_camera_flow()
    preview_task_running = true
    sys.taskInit(function()
        -- === 阶段1：纯画面预览 ===
        local param_preview = {
            id = "gc032a", i2c_id = I2C_ID, work_mode = 2,
            save_path = "ZBUFF",
            camera_pwr = CAM_PWR, camera_pwdn = CAM_PWDN, camera_light = nil
        }
        local ok = excamera.open(param_preview)
        camera_opened = ok
        if ok then
            excamera.preview()
            page_state = "preview"
            log.info("camera_preview", "纯画面预览中，点击任意位置拍照")

            -- 预览循环：等待触摸事件触发拍照
            while page_state == "preview" and preview_task_running do
                local has_touch, ev, tx, ty = sys.waitUntil("BASE_TOUCH_EVENT", 500)
                if has_touch and ev then
                    log.info("camera_preview", "触摸触发拍照")
                    page_state = "taking_photo"
                    break
                end
            end

            -- 关闭预览模式
            excamera.close()
            sys.wait(1000)
            camera_opened = false
        end

        -- === 阶段2：拍照 ===
        if page_state == "taking_photo" then
            local param_capture = {
                id = "gc032a", i2c_id = I2C_ID, work_mode = 0,
                save_path = "/photo.jpg",
                camera_pwr = CAM_PWR, camera_pwdn = CAM_PWDN, camera_light = nil
            }
            local ok = excamera.open(param_capture)
            if ok then
                local result, _ = excamera.photo()
                excamera.close()
                if result then
                    photo_saved = false
                    page_state = "show_photo"
                    log.info("camera_preview", "拍照成功")
                else
                    log.error("camera_preview", "拍照失败，重新预览")
                    page_state = "idle"
                end
            else
                log.error("camera_preview", "摄像头初始化失败")
                page_state = "idle"
            end
            sys.publish("BASE_TOUCH_EVENT", nil, 0, 0)
        end

        preview_task_running = false
    end)
end


function camera_preview_page.on_enter()
    page_state = "idle"
    photo_saved = false
    start_camera_flow()
end


function camera_preview_page.is_preview_raw()
    return page_state == "preview"
end


function camera_preview_page.draw()
    set_cn_font()

    if page_state == "taking_photo" then
        lcd.clear()
        lcd.setColor(0xFFFF, 0x0000)
        lcd.drawStr(110, 230, "拍照中...", 0x0000)

    elseif page_state == "show_photo" then
        lcd.clear()

        -- 全屏显示照片
        lcd.showImage(0, 0, "/photo.jpg")

        -- 返回按钮（灰色）
        lcd.fill(back_button.x1, back_button.y1, back_button.x2, back_button.y2, 0xC618)
        lcd.setColor(0x07E0, 0x0000)
        lcd.drawStr(35, 35, "返回", 0x0000)

        -- 底部操作区
        lcd.drawLine(0, 350, 320, 350, 0x8410)

        lcd.setColor(0xFFFF, 0x0000)
        if photo_saved then
            lcd.drawStr(130, 358, "已保存", 0x07E0)
        end

        -- 保存（绿色）
        lcd.fill(photo_buttons.save.x1, photo_buttons.save.y1,
            photo_buttons.save.x2, photo_buttons.save.y2, 0x07E0)
        lcd.drawStr(65, 415, "保存", 0xFFFF)

        -- 删除（红色）
        lcd.fill(photo_buttons.delete.x1, photo_buttons.delete.y1,
            photo_buttons.delete.x2, photo_buttons.delete.y2, 0xF800)
        lcd.drawStr(215, 415, "删除", 0xFFFF)

    elseif page_state == "preview" then
        -- 预览状态下显示左上角返回按钮
        lcd.fill(back_button.x1, back_button.y1, back_button.x2, back_button.y2, 0xC618)
        lcd.setColor(0x07E0, 0x0000)
        lcd.drawStr(35, 35, "返回", 0x0000)
    end
end


function camera_preview_page.handle_touch(x, y, switch_page)
    if page_state == "show_photo" then
        -- 保存
        if is_in_button(x, y, photo_buttons.save) then
            photo_saved = true
            return true
        end

        -- 删除 → 回到预览
        if is_in_button(x, y, photo_buttons.delete) then
            os.remove("/photo.jpg")
            photo_saved = false
            start_camera_flow()
            -- 等待新 task 执行到 preview 状态，让 ui_main 进入预览分支（不刷新 LCD）
            sys.wait(100)
            return true
        end

        -- 左上角返回 → 回到主页
        if x >= back_button.x1 and x <= back_button.x2 and
           y >= back_button.y1 and y <= back_button.y2 then
            switch_page("home")
            return true
        end

    elseif page_state == "preview" then
        -- 预览期间左上角返回主页
        if x >= back_button.x1 and x <= back_button.x2 and
           y >= back_button.y1 and y <= back_button.y2 then
            preview_task_running = false
            page_state = "idle"
            switch_page("home")
            return true
        end
        return false

    elseif page_state == "taking_photo" then
        return false
    end

    return false
end


function camera_preview_page.on_leave()
    preview_task_running = false
    page_state = "idle"
    if camera_opened then
        excamera.close()
        camera_opened = false
    end
    i2c.setup(I2C_ID, i2c.SLOW)
end

return camera_preview_page
