--[[
@module  airui_nes
@summary NES模拟器组件演示页面
@version 1.0.0
@date    2026.10.12
@author  江访
@usage
本文件是NES模拟器组件的演示页面，演示airui.nes组件的用法，包括创建、按键控制
和销毁重建。需要固件启用NES支持，ROM文件放到/luadb/目录，文件名为game.nes。
]]

local airui_nes = {}

-- 页面UI元素
local main_container = nil
local nes_widget = nil

-- 创建NES模拟器组件
local function create_nes()
    nes_widget = airui.nes({
        rom = "/luadb/game.nes",   -- NES ROM文件路径
        scale = 1,                 -- 画面缩放倍数，1倍时画面256*240
        x = 384, y = 70,           -- 组件位置
    })
    if not nes_widget then
        log.error("nes", "创建 NES 组件失败，固件可能未启用 NES 支持")
        return
    end
    log.info("airui", "nes created")
end

-- 销毁NES模拟器组件
local function destroy_nes()
    if nes_widget then
        nes_widget:destroy()
        nes_widget = nil
        log.info("airui", "nes destroyed")
    end
end

-- 发送NES按键事件
local function nes_key(key_code, pressed)
    if nes_widget then
        nes_widget:key(key_code, pressed)
    end
end

-- 创建UI
function airui_nes.create_ui()
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
        color = 0x4CAF50,
    })

    airui.label({
        parent = title_bar,
        text = "NES模拟器组件演示",
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

    -- ========== 创建 NES 模拟器组件 ==========
    create_nes()

    -- ========== 方向键 ==========
    airui.button({
        parent = main_container,
        text = "上",
        x = 80, y = 330, w = 90, h = 55,
        size = 18,
        on_pressed = function() nes_key(airui.NES_KEY_UP, 1) end,
        on_released = function() nes_key(airui.NES_KEY_UP, 0) end,
    })
    airui.button({
        parent = main_container,
        text = "左",
        x = 15, y = 395, w = 90, h = 55,
        size = 18,
        on_pressed = function() nes_key(airui.NES_KEY_LEFT, 1) end,
        on_released = function() nes_key(airui.NES_KEY_LEFT, 0) end,
    })
    airui.button({
        parent = main_container,
        text = "右",
        x = 145, y = 395, w = 90, h = 55,
        size = 18,
        on_pressed = function() nes_key(airui.NES_KEY_RIGHT, 1) end,
        on_released = function() nes_key(airui.NES_KEY_RIGHT, 0) end,
    })
    airui.button({
        parent = main_container,
        text = "下",
        x = 80, y = 460, w = 90, h = 55,
        size = 18,
        on_pressed = function() nes_key(airui.NES_KEY_DOWN, 1) end,
        on_released = function() nes_key(airui.NES_KEY_DOWN, 0) end,
    })

    -- ========== 功能键 ==========
    airui.button({
        parent = main_container,
        text = "SELECT",
        x = 390, y = 330, w = 150, h = 55,
        size = 18,
        on_pressed = function() nes_key(airui.NES_KEY_SELECT, 1) end,
        on_released = function() nes_key(airui.NES_KEY_SELECT, 0) end,
    })
    airui.button({
        parent = main_container,
        text = "START",
        x = 560, y = 330, w = 150, h = 55,
        size = 18,
        on_pressed = function() nes_key(airui.NES_KEY_START, 1) end,
        on_released = function() nes_key(airui.NES_KEY_START, 0) end,
    })

    -- ========== 动作键 ==========
    airui.button({
        parent = main_container,
        text = "B",
        x = 760, y = 400, w = 90, h = 80,
        size = 22,
        on_pressed = function() nes_key(airui.NES_KEY_B, 1) end,
        on_released = function() nes_key(airui.NES_KEY_B, 0) end,
    })
    airui.button({
        parent = main_container,
        text = "A",
        x = 870, y = 380, w = 90, h = 80,
        size = 22,
        on_pressed = function() nes_key(airui.NES_KEY_A, 1) end,
        on_released = function() nes_key(airui.NES_KEY_A, 0) end,
    })

    -- ========== 组件生命周期 ==========
    -- 销毁NES组件
    airui.button({
        parent = main_container,
        text = "销毁组件",
        x = 390, y = 460, w = 150, h = 55,
        size = 16,
        on_click = function()
            destroy_nes()
        end
    })

    -- 重建NES组件，演示先销毁再创建的切换流程
    airui.button({
        parent = main_container,
        text = "重建组件",
        x = 560, y = 460, w = 150, h = 55,
        size = 16,
        on_click = function()
            destroy_nes()
            create_nes()
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 需要固件启用NES支持，ROM文件放到/luadb/game.nes，按下按键开始游戏操作",
        x = 20,
        y = 560,
        w = 800,
        h = 25,
        size = 14,
    })
end

-- 初始化页面
function airui_nes.init(params)
    airui_nes.create_ui()
end

-- 清理页面
function airui_nes.cleanup()
    destroy_nes()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return airui_nes
