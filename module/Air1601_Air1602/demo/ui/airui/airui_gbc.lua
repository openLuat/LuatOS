--[[
@module  airui_gbc
@summary GBC模拟器组件演示页面
@version 1.0.0
@date    2026.10.12
@author  江访
@usage
本文件是GBC模拟器组件的演示页面，演示airui.gbc组件的用法，包括创建、按键控制
和销毁重建。需要固件启用GBC支持，ROM文件放到/luadb/目录，文件名为game.gbc。
]]

local airui_gbc = {}

-- 页面UI元素
local main_container = nil
local gbc_widget = nil

-- 创建GBC模拟器组件
local function create_gbc()
    gbc_widget = airui.gbc({
        rom = "/luadb/game.gbc",   -- GBC ROM文件路径
        scale = 2,                 -- 画面缩放倍数，2倍时画面320*288
        x = 352, y = 70,           -- 组件位置
    })
    if not gbc_widget then
        log.error("gbc", "创建 GBC 组件失败，固件可能未启用 GBC 支持")
        return
    end
    log.info("airui", "gbc created")
end

-- 销毁GBC模拟器组件
local function destroy_gbc()
    if gbc_widget then
        gbc_widget:destroy()
        gbc_widget = nil
        log.info("airui", "gbc destroyed")
    end
end

-- 发送GBC按键事件
local function gbc_key(key_code, pressed)
    if gbc_widget then
        gbc_widget:key(key_code, pressed)
    end
end

-- 创建UI
function airui_gbc.create_ui()
    -- 创建主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 1024,
        h = 600,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 1024,
        h = 60,
        color = 0x9C27B0,
    })

    airui.label({
        parent = title_bar,
        text = "GBC模拟器组件演示",
        x = 20,
        y = 15,
        w = 300,
        h = 30,
        size = 20,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 900,
        y = 15,
        w = 100,
        h = 35,
        text = "返回",
        size = 16,
        on_click = function()
            go_back()
        end
    })

    -- ========== 创建 GBC 模拟器组件 ==========
    create_gbc()

    -- ========== 方向键 ==========
    airui.button({
        parent = main_container,
        text = "上",
        x = 80, y = 380, w = 90, h = 50,
        size = 18,
        on_pressed = function() gbc_key(airui.GBC_KEY_UP, 1) end,
        on_released = function() gbc_key(airui.GBC_KEY_UP, 0) end,
    })
    airui.button({
        parent = main_container,
        text = "左",
        x = 15, y = 440, w = 90, h = 50,
        size = 18,
        on_pressed = function() gbc_key(airui.GBC_KEY_LEFT, 1) end,
        on_released = function() gbc_key(airui.GBC_KEY_LEFT, 0) end,
    })
    airui.button({
        parent = main_container,
        text = "右",
        x = 145, y = 440, w = 90, h = 50,
        size = 18,
        on_pressed = function() gbc_key(airui.GBC_KEY_RIGHT, 1) end,
        on_released = function() gbc_key(airui.GBC_KEY_RIGHT, 0) end,
    })
    airui.button({
        parent = main_container,
        text = "下",
        x = 80, y = 500, w = 90, h = 50,
        size = 18,
        on_pressed = function() gbc_key(airui.GBC_KEY_DOWN, 1) end,
        on_released = function() gbc_key(airui.GBC_KEY_DOWN, 0) end,
    })

    -- ========== 功能键 ==========
    airui.button({
        parent = main_container,
        text = "SELECT",
        x = 390, y = 380, w = 150, h = 50,
        size = 18,
        on_pressed = function() gbc_key(airui.GBC_KEY_SELECT, 1) end,
        on_released = function() gbc_key(airui.GBC_KEY_SELECT, 0) end,
    })
    airui.button({
        parent = main_container,
        text = "START",
        x = 560, y = 380, w = 150, h = 50,
        size = 18,
        on_pressed = function() gbc_key(airui.GBC_KEY_START, 1) end,
        on_released = function() gbc_key(airui.GBC_KEY_START, 0) end,
    })

    -- ========== 动作键 ==========
    airui.button({
        parent = main_container,
        text = "B",
        x = 760, y = 450, w = 90, h = 75,
        size = 22,
        on_pressed = function() gbc_key(airui.GBC_KEY_B, 1) end,
        on_released = function() gbc_key(airui.GBC_KEY_B, 0) end,
    })
    airui.button({
        parent = main_container,
        text = "A",
        x = 870, y = 430, w = 90, h = 75,
        size = 22,
        on_pressed = function() gbc_key(airui.GBC_KEY_A, 1) end,
        on_released = function() gbc_key(airui.GBC_KEY_A, 0) end,
    })

    -- ========== 组件生命周期 ==========
    -- 销毁GBC组件
    airui.button({
        parent = main_container,
        text = "销毁组件",
        x = 390, y = 500, w = 150, h = 50,
        size = 16,
        on_click = function()
            destroy_gbc()
        end
    })

    -- 重建GBC组件，演示先销毁再创建的切换流程
    airui.button({
        parent = main_container,
        text = "重建组件",
        x = 560, y = 500, w = 150, h = 50,
        size = 16,
        on_click = function()
            destroy_gbc()
            create_gbc()
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 需要固件启用GBC支持，ROM文件放到/luadb/game.gbc，按下按键开始游戏操作",
        x = 20,
        y = 560,
        w = 800,
        h = 25,
        size = 14,
    })
end

-- 初始化页面
function airui_gbc.init(params)
    airui_gbc.create_ui()
end

-- 清理页面
function airui_gbc.cleanup()
    destroy_gbc()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return airui_gbc
