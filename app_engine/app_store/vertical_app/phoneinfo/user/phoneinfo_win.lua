--[[
@module  phoneinfo_win
@summary 手机号码归属地查询窗口
@version 1.0
@date    2026.04.11
@author  xulu
@usage
本模块实现手机号码归属地查询功能，包括：
1. 11位手机号码输入
2. 实时查询归属地（省/市）
3. 运营商识别（移动/联通/电信/广电）
4. 网络请求失败状态提示
5. 数据加载状态显示
]]

local win_id = nil
local main_container

-- API配置
local API_URL = "https://cn.apihz.cn/api/ip/shouji.php"
local API_ID = "10015156"
local API_KEY = "f30af70870591caeec9ada8abcb55933"

-- UI组件
local phone_input
local location_label
local operator_label
local area_code_label
local zip_code_label
local error_label
local query_btn
local reset_btn
local phone_keyboard  -- 数字键盘

-- 显示提示信息
local function show_message(msg, is_error)
    if error_label then
        error_label:set_text(msg or "")
        if is_error then
            error_label:set_color(0xc44536)
        else
            error_label:set_color(0x2a7a3e)
        end
    end
end

-- 清空错误提示
local function clear_message()
    if error_label then
        error_label:set_text("")
    end
end

-- 显示查询结果
local function show_result(location, operator, area_code, zip_code)
    if location_label then
        location_label:set_text(location or "未知地区")
    end
    if operator_label then
        operator_label:set_text(operator or "未知")
    end
    if area_code_label then
        area_code_label:set_text(area_code or "")
    end
    if zip_code_label then
        zip_code_label:set_text(zip_code or "")
    end
    clear_message()
end

-- 显示错误
local function show_error(msg)
    if location_label then
        location_label:set_text("查询失败")
    end
    if operator_label then
        operator_label:set_text("")
    end
    if area_code_label then
        area_code_label:set_text("")
    end
    if zip_code_label then
        zip_code_label:set_text("")
    end
    show_message(msg or "查询失败，请稍后重试", true)
end

-- 重置界面
local function reset_form()
    if phone_input then
        phone_input:set_text("")
    end
    if location_label then
        location_label:set_text("实时查询， 精确到城市")
    end
    if operator_label then
        operator_label:set_text("")
    end
    if area_code_label then
        area_code_label:set_text("")
    end
    if zip_code_label then
        zip_code_label:set_text("")
    end
    clear_message()
end

-- 调用API查询归属地
local function query_phone(phone_num)
    if not phone_num or #phone_num ~= 11 then
        show_error("请输入11位有效手机号")
        return
    end
    
    if query_btn then
        query_btn:set_text("查询中...")
    end
    
    -- 在协程中执行HTTP请求，避免阻塞UI线程
    sys.taskInit(function()
        local url = string.format("%s?id=%s&key=%s&phone=%s", API_URL, API_ID, API_KEY, phone_num)
        
        -- 使用同步方式调用HTTP请求
        local code, headers, data = http.request("GET", url).wait(8000)
        
        if query_btn then
            query_btn:set_text("查询归属地")
        end
        
        if code == 200 and data then
            local ok, result = pcall(json.decode, data)
            if ok and result and result.code == 200 then
                local province = result.shengfen or ""
                local city = result.chengshi or ""
                local operator_raw = result.fuwushang or ""
                local area_code = result.quhao or ""
                local zip_code = result.youbian or ""
                
                local location = ""
                if province ~= "" and city ~= "" and province ~= city then
                    location = province .. " " .. city
                elseif city ~= "" then
                    location = city
                elseif province ~= "" then
                    location = province
                else
                    location = "中国"
                end
                
                local operator = operator_raw
                if operator_raw then
                    if string.find(operator_raw, "移动") then
                        operator = "中国移动"
                    elseif string.find(operator_raw, "联通") then
                        operator = "中国联通"
                    elseif string.find(operator_raw, "电信") then
                        operator = "中国电信"
                    elseif string.find(operator_raw, "广电") then
                        operator = "中国广电"
                    end
                end
                
                show_result(location, operator, area_code, zip_code)
            else
                local err_msg = (result and result.msg) or "查询失败"
                show_error(err_msg)
            end
        else
            show_error("网络请求失败，请检查网络")
        end
    end)
end

-- 查询按钮回调
local function on_query_click()
    local phone = phone_input and phone_input:get_text() or ""
    local clean_phone = phone:gsub("%D", "")
    if #clean_phone == 11 then
        query_phone(clean_phone)
    else
        show_error("请输入11位数字手机号")
    end
end

