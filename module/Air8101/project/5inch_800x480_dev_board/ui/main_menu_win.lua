--[[
1、窗口显示布局：上40像素为状态栏，中400像素为主菜单图标，下40像素为主菜单分页x/y提示
2、主菜单图标支持多页
   (1) 每页8个图标，图标大小120*120
   (2) 分2排显示，每页4个图标
   (3) 每个图标的左右空白间隔为 (800-4*120)/5 = 64
   (4) 每个图标的上下空白间隔为 (400-2*120)/3 = 53
]]



-- 加载显示屏驱动功能模块
local lcd_device = require "lcd_device"
-- 加载窗口管理功能模块
local lib_win = require "lib_win"

-- 主菜单每个图标的宽和高
local MENU_IMG_WIDTH,MENU_IMG_HEIGHT = 120,120
-- 主菜单显示区域的起始y轴坐标
local MENU_IMG_Y_OFFSET = 40
-- 主菜单显示区域的高度
local MENU_IMG_DISPLAY_HEIGHT = 400
-- 主菜单显示区域内，每页显示的行数
local MENU_IMG_LINE_CNT = 2
-- 每行显示的主菜单个数
local MENU_IMG_CNT_PER_LINE = 4
-- 每个主菜单图标的左右空白间隔
local MENU_IMG_X_SPACE = math.floor((lcd_device.width-MENU_IMG_CNT_PER_LINE*MENU_IMG_WIDTH)/(MENU_IMG_CNT_PER_LINE+1))
-- 每行第一个主菜单图标显示的默认x轴坐标
local MENU_IMG_DEFAULT_X_OFFSET = MENU_IMG_X_SPACE
-- 每个主菜单图标的上下空白间隔
local MENU_IMG_Y_SPACE = math.floor((MENU_IMG_DISPLAY_HEIGHT-MENU_IMG_LINE_CNT*MENU_IMG_HEIGHT)/(MENU_IMG_LINE_CNT+1))
-- 第一行主菜单图标显示的默认y轴坐标
local MENU_IMG_DEFAULT_Y_OFFSET = MENU_IMG_Y_OFFSET+MENU_IMG_Y_SPACE
-- 菜单标题字体大小，不要超过36
local MENU_IMG_TITLE_FONT_SIZE = 26
-- 底部页数字体大小，不要超过40
local BOTTOM_PAGE_FONT_SIZE = 40

-- 当前页为主菜单的第几页
local cur_page = 1
-- 每行显示的图标起始索引（触摸滑动时有可能会发生改变）
local disp_img_index = 1
-- 每行显示的图标起始x轴坐标（触摸滑动时有可能会发生改变）
local disp_img_x_offset = MENU_IMG_DEFAULT_X_OFFSET

-- 每行第一个主菜单图标显示的动态x轴坐标（触摸滑动时会发生改变）
-- local dyn_x_offset = MENU_IMG_DEFAULT_X_OFFSET
-- 每次手指开始移动，检测到的tp.EVENT_MOVE的X坐标
-- 当检测到tp.EVENT_UP，此值赋值为-1
local move_last_x = -1;
-- 触摸按下和触摸弹起之间是否存在有效移动
local valid_move

-- 每轮移动前和移动后，最左边一列显示的图标索引
-- 用来判断本轮移动是左移还是右移
local old_index, new_index



-- -- 当前页每行显示的图标数量（触摸滑动时有可能会发生改变）
-- local cur_page_disp_img_cnt_per_line = MENU_IMG_CNT_PER_LINE
-- -- 当前页每行显示的图标起始x轴坐标（触摸滑动时有可能会发生改变）
-- local cur_page_disp_img_x_offset = MENU_IMG_DEFAULT_X_OFFSET
-- -- 当前页每行显示的图标起始索引（触摸滑动时有可能会发生改变）
-- local cur_page_disp_img_index = 1



