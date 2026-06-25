--[[
@module  dvp_camera_page
@summary DVP摄像头预览拍照页面：进入即预览，点击拍照，照片可保存/删除
@version 1.3
@date    2026.06.24
@author  江访
@usage
进入页面自动预览→点击预览画面拍照→显示照片→保存/删除/返回

对外接口：
1、dvp_camera_page.on_enter()：进入页面，启动预览task
2、dvp_camera_page.draw()：绘制页面
3、dvp_camera_page.on_leave()：离开页面，释放资源
4、dvp_camera_page.handle_touch()：处理触摸事件
]]

local excamera = require "excamera"

local dvp_camera_page = {}

-- DVP摄像头参数（AirCAMERA_1020，GC2145传感器，驱动IC：KC6060-V2.0）
local SENSOR_W   = 1280
local SENSOR_H   = 720
local PHOTO_PATH = "/ram/dvp_photo.jpg"

-- 页面状态
local page_state = "idle"            -- idle / preview / taking_photo / show_photo
local camera_opened = false
local photo_saved = false
local preview_task_running = false

-- 按钮区域（照片显示后的三个按钮）
local btn_w   = 120
local btn_h   = 40
local btn_y   = 430
local btn_gap = 20
local total_w = btn_w * 3 + btn_gap * 2
local start_x = math.floor((800 - total_w) / 2)

local save_btn   = { x1 = start_x,                          y1 = btn_y, x2 = start_x + btn_w,                   y2 = btn_y + btn_h }
local delete_btn = { x1 = start_x + btn_w + btn_gap,         y1 = btn_y, x2 = start_x + btn_w * 2 + btn_gap,    y2 = btn_y + btn_h }
local back_btn   = { x1 = start_x + (btn_w + btn_gap) * 2,  y1 = btn_y, x2 = start_x + btn_w * 3 + btn_gap * 2, y2 = btn_y + btn_h }


local function is_in_button(x, y, btn)
    return x >= btn.x1 and x <= btn.x2 and y >= btn.y1 and y <= btn.y2
end


-- 启动预览→拍照→显图的完整流程task
local function start_camera_flow()
    preview_task_running = true
    sys.taskInit(function()
        -- === 阶段1：纯画面预览 ===
        local param_preview = {
            id = camera.DVP,
            sensor_width = SENSOR_W,
            sensor_height = SENSOR_H,
            i2c_id = 1,
            work_mode = 2,
            save_path = PHOTO_PATH,
        }
        local ok = excamera.open(param_preview)
        camera_opened = ok
        if ok then
            excamera.preview()
            page_state = "preview"
            log.info("dvp_camera", "预览中，点击画面拍照")

            -- 预览循环：等待 handle_touch 触发拍照（通过专用消息避免与 ui_main 抢事件）
            while page_state == "preview" and preview_task_running do
                local has_trigger = sys.waitUntil("DVP_CAMERA_TRIGGER_CAPTURE", 500)
                if has_trigger then
                    log.info("dvp_camera", "触摸触发拍照")
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
                id = camera.DVP,
                sensor_width = SENSOR_W,
                sensor_height = SENSOR_H,
                i2c_id = 1,
                work_mode = 0,
                save_path = PHOTO_PATH,
            }
            local ok = excamera.open(param_capture)
            if ok then
                local result, _ = excamera.photo()
                excamera.close()
                if result then
                    photo_saved = false
                    page_state = "show_photo"
                    log.info("dvp_camera", "拍照成功")
                    -- 通知 ui_main 立即刷新显示照片
                    sys.publish("BASE_TOUCH_EVENT", nil, 0, 0)
                else
                    log.error("dvp_camera", "拍照失败，重新预览")
                    page_state = "idle"
                end
            else
                log.error("dvp_camera", "摄像头初始化失败")
                page_state = "idle"
            end
            -- 清除残留触摸事件，防止误触二次启动
            sys.publish("BASE_TOUCH_EVENT", nil, 0, 0)
        end

        preview_task_running = false
    end)
end