-- 创建UI
local function create_ui()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xeef2f7,
        scrollable = false
    })
    
    -- 创建数字键盘
    phone_keyboard = airui.keyboard({
        mode = "numeric",
        auto_hide = true,
        preview = true,
        preview_height = 32,
        x = 0,
        w = 480,
        h = 160,
        on_commit = function(self)
            self:hide()
        end
    })
    
    -- 头部卡片
    local header = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 80,
        color = 0x0d4769,
        radius = 0
    })
    
    -- 头部主标题
    airui.label({
        parent = header,
        x = 20,
        y = 20,
        w = 440,
        h = 40,
        text = "手机号码归属地查询",
        font_size = 26,
        color = 0xffffff,
        bold = true,
        align = airui.TEXT_ALIGN_CENTER,
        valign = airui.TEXT_VALIGN_CENTER
    })
    
    -- 输入卡片背景
    local input_card = airui.container({
        parent = main_container,
        x = 20,
        y = 150,
        w = 440,
        h = 160,
        color = 0xffffff,
        radius = 24,
        border = { width = 1, color = 0xdce5ef }
    })
    
    -- 输入框标签
    local input_label = airui.label({
        parent = input_card,
        x = 20,
        y = 15,
        w = 100,
        h = 20,
        text = "手机号码",
        font_size = 14,
        color = 0x1a4c6e,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 输入框
    phone_input = airui.textarea({
        parent = input_card,
        x = 20,
        y = 38,
        w = 400,
        h = 48,
        text = "",
        max_len = 11,
        font_size = 18,
        placeholder = "请输入11位手机号码",
        keyboard = phone_keyboard,
        on_click = function()
            if phone_keyboard and phone_keyboard.show then
                phone_keyboard:show()
            end
        end
    })
    
    -- 查询按钮（自定义组合方式）
    local query_btn_container = airui.container({
        parent = input_card,
        x = 100,
        y = 95,
        w = 240,
        h = 44,
        color = 0xff9540,
        radius = 22,
        on_click = on_query_click
    })
    -- 查询图标（使用系统内置SYMBOL_CALL）
    airui.label({
        parent = query_btn_container,
        x = 70,
        y = 5,
        w = 32,
        h = 32,
        text = airui.SYMBOL_CALL,
        font_size = 24,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    -- 查询按钮文字
    airui.label({
        parent = query_btn_container,
        x = 105,
        y = 13,
        w = 130,
        h = 20,
        text = "查询归属地",
        font_size = 16,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 结果显示卡片
    local result_card = airui.container({
        parent = main_container,
        x = 20,
        y = 330,
        w = 440,
        h = 230,
        color = 0xfef9ef,
        radius = 24,
        border = { width = 2, color = 0xff9f4a }
    })
    
    -- 结果标题
    local result_title = airui.label({
        parent = result_card,
        x = 20,
        y = 15,
        w = 150,
        h = 20,
        text = "归属地信息",
        font_size = 14,
        color = 0x6d8eaa,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 归属地内容
    location_label = airui.label({
        parent = result_card,
        x = 20,
        y = 45,
        w = 400,
        h = 45,
        text = "实时查询， 精确到城市",
        font_size = 24,
        color = 0x1b4d6e,
        bold = true,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 运营商行
    local operator_title = airui.label({
        parent = result_card,
        x = 20,
        y = 100,
        w = 80,
        h = 20,
        text = "运营商",
        font_size = 14,
        color = 0x5f7f9a,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    operator_label = airui.label({
        parent = result_card,
        x = 120,
        y = 100,
        w = 300,
        h = 20,
        text = " ",
        font_size = 15,
        color = 0x2c5a7a,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 区号行
    local area_code_title = airui.label({
        parent = result_card,
        x = 20,
        y = 135,
        w = 80,
        h = 20,
        text = "区号",
        font_size = 14,
        color = 0x5f7f9a,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    area_code_label = airui.label({
        parent = result_card,
        x = 120,
        y = 135,
        w = 300,
        h = 20,
        text = " ",
        font_size = 15,
        color = 0x2c5a7a,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 邮编行
    local zip_code_title = airui.label({
        parent = result_card,
        x = 20,
        y = 170,
        w = 80,
        h = 20,
        text = "邮编",
        font_size = 14,
        color = 0x5f7f9a,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    zip_code_label = airui.label({
        parent = result_card,
        x = 120,
        y = 170,
        w = 300,
        h = 20,
        text = " ",
        font_size = 15,
        color = 0x2c5a7a,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 错误/提示信息
    error_label = airui.label({
        parent = result_card,
        x = 20,
        y = 205,
        w = 400,
        h = 20,
        text = "",
        font_size = 12,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 底部按钮区域
    local btn_bar = airui.container({
        parent = main_container,
        x = 20,
        y = 680,
        w = 440,
        h = 55,
        color = 0xeef2f7
    })
    
    -- 重置按钮（自定义组合方式）
    local reset_btn_container = airui.container({
        parent = btn_bar,
        x = 10,
        y = 5,
        w = 200,
        h = 45,
        color = 0x6b8e9f,
        radius = 22,
        on_click = reset_form
    })
    -- 重置图标（使用系统已存在的set.png）
    airui.image({
        parent = reset_btn_container,
        x = 60,
        y = 6,
        w = 32,
        h = 32,
        src = "/luadb/set.png"
    })
    -- 重置按钮文字
    airui.label({
        parent = reset_btn_container,
        x = 95,
        y = 13,
        w = 100,
        h = 20,
        text = "重置",
        font_size = 15,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 退出按钮（自定义组合方式）
    local exit_btn_container = airui.container({
        parent = btn_bar,
        x = 230,
        y = 5,
        w = 200,
        h = 45,
        color = 0xc74a36,
        radius = 22,
        on_click = function()
            if win_id then
                exwin.close(win_id)
            end
        end
    })
    -- 退出图标（使用airui自带的SYMBOL_POWER）
    airui.label({
        parent = exit_btn_container,
        x = 60,
        y = 5,
        w = 32,
        h = 32,
        text = airui.SYMBOL_POWER,
        font_size = 24,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    -- 退出按钮文字
    airui.label({
        parent = exit_btn_container,
        x = 95,
        y = 13,
        w = 100,
        h = 20,
        text = "退出",
        font_size = 15,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 默认提示
    location_label:set_text("实时查询， 精确到城市")
    clear_message()
end

-- 窗口生命周期
local function on_create()
    create_ui()
    print("PhoneLookup 已启动 | AirUI版本 | 480x800")
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function on_get_focus()
end

local function on_lose_focus()
end

-- 打开窗口
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_PHONEINFO_WIN", open_handler)

return {
    query_phone = query_phone,
    reset_form = reset_form
}