-- 主菜单信息表
local image_table =
{
    {
        {img="/luadb/P1-L1-1.jpg", title= "1.1", proc_func=function() log.info("page1-line1-app1") end},
        {img="/luadb/P1-L2-1.jpg", title= "1.2", proc_func=function() log.info("page1-line2-app1") end},
    },
    {
        {img="/luadb/P1-L1-2.jpg", title= "2.1", proc_func=function() log.info("page1-line1-app2") end},
        {img="/luadb/P1-L2-2.jpg", title= "2.2", proc_func=function() log.info("page1-line2-app2") end},
    },
    {
        {img="/luadb/P1-L1-3.jpg", title= "3.1", proc_func=function() log.info("page1-line1-app3") end},
        {img="/luadb/P1-L2-3.jpg", title= "3.2", proc_func=function() log.info("page1-line2-app3") end},
    },
    {
        {img="/luadb/P1-L1-4.jpg", title= "4.1", proc_func=function() log.info("page1-line1-app4") end},
        {img="/luadb/P1-L2-4.jpg", title= "4.2", proc_func=function() log.info("page1-line2-app4") end},
    },
    {
        {img="/luadb/P2-L1-1.jpg", title= "5.1", proc_func=function() log.info("page2-line1-app1") end},
        {img="/luadb/P2-L2-1.jpg", title= "5.2", proc_func=function() log.info("page2-line2-app1") end},
    },
    {
        {img="/luadb/P2-L1-2.jpg", title= "6.1", proc_func=function() log.info("page2-line1-app2") end},
        {img="/luadb/P2-L2-2.jpg", title= "6.2", proc_func=function() log.info("page2-line2-app2") end},
    },
    {
        {img="/luadb/P2-L1-3.jpg", title= "7.1", proc_func=function() log.info("page2-line1-app3") end},
        {img="/luadb/P2-L2-3.jpg", title= "7.2", proc_func=function() log.info("page2-line2-app3") end},
    },
    {
        {img="/luadb/P2-L1-4.jpg", title= "8.1", proc_func=function() log.info("page2-line1-app4") end},
        {img="/luadb/P2-L2-4.jpg", title= "8.2", proc_func=function() log.info("page2-line2-app4") end},
    },

}

