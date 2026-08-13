local st6201 = require "lcd_st6201_cust_drv"


local function lcd_app_task_func()

    local result = st6201.init({
        port = lcd.HWID_0,
        pin_pwr = 1,
        direction = 0,
        bus_speed = 80 * 1000 * 1000,
        rb_swap = true,
    })
    if not result then
        log.error("main", "ST6201 init failed")
        return
    end

    if airui then
            -- 初始化AirUI
            local width, height = lcd.getSize()
            local result = airui.init(width, height)
            if not result then
                log.error("airui", "init failed")
                return result
            end

            -- 加载中文字体
            if rtos.bsp() ~= "Air8101" then
                -- PC端/Air8000/780EHM 从14号固件/114号固件中加载hzfont字库，从而支持12-255~号中文显示
                airui.font_load({
                    type = "hzfont",   -- 字体类型，可选 "hzfont" 或 "bin"
                    path = nil,        -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
                    -- path = "/luadb/NotoSansSC_subset.ttf", -- 展示NotoSansSC_subset自定义字体
                    size = 20,         -- 字体大小，默认 16
                    cache_size = 1048, -- 缓存字数大小，默认 2048
                    antialias = 1,     -- 抗锯齿等级1-3，默认 1
                })
            elseif rtos.bsp() == "PC" then
                -- PC模拟器使用外部TTF字体文件（与lua脚本同目录），完整展示字体特性
                airui.font_load({
                    type = "hzfont",
                    path = nil,        -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
                    -- path = "/luadb/NotoSansSC_subset.ttf", -- 展示NotoSansSC_subset自定义字体
                    size = 20,
                    cache_size = 2048,
                    antialias = 3, -- 高抗锯齿等级，展示字体边缘平滑特性
                    global = true
                })
            end

            -- 查询当前固件内AirUI核心库版本
            local version_result = airui.version()

            -- 打印查询结果
            log.info("airui", "version -> " .. version_result)
        else
            log.warn("lcd_st6201_cust_drv", "AirUI not available, skip AirUI init")
        end

    log.info("lcd_app", "Air8301 网关界面开始执行")

    -- 根容器：浅灰背景
    local root = airui.container({ x = 0, y = 0, w = 480, h = 272, color = 0xECEFF1, })

    -- 顶部标题栏
    airui.container({ parent = root, x = 0, y = 0, w = 480, h = 48, color = 0x1A5276 })

    -- 标题
    airui.label({ parent = root, text = "Air8301 网关", x = 15, y = 12, w = 200, h = 24, color = 0xFFFFFF, font_size = 22, })

    -- 时间
    airui.label({ parent = root, text = "08:00", x = 380, y = 12, w = 85, h = 24, color = 0xFFFFFF, font_size = 22, align = "right", })

    -- 网络状态 卡片（左上）
    airui.container({ parent = root, x = 10, y = 56, w = 220, h = 58, color = 0x4CAF50, radius = 6, })
    airui.label({ parent = root, text = "网络状态", x = 10, y = 70, w = 220, h = 30, color = 0xFFFFFF, font_size = 20, align = "center", })

    -- 信号/图表 卡片（右上）
    airui.container({ parent = root, x = 250, y = 56, w = 220, h = 58, color = 0x2196F3, radius = 6,    })
    -- 模拟几条信号柱状线
    for i = 0, 4 do
        airui.container({ parent = root, x = 300 + i * 18, y = 78 - i * 4, w = 10, h = 16 + i * 6, color = 0xFFFFFF, radius = 2, })
    end

    -- 以太网 卡片（左中）
    airui.container({ parent = root, x = 10, y = 122, w = 220, h = 58, color = 0xFF9800, radius = 6,    })
    -- 状态指示点
    airui.container({ parent = root, x = 62, y = 144, w = 8, h = 8, color = 0xFFFFFF, radius = 4,    })
    airui.label({ parent = root, text = "以太网", x = 10, y = 136, w = 220, h = 30, color = 0xFFFFFF, font_size = 20, align = "center",    })

    -- RS485 卡片（右中）
    airui.container({ parent = root, x = 250, y = 122, w = 220, h = 58, color = 0x795548, radius = 6,    })
    airui.label({ parent = root, text = "RS485", x = 250, y = 136, w = 220, h = 30, color = 0xFFFFFF, font_size = 20, align = "center",    })

    -- RS232 卡片（左下）
    airui.container({ parent = root, x = 10, y = 188, w = 220, h = 58,  color = 0x009688, radius = 6,    })
    airui.label({ parent = root, text = "RS232", x = 10, y = 202, w = 220, h = 30, color = 0xFFFFFF, font_size = 20, align = "center",    })

    -- DI状态 卡片（右下）
    airui.container({ parent = root, x = 250, y = 188, w = 220, h = 58,  color = 0x666666, radius = 6,    })
    airui.label({ parent = root, text = "DI状态", x = 250, y = 202, w = 220, h = 30, color = 0xFFFFFF, font_size = 20, align = "center",    })

    log.info("airui_app", "Air8301 网关界面创建完成")

    while true do
        sys.wait(1000)
    end
end

sys.taskInit(lcd_app_task_func)