-- 进入页面
function dvp_camera_page.on_enter()
    page_state = "idle"
    photo_saved = false
    start_camera_flow()
end


-- 绘制页面
function dvp_camera_page.draw()
    lcd.clear()

    if page_state == "taking_photo" then
        lcd.setFont(lcd.font_opposansm12_chinese)
        lcd.setColor(0xFFFF, 0x0000)
        lcd.drawStr(350, 230, "拍照中...", 0x0000)

    elseif page_state == "show_photo" then
        lcd.setFont(lcd.font_opposansm12_chinese)
        lcd.setColor(0xFFFF, 0x0000)

        -- 全屏显示照片
        lcd.showImage(0, 0, PHOTO_PATH)

        -- 保存按钮（绿色，已保存变灰）
        if photo_saved then
            lcd.fill(save_btn.x1, save_btn.y1, save_btn.x2, save_btn.y2, 0x8888)
            lcd.drawStr(save_btn.x1 + 38, save_btn.y1 + 15, "已保存", 0xFFFF)
        else
            lcd.fill(save_btn.x1, save_btn.y1, save_btn.x2, save_btn.y2, 0x07E0)
            lcd.drawStr(save_btn.x1 + 44, save_btn.y1 + 15, "保存", 0xFFFF)
        end

        -- 删除按钮（红色）
        lcd.fill(delete_btn.x1, delete_btn.y1, delete_btn.x2, delete_btn.y2, 0xF800)
        lcd.drawStr(delete_btn.x1 + 44, delete_btn.y1 + 15, "删除", 0xFFFF)

        -- 返回按钮（灰色）
        lcd.fill(back_btn.x1, back_btn.y1, back_btn.x2, back_btn.y2, 0xC618)
        lcd.drawStr(back_btn.x1 + 44, back_btn.y1 + 15, "返回", 0xFFFF)

    elseif page_state == "idle" then
        lcd.setFont(lcd.font_opposansm12_chinese)
        lcd.drawStr(340, 230, "加载中...", 0x8888)

    elseif page_state == "preview" then
        lcd.setFont(lcd.font_opposansm12_chinese)
        lcd.drawStr(10, 10, "DVP摄像头预览", 0x0000)
        lcd.drawStr(10, 30, "点击画面拍照", 0x8888)
        lcd.drawRectangle(0, 50, 799, 429, 0x0000)

        lcd.drawStr(300, 200, "预览运行中", 0x07E0)
        lcd.drawStr(320, 220, SENSOR_W .. "x" .. SENSOR_H, 0x8888)
    end
end


-- 处理触摸事件
function dvp_camera_page.handle_touch(x, y, switch_page)
    if page_state == "preview" then
        -- 预览状态下：通知 camera task 开始拍照
        sys.publish("DVP_CAMERA_TRIGGER_CAPTURE", true)
        return true

    elseif page_state == "show_photo" then
        -- 保存
        if is_in_button(x, y, save_btn) then
            if not photo_saved then
                local data = io.readFile(PHOTO_PATH)
                if data then
                    local ts = os.date("*t")
                    local save_name = string.format("/dvp_photo_%04d%02d%02d_%02d%02d%02d.jpg",
                        ts.year, ts.month, ts.day, ts.hour, ts.min, ts.sec)
                    io.writeFile(save_name, data)
                    log.info("dvp_camera", "照片已保存:", save_name)
                    photo_saved = true
                end
            end
            return true
        end

        -- 删除 → 重新预览
        if is_in_button(x, y, delete_btn) then
            os.remove(PHOTO_PATH)
            photo_saved = false
            page_state = "idle"
            start_camera_flow()
            return true
        end

        -- 返回 → 主页
        if is_in_button(x, y, back_btn) then
            os.remove(PHOTO_PATH)
            dvp_camera_page.on_leave()
            switch_page("home")
            return true
        end
    end

    return false
end


-- 离开页面
function dvp_camera_page.on_leave()
    preview_task_running = false
    page_state = "idle"
    if camera_opened then
        excamera.close()
        camera_opened = false
    end
end

return dvp_camera_page