-- 刷新处理函数
local function refresh_proc_func()

    lcd.setColor(lcd_device.bg_color, lcd_device.fg_color)

    --清屏
    lcd.clear()

    -- 显示主菜单图标
    -- for line=1, #(image_table[cur_page]) do
    --     for i=1,#(image_table[cur_page][line]) do
    --         lcd.showImage(dyn_x_offset+(i-1)*(MENU_IMG_X_SPACE+MENU_IMG_WIDTH),
    --             MENU_IMG_DEFAULT_Y_OFFSET+(line-1)*(MENU_IMG_Y_SPACE+MENU_IMG_HEIGHT),
    --             image_table[cur_page][line][i].img)
    --     end
    -- end

    for i=disp_img_index,disp_img_index+MENU_IMG_CNT_PER_LINE-1 do
        lcd.showImage(disp_img_x_offset+(i-disp_img_index)*(MENU_IMG_X_SPACE+MENU_IMG_WIDTH),
            MENU_IMG_DEFAULT_Y_OFFSET+(1-1)*(MENU_IMG_Y_SPACE+MENU_IMG_HEIGHT),
            image_table[i][1].img)

        lcd.drawGtfontUtf8(image_table[i][1].title,
            MENU_IMG_TITLE_FONT_SIZE,
            disp_img_x_offset+(i-disp_img_index)*(MENU_IMG_X_SPACE+MENU_IMG_WIDTH)+math.floor((MENU_IMG_WIDTH-image_table[i][1].title:len()*MENU_IMG_TITLE_FONT_SIZE/2)/2),
            MENU_IMG_DEFAULT_Y_OFFSET+(1-1)*(MENU_IMG_Y_SPACE+MENU_IMG_HEIGHT)+MENU_IMG_HEIGHT)
        

        lcd.showImage(disp_img_x_offset+(i-disp_img_index)*(MENU_IMG_X_SPACE+MENU_IMG_WIDTH),
            MENU_IMG_DEFAULT_Y_OFFSET+(2-1)*(MENU_IMG_Y_SPACE+MENU_IMG_HEIGHT),
            image_table[i][2].img)

        lcd.drawGtfontUtf8(image_table[i][2].title,
            MENU_IMG_TITLE_FONT_SIZE,
            disp_img_x_offset+(i-disp_img_index)*(MENU_IMG_X_SPACE+MENU_IMG_WIDTH)+math.floor((MENU_IMG_WIDTH-image_table[i][2].title:len()*MENU_IMG_TITLE_FONT_SIZE/2)/2),
            MENU_IMG_DEFAULT_Y_OFFSET+(2-1)*(MENU_IMG_Y_SPACE+MENU_IMG_HEIGHT)+MENU_IMG_HEIGHT)

        
        
    end

    -- 显示当前页菜单图标
    -- for line=1, #(image_table[cur_page]) do
    --     for i=cur_page_disp_img_index,cur_page_disp_img_cnt_per_line do
    --         lcd.showImage(cur_page_disp_img_x_offset+(i-cur_page_disp_img_index)*(MENU_IMG_X_SPACE+MENU_IMG_WIDTH),
    --             MENU_IMG_DEFAULT_Y_OFFSET+(line-1)*(MENU_IMG_Y_SPACE+MENU_IMG_HEIGHT),
    --             image_table[cur_page][line][i].img)
    --     end
    -- end

    -- 显示当前第几页
    local str = cur_page.."/"..math.floor(#image_table/MENU_IMG_CNT_PER_LINE)
    lcd.drawGtfontUtf8(str,
        BOTTOM_PAGE_FONT_SIZE,
        lcd_device.width/2-math.floor(str:len()*BOTTOM_PAGE_FONT_SIZE/2/2),
        MENU_IMG_Y_OFFSET+MENU_IMG_DISPLAY_HEIGHT+math.floor((lcd_device.height-MENU_IMG_Y_OFFSET-MENU_IMG_DISPLAY_HEIGHT-BOTTOM_PAGE_FONT_SIZE)/2))

    --刷屏，将缓冲区中的数据显示到lcd上
    lcd.flush()
end

-- 触摸处理函数
local function touch_proc_func(tp_data)
    -- log.info("main_menu_win.touch_proc_func")

    -- 每次移动后，临时记录每行第一个图标应该显示的x轴坐标
    local new_x_offset

    -- 每次移动的像素数量，左移为负，右移为正
    local move_pixels = 0

    -- 每次移动后，要显示的起始图标的列索引
    local temp_index

    if tp_data[1].event == tp.EVENT_DOWN then
        valid_move = false
    end

    -- 当前移动过程中第一次检测到MOVE事件
    -- 初始化赋值move_last_x
    if move_last_x==-1 and tp_data[1].event == tp.EVENT_MOVE then
        move_last_x = tp_data[1].x
        old_index = disp_img_index
    end

    if tp_data[1].event == tp.EVENT_UP then
        -- 当前移动过程中检测到UP事件
        -- 结束本次移动过程
        if move_last_x~=-1 then
            move_last_x = -1
            new_index = disp_img_index
        end

        if valid_move then
            valid_move = false
            -- 右移
            if new_index > old_index then
                cur_page = cur_page+1
            -- 左移
            elseif new_index < old_index then
                cur_page = cur_page-1
            end
            -- 每行显示的图标起始索引（触摸滑动时有可能会发生改变）
            disp_img_index = (cur_page-1)*MENU_IMG_CNT_PER_LINE+1
            -- 每行显示的图标起始x轴坐标（触摸滑动时有可能会发生改变）
            disp_img_x_offset = MENU_IMG_DEFAULT_X_OFFSET

            log.info("TP EVENT UP refresh page", old_index, new_index, cur_page)

            lib_win.refresh()
        else
            -- 根据坐标计算是否点击有效图标，如果有，则执行对应的处理函数
            log.info("TP EVENT UP click app", tp_data[1].x, tp_data[1].y)
        end
    end

    
    if move_last_x~=-1 and tp_data[1].event == tp.EVENT_UP then
        move_last_x = -1
    end

    -- 移动过程中
    if move_last_x~=-1 and tp_data[1].event == tp.EVENT_MOVE then
        -- 和上次移动记录的有效x坐标相比，本次移动是否大于等于3个像素
        -- 每移动3个像素当做1个有效像素来计算
        move_pixels = math.floor((tp_data[1].x - move_last_x)/3)
        if move_pixels~=0 then            
            new_x_offset = disp_img_x_offset+move_pixels
            -- 当页的图标没有出界，直接根据移动的位置显示本页图标即可
            if new_x_offset>=0 and new_x_offset<=(MENU_IMG_DEFAULT_X_OFFSET+MENU_IMG_X_SPACE) then
                valid_move = true
                disp_img_x_offset = new_x_offset
                move_last_x = tp_data[1].x
                lib_win.refresh()
            -- 当页的图标左边已经出界，说明应该显示当页图标以及右边一页的图标
            elseif new_x_offset < 0 then
                temp_index = disp_img_index+1
                --左移出界面，剩余的右边满屏最大列数索引没有超过image_table的最大列索引
                if temp_index+MENU_IMG_CNT_PER_LINE-1 <= #image_table then
                    valid_move = true
                    disp_img_index = temp_index
                    disp_img_x_offset = MENU_IMG_DEFAULT_X_OFFSET
                    lib_win.refresh()
                end
            -- 当页的图标右边已经出界，说明应该显示左边一页的图标以及当页图标
            elseif new_x_offset > (MENU_IMG_DEFAULT_X_OFFSET+MENU_IMG_X_SPACE) then
                temp_index = disp_img_index-1
                --右移出界面，剩余的左边满屏最大列数索引没有小于image_table的第一列索引
                if temp_index >= 1 then
                    valid_move = true
                    disp_img_index = temp_index
                    disp_img_x_offset = MENU_IMG_DEFAULT_X_OFFSET
                    lib_win.refresh()
                end
            end
        end
    end
end


--窗口表
local win =
{
    on_refresh = refresh_proc_func,
    on_touch = touch_proc_func,
}


local function open()
    lib_win.add(win)
end


sys.subscribe("OPEN_MAIN_MENU_WIN", open)

