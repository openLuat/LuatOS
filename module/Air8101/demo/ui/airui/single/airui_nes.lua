--[[
@module  nes_page
@summary NES模拟器组件演示
@version 1.0.0
@date    2026.10.12
@author  江访
@usage
本文件演示airui.nes组件的用法，包括创建、按键控制和销毁重建。
需要固件启用NES支持，ROM文件放到/luadb/目录，文件名为game.nes。
]]

-- NES组件对象
local nes_widget

-- 创建NES模拟器组件
local function create_nes()
    nes_widget = airui.nes({
        rom = "/luadb/game.nes",   -- NES ROM文件路径
        scale = 1,                 -- 画面缩放倍数，1倍时画面256*240
        x = 272, y = 8,            -- 组件位置
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

local function ui_main()
    -- ========== 创建 NES 模拟器组件 ==========
    create_nes()

    -- ========== 方向键 ==========
    airui.button({
        text = "上",
        x = 60, y = 265, w = 70, h = 45,
        size = 16,
        on_pressed = function() nes_key(airui.NES_KEY_UP, 1) end,
        on_released = function() nes_key(airui.NES_KEY_UP, 0) end,
    })
    airui.button({
        text = "左",
        x = 10, y = 315, w = 70, h = 45,
        size = 16,
        on_pressed = function() nes_key(airui.NES_KEY_LEFT, 1) end,
        on_released = function() nes_key(airui.NES_KEY_LEFT, 0) end,
    })
    airui.button({
        text = "右",
        x = 110, y = 315, w = 70, h = 45,
        size = 16,
        on_pressed = function() nes_key(airui.NES_KEY_RIGHT, 1) end,
        on_released = function() nes_key(airui.NES_KEY_RIGHT, 0) end,
    })
    airui.button({
        text = "下",
        x = 60, y = 365, w = 70, h = 45,
        size = 16,
        on_pressed = function() nes_key(airui.NES_KEY_DOWN, 1) end,
        on_released = function() nes_key(airui.NES_KEY_DOWN, 0) end,
    })

    -- ========== 功能键 ==========
    airui.button({
        text = "SELECT",
        x = 280, y = 265, w = 110, h = 45,
        size = 16,
        on_pressed = function() nes_key(airui.NES_KEY_SELECT, 1) end,
        on_released = function() nes_key(airui.NES_KEY_SELECT, 0) end,
    })
    airui.button({
        text = "START",
        x = 410, y = 265, w = 110, h = 45,
        size = 16,
        on_pressed = function() nes_key(airui.NES_KEY_START, 1) end,
        on_released = function() nes_key(airui.NES_KEY_START, 0) end,
    })

    -- ========== 动作键 ==========
    airui.button({
        text = "B",
        x = 600, y = 330, w = 70, h = 60,
        size = 20,
        on_pressed = function() nes_key(airui.NES_KEY_B, 1) end,
        on_released = function() nes_key(airui.NES_KEY_B, 0) end,
    })
    airui.button({
        text = "A",
        x = 690, y = 315, w = 70, h = 60,
        size = 20,
        on_pressed = function() nes_key(airui.NES_KEY_A, 1) end,
        on_released = function() nes_key(airui.NES_KEY_A, 0) end,
    })

    -- ========== 组件生命周期 ==========
    -- 销毁NES组件
    airui.button({
        text = "销毁组件",
        x = 280, y = 370, w = 110, h = 45,
        size = 14,
        on_click = function()
            destroy_nes()
        end
    })

    -- 重建NES组件，演示先销毁再创建的切换流程
    airui.button({
        text = "重建组件",
        x = 410, y = 370, w = 110, h = 45,
        size = 14,
        on_click = function()
            destroy_nes()
            create_nes()
        end
    })

    -- 底部提示
    airui.label({
        text = "提示: ROM文件放到/luadb/game.nes，按下按键开始游戏操作",
        x = 10, y = 440, w = 780, h = 25,
        size = 14,
    })
end

sys.taskInit(ui_main)
