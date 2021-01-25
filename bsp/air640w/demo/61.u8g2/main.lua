--- 模块功能：u8g2demo
-- @module u8g2
-- @author Dozingfiretruck
-- @release 2021.01.25

local sys = require("sys")

--[[ 注意，使用u8g2需将 LuatOS\bsp\air640w\rtt\applications\dfs_lfs2.c
第78处修改为小文件系统，因为全汉字字库占用极大空间，否则将无法使用 ]]

-- 项目信息,预留
VERSION = "1.0.0"
PRODUCT_KEY = "1234567890"

-- 日志TAG, 非必须
local TAG = "main"
local last_temp_data = "0"

----------------------------------------------------------------------
-- 对接SSD1306, 当前显示一行就好了
function display_str(str,x,y)
    u8g2.SetFont("u8g2_font_ncenB08_tr")
    u8g2.ClearBuffer()
    u8g2.DrawUTF8(str, x, y)
    u8g2.SendBuffer()
end

function display_chinese(str,x,y)
    u8g2.SetFont("u8g2_font_wqy12_t_gb2312")
    u8g2.ClearBuffer()
    u8g2.DrawUTF8(str, x, y)
    u8g2.SendBuffer()
end

-- 初始化显示屏
log.info(TAG, "init ssd1306")
u8g2.begin("ssd1306")
u8g2.SetFontMode(1)
display_chinese("启动中",1,10)

-- 联网主流程
sys.taskInit(function()
    log.info("u8g2.getWidth",u8g2.GetDisplayWidth())
    log.info("u8g2.getHeight",u8g2.GetDisplayHeight())
    u8g2.DrawLine(0,60,128,60)
    u8g2.DrawCircle(60,30,8,15)
    u8g2.DrawDisc(90,30,8,15)
    u8g2.DrawEllipse(60,50,4,6,15)
    u8g2.DrawFilledEllipse(90,50,4,6,15)

    u8g2.DrawBox(10,25,4,5)
    u8g2.DrawFrame(10,40,4,5)
    u8g2.DrawRBox(20,25,4,6,2)
    u8g2.DrawRFrame(40,40,4,6,2)

    u8g2.SetFont("u8g2_font_unifont_t_symbols")
    u8g2.DrawGlyph( 112, 56, 0x2603 )

    u8g2.DrawTriangle(90,5, 27,12, 5,32)

    u8g2.SetBitmapMode(0)

    u8g2.SendBuffer()
    --u8g2.clear()
    while true do
        sys.wait(500)
    end
end)

-- TODO: 用户按钮(PB7), 用于清除配网信息,重新airkiss

-- TODO: 联网更新脚本和底层(也许)

-- 主循环, 必须加
sys.run()
