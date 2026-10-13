--[[
@module  wifi_win
@summary WiFi 设置界面窗口模块（手机风格：自动扫描/配置/连接热点）
@version 2.1
@date    2026.08.24
@author  嵌入式软件设计开发代理
@usage
本模块为 WiFi 设置界面（wifi_win），提供手机风格的热点扫描、配置、连接交互：
1、WiFi 开关（airui.switch）：开关状态 fskv 持久化（默认开）；打开时自动扫描热点并自动连接已保存热点，
   关闭时清空扫描列表并断开 WiFi 连接（保留已保存热点列表）；
2、热点列表（airui.table）：显示扫描结果（已保存热点优先显示顶部，并从扫描结果回填真实信号强度），点击热点弹出密码输入；
3、密码输入弹窗（airui.textarea 密码模式 + airui.keyboard 虚拟键盘 + 连接/断开连接/忘记网络按钮）；
4、"扫描完成，共x个热点"提示显示在 WiFi 开关右侧（不占用列表空间）；
5、状态显示统一在 WiFi 开关右侧（已删除独立的"当前连接"状态行，热点列表获得更多空间）；
6、窗口打开时主动查询网络状态与开关状态（不再无条件显示"未连接 WiFi"）。

订阅消息：
- "OPEN_WIFI_WIN"         -- 打开 WiFi 设置窗口
- "WIFI_SCAN_RESULT"      -- 扫描结果 {list: [{ssid, rssi, bssid}]}（netdrv_wifi 发布）
- "WIFI_SAVED_RSP"        -- 保存列表响应 {list: [{ssid, password}]}
- "WIFI_CONNECTED"        -- WiFi 连接成功 {ssid}
- "WIFI_DISCONNECTED"     -- WiFi 断开 {reason}
- "WIFI_STATE_RSP"        -- WiFi 开关状态响应 {enabled}（netdrv_wifi 发布）
- "NET_STATUS"            -- 网络总状态 {wifi_connected, wifi_ssid, wifi_rssi, g4_connected, current_adapter}

发布消息：
- "WIFI_SCAN_REQ"         -- 发起扫描请求
- "WIFI_CONNECT_REQ"      -- 连接热点 {ssid, password}
- "WIFI_DISCONNECT_REQ"   -- 断开 WiFi
- "WIFI_FORGET_REQ"       -- 忘记热点 {ssid}
- "WIFI_GET_SAVED_REQ"    -- 获取保存列表
- "WIFI_GET_STATUS_REQ"   -- 查询网络状态（打开窗口时主动查询）
- "WIFI_ENABLE_REQ"       -- 打开 WiFi 功能（持久化 + 扫描 + 自动连接）
- "WIFI_DISABLE_REQ"      -- 关闭 WiFi 功能（持久化 + 断开 WiFi）
- "WIFI_GET_STATE_REQ"    -- 查询 WiFi 开关状态
- "OPEN_SETTINGS_WIN"     -- 返回设置页面
]]

local win_id = nil
local main_container = nil

-- UI 组件引用
local wifi_switch = nil          -- WiFi 开关
local wifi_state_label = nil     -- WiFi 开关右侧状态提示（扫描结果/连接状态，唯一状态显示区）
local hotspot_table = nil        -- 热点列表表格
local hotspot_scroll = nil       -- 热点列表滚动容器（热点多于可视行数时上下滑动查看）

-- 密码输入弹窗组件
local pwd_mask = nil             -- 弹窗遮罩
local pwd_panel = nil            -- 弹窗面板
local pwd_ta = nil               -- 密码输入框
local pwd_kb = nil               -- 虚拟键盘对象（airui.keyboard 创建）
local pwd_ssid = nil             -- 当前输入密码的热点 SSID

-- 数据缓存
local saved_list = {}            -- 已保存热点 [{ssid=..., password=...}]
local scan_results = {}          -- 扫描结果 [{ssid=..., rssi=..., bssid=...}]
local display_list = {}          -- 列表显示数据（已保存优先，去重）
local display_count = 0          -- 实际显示的热点数量

-- 热点列表布局常量
-- ⚠️ 行高自适应实现说明（手动折行 + 手动行高数组）：
-- LVGL lv_table 单元格文本默认自动换行，且 set_cell_text 时自动按换行行数重算行高
-- （refr_cell_size → get_row_height = 字体行高 + 上下 padding，20 号字约 54px），
-- 单行会变高、与原始 28px 紧凑行高不一致。而 airui 的 row_height（含数组）会在
-- set_cell_text 后强制 reapply 覆盖 LVGL 自动行高（luat_airui_table.c 1128 行）。
-- 因此采用「手动插入 \n + row_height 数组 = 28×行数」：估算折行行数与 LVGL 渲染一致时，
-- 单行保持 28px 紧凑、多行按 28×行数 自适应（2 行 56px、3 行 84px）。
local ROW_HEIGHT = 28            -- 单行行高基准（像素，紧凑模式）
local CELL_FONT_SIZE = 20        -- 单元格字号（与 lcd_drv.lua airui.font_load size=20 全局默认一致）
-- ⚠️ 折行参数校准说明（第八十四次修改）：
-- LVGL lv_table 单元格文本默认按可用宽度自动换行（lv_table.c 812/822 行：text_flags=NONE + max_width=列宽-padding），
-- 且换行时遇断字符（_、- 等）会回退到断点（lv_text.c 279 行），因此手动 \n 段宽必须 ≤ 实际可用宽度，
-- 否则段内会被 LVGL 二次换行（TP-LINK_ZHUTIANHUA 被拆成 8+8+2 三行即此原因）。
-- 实测反推：hzfont 20 号 ASCII 字符实际宽 ≈ 13px（16 字符×13=208px > 203px 触发二次换行）；
-- 实际可用宽度 = col_width 235 - 单元格左右 padding 各 16 = 203px（与单行 54px=字高22+padding32 互相印证）。
-- 第八十三次取 180 过保守，导致「茶室-降功耗,找合宙!」（8 中文×20 + 3 ASCII×13 = 199px ≤ 203px 实际可一行）
-- 被误判超宽拆成两行。因此 SSID_COL_WIDTH 取实际可用宽度 203：
--   茶室-降功耗,找合宙! = 199px ≤ 203 → 一行完整显示；
--   TP-LINK_ZHUTIANHUA = 18×13=234 > 203 → 折行：15 字符段 195px ≤ 203（LVGL 不二次换行）+ 剩余 3 字符 = 两行。
local SSID_COL_WIDTH = 203       -- SSID 列可容纳文本宽度（px，= 实际可用宽度 235-16×2，估算值与 LVGL 渲染一致）
local CHAR_W_CJK = 20            -- 中文字符宽度（px，20 号字全角 ≈ 字号，203px 内约 10 字/行）
local CHAR_W_ASCII = 13          -- ASCII 字符宽度（px，hzfont 20 号实际约 13px，由 16 字符段 208px>203px 触发二次换行反推）

-- 当前连接状态
local wifi_connected = false
local current_ssid = nil
local wifi_enabled = true        -- WiFi 功能开关（fskv 持久化，默认开启；实际值由 WIFI_STATE_RSP 同步）

-- 开关状态同步标志（防止 set_state 触发 on_change 造成递归/重复操作）
local wifi_switch_syncing = false

-- 前向声明（解决 local 函数相互引用的解析顺序）
local show_pwd_panel
local hide_pwd_panel
local on_pwd_confirm
local on_pwd_forget

--[[
设置 WiFi 开关右侧提示文字（wifi_state_label，唯一状态显示区）

@local
@function set_switch_text
@param text string 提示文字
@return nil
]]
local function set_switch_text(text)
    if wifi_state_label then
        wifi_state_label:set_text(text)
    end
end

--[[
热点行点击回调

已连接热点：断开连接；
其他热点：弹出密码输入弹窗（已保存热点预填密码）。

@local
@function on_cell_click
@param self userdata 表格对象（airui.table 回调标准参数）
@param row number 行号（0 为表头）
@param col number 列号
@param value string 单元格文本
@return nil
]]
local function on_cell_click(self, row, col, value)
    -- 表头行忽略
    if row <= 0 then
        return
    end
    local item = display_list[row]
    if not item then
        return
    end
    -- 点击任意热点：打开密码输入页（已连接热点的"断开连接"按钮在弹窗内操作）
    show_pwd_panel(item.ssid)
end

--[[
手动折行计算（UTF-8 感知）

按单元格可用宽度估算热点名称应折成几行，并在超宽位置插入换行符 \n。
与 LVGL 实际渲染保持一致：中文字符（UTF-8 多字节）按全角 20px 计，
ASCII 字符按半角 13px 计（hzfont 20 号实测反推，16 字符×13=208px>203px 触发 LVGL 二次换行）。
折行阈值 SSID_COL_WIDTH=203 与 LVGL 实际可用宽度一致（col_width 235 - 左右 padding 各 16），
估算值 ≤ 203px 的文本（如「茶室-降功耗,找合宙!」=199px）LVGL 一行完整显示、不二次换行；
估算值 > 203px 的文本折行后每段 ≤ 203px，LVGL 不会在段内二次换行。

@local
@function calc_wrap_text
@param text string 原始文本（SSID）
@param max_width number 单元格可用宽度（px）
@return string 插入 \n 后的文本
@return number 折行行数（≥1）
]] 
local function calc_wrap_text(text, max_width)
    if not text or #text == 0 then
        return text or "", 1
    end
    -- 字符宽度：中文全角按 CHAR_W_CJK 计，ASCII 半角按 CHAR_W_ASCII 计（20 号 hzfont 实测反推）
    local full_w = CHAR_W_CJK
    local half_w = CHAR_W_ASCII
    local lines = {}
    local cur = {}
    local cur_w = 0
    local i = 1
    local len = #text
    while i <= len do
        -- 读取一个 UTF-8 字符（1~3 字节）
        local b = string.byte(text, i)
        local char_len = 1
        local w = half_w
        if b >= 0xE0 then
            char_len = 3
            w = full_w
        elseif b >= 0xC0 then
            char_len = 2
            w = full_w
        end
        local ch = string.sub(text, i, i + char_len - 1)
        -- 检查加入当前字符后是否超宽
        if cur_w + w > max_width and #cur > 0 then
            table.insert(lines, table.concat(cur))
            cur = {}
            cur_w = 0
        end
        table.insert(cur, ch)
        cur_w = cur_w + w
        i = i + char_len
    end
    if #cur > 0 then
        table.insert(lines, table.concat(cur))
    end
    return table.concat(lines, "\n"), #lines
end

--[[
构建显示列表并刷新热点表格

显示策略（与手机设计一致）：
1、已保存热点优先显示顶部（带"已保存"标记）；
2、其次显示扫描结果（与已保存去重）；
3、当前连接的热点显示"已连接"。

@local
@function refresh_table
@return nil
]]
local function refresh_table()
    if not main_container then
        return
    end
    -- 调试日志：入口 + airui 版本（row_height 数组需 airui V1.1.3+ 支持）
    local airui_ver = "?"
    if airui and airui.version then
        local ok, v = pcall(airui.version)
        if ok then
            airui_ver = tostring(v)
        end
    end
    log.info("wifi_win", "refresh_table enter, saved=%d scan=%d airui=%s", #saved_list, #scan_results, airui_ver)
    -- 销毁旧表格与滚动容器
    if hotspot_table then
        hotspot_table:destroy()
        hotspot_table = nil
    end
    if hotspot_scroll then
        hotspot_scroll:destroy()
        hotspot_scroll = nil
    end
    -- 构建显示列表
    display_list = {}
    local seen = {}
    -- 已保存热点优先（从扫描结果回填真实信号强度，无扫描数据时保持 nil 显示 "-"）
    for _, item in ipairs(saved_list) do
        if not seen[item.ssid] then
            local rssi = nil
            for _, ap in ipairs(scan_results) do
                if ap.ssid == item.ssid then
                    rssi = ap.rssi
                    break
                end
            end
            table.insert(display_list, {ssid = item.ssid, rssi = rssi, saved = true})
            seen[item.ssid] = true
        end
    end
    -- 扫描结果（去重）
    for _, ap in ipairs(scan_results) do
        if not seen[ap.ssid] then
            table.insert(display_list, {ssid = ap.ssid, rssi = ap.rssi, saved = false})
            seen[ap.ssid] = true
        end
    end
    -- 显示全部扫描热点（滚动容器内，超出可视区域时手势上下滑动查看）
    display_count = #display_list
    -- 表格总行数 = 表头 + 全部热点；热点不足时填充空行至最少 5 行
    local rows = math.max(1 + display_count, 5)
    local fill_rows = rows - (1 + display_count)  -- 空行填充数
    -- 手动折行 + 手动行高数组（airui 会在 set_cell_text 后 reapply 覆盖 LVGL 自动行高，
    -- 因此行高必须由 Lua 侧精确给出 = 28×实际行数，保证单行 28px、多行按行数自适应）
    local wrapped_ssid = {}
    local row_heights = {ROW_HEIGHT}  -- 表头行高
    for i = 1, display_count do
        local item = display_list[i]
        local wrapped, lines = calc_wrap_text(item.ssid, SSID_COL_WIDTH)
        wrapped_ssid[i] = wrapped
        table.insert(row_heights, ROW_HEIGHT * lines)
    end
    for i = 1, fill_rows do
        table.insert(row_heights, ROW_HEIGHT)
    end
    -- 表格总高 = 各行行高之和
    local table_h = 0
    for _, h in ipairs(row_heights) do
        table_h = table_h + h
    end
    -- 调试日志：行数与行高数组（确认折行与自适应是否触发）
    log.info("wifi_win", string.format("rows=%d fill=%d table_h=%d row_height=array(%s)", rows, fill_rows, table_h, table.concat(row_heights, ",")))
    -- 滚动容器（可视区域 y=88, h=152；内容超高时手势滚动，480x272 下压缩高度；白色背景贴合浅色主题）
    hotspot_scroll = airui.container({
        parent = main_container,
        x = 10,
        y = 88,
        w = 460,
        h = 152,
        color = 0xFFFFFF
    })
    -- 表格（位于滚动容器内，高度 = 各行行高之和，可超出容器高度滚动；浅色主题：浅灰边框）
    hotspot_table = airui.table({
        parent = hotspot_scroll,
        x = 0,
        y = 0,
        w = 460,
        h = table_h,
        rows = rows,
        cols = 3,
        col_width = {235, 115, 100},
        -- 手动行高数组：单行 28px，多行 28×行数（airui reapply 覆盖 LVGL 自动行高，避免单行变 54px）
        row_height = row_heights,
        style = { cell_font_size = CELL_FONT_SIZE },  -- 显式指定单元格字号，与 lcd_drv 全局字体一致
        border_color = 0xD8D8D8
    })
    -- 填充表头（浅色主题：表头行深蓝文字 + 浅蓝底）
    hotspot_table:set_cell_text(0, 0, "热点名称")
    hotspot_table:set_cell_text(0, 1, "信号")
    hotspot_table:set_cell_text(0, 2, "状态")
    hotspot_table:set_cell_style("row", 0, {cell_text_color = 0x0D47A1, cell_bg_color = 0xE3F2FD})
    -- 填充数据行
    for i = 1, display_count do
        local item = display_list[i]
        local rssi_text = "-"
        if item.rssi then
            rssi_text = item.rssi .. "dBm"
        end
        local state_text = "未连接"
        local is_connected = (item.ssid == current_ssid and wifi_connected)
        if is_connected then
            state_text = "已连接"
        elseif item.saved then
            state_text = "已保存"
        end
        -- 设置手动折行后的 SSID 文本（行高由 row_height 数组按行数精确指定）
        hotspot_table:set_cell_text(i, 0, wrapped_ssid[i])
        hotspot_table:set_cell_text(i, 1, rssi_text)
        hotspot_table:set_cell_text(i, 2, state_text)
        -- 浅色主题：数据行默认深灰文字；已连接热点行深绿文字（与原深色主题 0x00E676 同色系、适配浅色背景）
        if is_connected then
            hotspot_table:set_cell_style("row", i, {cell_text_color = 0x00A860})
        else
            hotspot_table:set_cell_style("row", i, {cell_text_color = 0x333333})
        end
    end
    -- 空行：设置空格文本（行高已由 row_height 数组指定为单行 28px）
    for i = 1, fill_rows do
        hotspot_table:set_cell_text(1 + display_count + i, 0, " ")
    end
    -- 绑定点击回调
    hotspot_table:set_on_cell_click(on_cell_click)
end

--[[
隐藏密码输入弹窗

@local
@function hide_pwd_panel
@return nil
]]
hide_pwd_panel = function()
    -- 销毁关联的虚拟键盘对象（show_pwd_panel 中 airui.keyboard 创建）
    if pwd_kb then
        pwd_kb:destroy()
        pwd_kb = nil
    end
    if pwd_ta then
        pwd_ta:destroy()
        pwd_ta = nil
    end
    if pwd_panel then
        pwd_panel:destroy()
        pwd_panel = nil
    end
    if pwd_mask then
        pwd_mask:destroy()
        pwd_mask = nil
    end
    pwd_ssid = nil
end

--[[
密码输入弹窗：连接按钮回调

@local
@function on_pwd_confirm
@return nil
]]
on_pwd_confirm = function()
    if not pwd_ta then
        return
    end
    local pwd = pwd_ta:get_text() or ""
    local ssid = pwd_ssid
    if pwd == "" then
        -- 密码为空：不关闭弹窗（输入框 placeholder 已有提示）
        return
    end
    hide_pwd_panel()
    -- 发布连接请求（netdrv_wifi 订阅）；连接状态显示在 WiFi 开关右侧
    sys.publish("WIFI_CONNECT_REQ", ssid, pwd)
    set_switch_text("正在连接 " .. (ssid or "") .. " ...")
end

--[[
密码输入弹窗：忘记网络按钮回调

@local
@function on_pwd_forget
@return nil
]]
on_pwd_forget = function()
    local ssid = pwd_ssid
    hide_pwd_panel()
    sys.publish("WIFI_FORGET_REQ", ssid)
    -- 忘记后立即重新获取保存列表并刷新热点列表（修复：忘记网络后返回列表仍显示"已保存"）
    sys.publish("WIFI_GET_SAVED_REQ")
    set_switch_text("已忘记网络")
end

--[[
密码输入弹窗：断开连接按钮回调

@local
@function on_pwd_disconnect
@return nil
]]
on_pwd_disconnect = function()
    local ssid = pwd_ssid
    hide_pwd_panel()
    sys.publish("WIFI_DISCONNECT_REQ")
    set_switch_text("已断开 " .. (ssid or ""))
end

--[[
显示密码输入弹窗

@local
@function show_pwd_panel
@param ssid string 热点名称
@return nil
]]
show_pwd_panel = function(ssid)
    if pwd_panel then
        return
    end
    pwd_ssid = ssid
    -- 查找已保存密码（预填）
    local saved_pwd = ""
    local is_saved = false
    for _, item in ipairs(saved_list) do
        if item.ssid == ssid then
            saved_pwd = item.password or ""
            is_saved = true
            break
        end
    end
    -- 是否为当前已连接热点（用于显示"断开连接"按钮）
    local is_connected = (ssid == current_ssid and wifi_connected)
    -- 遮罩（覆盖全屏 480x272，防止误触底层控件）
    pwd_mask = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 272,
        color = 0x000000
    })
    -- 弹窗面板（480x272 下压缩高度并上移，保证整体在虚拟键盘上方可见；白色背景贴合浅色主题）
    pwd_panel = airui.container({
        parent = pwd_mask,
        x = 40,
        y = 8,
        w = 400,
        h = 113,
        color = 0xFFFFFF
    })
    -- 标题（深灰文字）
    airui.label({
        parent = pwd_panel,
        x = 0,
        y = 6,
        w = 400,
        h = 22,
        text = "输入密码: " .. ssid,
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    -- 取消按钮（右上角；浅蓝底深蓝字）
    airui.button({
        parent = pwd_panel,
        x = 350,
        y = 4,
        w = 40,
        h = 24,
        text = "X",
        font_size = 14,
        style = {
            bg_color = 0xE3F2FD,
            text_color = 0x1565C0,
            radius = 6,
        },
        on_click = hide_pwd_panel
    })
    -- 创建虚拟键盘对象（先创建，再在 textarea 中引用绑定；airui 标准用法）
    -- ⚠️ 根因修复：textarea 的 keyboard 参数必须传入 airui.keyboard() 创建的对象引用，
    -- 原代码传入普通配置表导致键盘对象从未创建，故弹窗出现时无键盘痕迹（2050 固件 airui 行为）
    pwd_kb = airui.keyboard({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 150,
        mode = "text",
        auto_hide = true,
        bg_color = 0xf1f1f1,
        on_commit = function(self)
            -- 按下键盘确认键：隐藏键盘并触发连接（与"连接"按钮等效）
            if self then
                self:hide()
            end
            on_pwd_confirm()
        end
    })
    -- 密码输入框（密码模式，引用上面创建的虚拟键盘对象）
    pwd_ta = airui.textarea({
        parent = pwd_panel,
        x = 20,
        y = 34,
        w = 360,
        h = 34,
        placeholder = "请输入WiFi密码",
        mode = "password",
        text = saved_pwd,
        max_len = 64,
        align = airui.TEXT_ALIGN_LEFT,
        style = {radius = 6, bg_color = 0xF0F0F0, text_color = 0x333333, font_size = 16},
        -- 关联虚拟键盘对象（点击输入框自动弹出键盘）
        keyboard = pwd_kb
    })

    -- 按钮区（y=78, h=32，弹窗宽 400）：连接 + 断开连接（仅已连接）+ 忘记网络（仅已保存）
    -- 连接按钮（蓝色主操作按钮）
    airui.button({
        parent = pwd_panel,
        x = 20,
        y = 78,
        w = 110,
        h = 32,
        text = "连 接",
        font_size = 16,
        style = {
            bg_color = 0x2196F3,
            text_color = 0xFFFFFF,
            radius = 6,
        },
        on_click = on_pwd_confirm
    })
    -- 断开连接按钮（仅当前已连接热点显示；浅蓝底深蓝字）
    if is_connected then
        airui.button({
            parent = pwd_panel,
            x = 145,
            y = 78,
            w = 110,
            h = 32,
            text = "断开连接",
            font_size = 16,
            style = {
                bg_color = 0xE3F2FD,
                text_color = 0x1565C0,
                radius = 6,
            },
            on_click = on_pwd_disconnect
        })
    end
    -- 忘记网络按钮（仅已保存热点显示；浅蓝底深蓝字）
    if is_saved then
        airui.button({
            parent = pwd_panel,
            x = 270,
            y = 78,
            w = 110,
            h = 32,
            text = "忘记网络",
            font_size = 16,
            style = {
                bg_color = 0xE3F2FD,
                text_color = 0x1565C0,
                radius = 6,
            },
            on_click = on_pwd_forget
        })
    end
end

--[[
WiFi 开关回调

@local
@function on_wifi_switch
@param self userdata 开关对象
@return nil
]]
local function on_wifi_switch(self)
    -- 程序同步开关状态（set_state）触发的回调，忽略
    if wifi_switch_syncing then
        return
    end
    local checked = self:get_state()
    -- 状态未变化（程序同步触发等场景）：忽略，避免重复操作
    if checked == wifi_enabled then
        return
    end
    wifi_enabled = checked
    if checked then
        -- WiFi 开关打开：通知 netdrv_wifi（持久化开启 + 扫描 + 自动连接已保存热点）
        set_switch_text("扫描中...")
        sys.publish("WIFI_ENABLE_REQ")
    else
        -- WiFi 开关关闭：通知 netdrv_wifi（持久化关闭 + 断开 WiFi 连接）
        set_switch_text("WiFi 已关闭")
        sys.publish("WIFI_DISABLE_REQ")
        -- 清空扫描结果（保留已保存热点列表），刷新表格
        scan_results = {}
        refresh_table()
    end
end

--[[
返回按钮回调：关闭窗口并返回设置页面

@local
@function on_back
@return nil
]]
local function on_back()
    if win_id then
        exwin.close(win_id)
    end
    sys.publish("OPEN_SETTINGS_WIN")
end

--[[
创建 UI：WiFi 设置界面布局（480x272）

@local
@function create_ui
@return nil
]]
local function create_ui()
    -- 主容器（白色背景，浅色主题）
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 272,
        color = 0xFFFFFF
    })
    -- 标题栏（浅蓝色）
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 45,
        color = 0x64B5F6
    })
    airui.button({
        parent = title_bar,
        x = 10,
        y = 8,
        w = 50,
        h = 30,
        text = "←",
        font_size = 18,
        style = {
            bg_color = 0xFFFFFF,
            text_color = 0x1565C0,
            radius = 6,
        },
        on_click = on_back
    })
    airui.label({
        parent = title_bar,
        x = 60,
        y = 10,
        w = 360,
        h = 25,
        text = "WiFi 设置",
        font_size = 20,
        color = 0x0D47A1,
        align = airui.TEXT_ALIGN_CENTER
    })
    -- WiFi 开关行（深灰文字）
    airui.label({
        parent = main_container,
        x = 20,
        y = 52,
        w = 60,
        h = 25,
        text = "WiFi",
        font_size = 16,
        color = 0x333333
    })
    wifi_switch = airui.switch({
        parent = main_container,
        x = 90,
        y = 50,
        w = 60,
        h = 28,
        checked = wifi_enabled,
        on_change = on_wifi_switch
    })
    -- WiFi 开关右侧提示：扫描完成共x个热点 / 连接状态（不占用列表空间；深绿文字适配浅色背景）
    wifi_state_label = airui.label({
        parent = main_container,
        x = 160,
        y = 52,
        w = 300,
        h = 25,
        text = "",
        font_size = 14,
        color = 0x00A860
    })
    -- 热点列表（已删除独立的"当前连接"状态行，状态统一显示在 WiFi 开关右侧，列表空间更大）
    refresh_table()
    -- 底部操作提示（删除扫描按钮，空间让给热点列表）
    airui.label({
        parent = main_container,
        x = 10,
        y = 250,
        w = 460,
        h = 14,
        text = "提示: 点击热点输入密码连接；热点较多时可上下滑动列表",
        font_size = 12,
        color = 0x8C8C8C,
        align = airui.TEXT_ALIGN_CENTER
    })
    -- 初始状态：主动查询保存列表、WiFi 开关状态与网络状态（状态统一显示在开关右侧）
    sys.publish("WIFI_GET_SAVED_REQ")
    sys.publish("WIFI_GET_STATE_REQ")
    sys.publish("WIFI_GET_STATUS_REQ")
end

--[[
扫描结果消息处理（netdrv_wifi 发布 WIFI_SCAN_RESULT）

@local
@function on_scan_result
@param list table 扫描结果列表 [{ssid, rssi, bssid}]
@return nil
]]
local function on_scan_result(list)
    scan_results = list or {}
    log.info("wifi_win", "on_scan_result cnt=%d", #scan_results)
    -- 扫描结果提示显示在 WiFi 开关右侧
    set_switch_text("扫描完成，共" .. #scan_results .. "个热点")
    refresh_table()
end

--[[
保存列表响应消息处理（netdrv_wifi 发布 WIFI_SAVED_RSP）

@local
@function on_saved_rsp
@param list table 保存列表 [{ssid, password}]
@return nil
]]
local function on_saved_rsp(list)
    saved_list = list or {}
    log.info("wifi_win", "on_saved_rsp cnt=%d", #saved_list)
    refresh_table()
end

--[[
WiFi 连接成功消息处理（netdrv_wifi 发布 WIFI_CONNECTED）

@local
@function on_wifi_connected
@param ssid string 连接的 SSID
@return nil
]]
local function on_wifi_connected(ssid)
    wifi_connected = true
    current_ssid = ssid
    set_switch_text("已连接: " .. (ssid or ""))
    refresh_table()
end

--[[
WiFi 断开消息处理（netdrv_wifi 发布 WIFI_DISCONNECTED）

@local
@function on_wifi_disconnected
@param reason string 断开原因
@return nil
]]
local function on_wifi_disconnected(reason)
    wifi_connected = false
    current_ssid = nil
    set_switch_text("未连接")
    refresh_table()
end

--[[
网络总状态消息处理（netdrv_wifi 发布 NET_STATUS）

@local
@function on_net_status
@param w_connected boolean WiFi 连接状态
@param ssid string 当前 WiFi SSID
@param rssi number 信号强度
@param g4_connected boolean 4G 连接状态
@param adapter number 当前默认网卡
@return nil
]]
local function on_net_status(w_connected, ssid, rssi, g4_connected, adapter)
    wifi_connected = w_connected or false
    if wifi_connected then
        current_ssid = ssid
        set_switch_text("已连接: " .. (ssid or ""))
    else
        current_ssid = nil
    end
    refresh_table()
end

--[[
WiFi 开关状态响应消息处理（netdrv_wifi 发布 WIFI_STATE_RSP）

窗口打开时主动查询开关状态：同步开关显示，并决定是否自动扫描。

@local
@function on_state_rsp
@param enabled boolean 开关状态（true 开启 / false 关闭）
@return nil
]]
local function on_state_rsp(enabled)
    wifi_enabled = enabled or false
    -- 同步开关显示状态（set_state 可能触发 on_change，用标志位防递归）
    if wifi_switch then
        wifi_switch_syncing = true
        wifi_switch:set_state(wifi_enabled)
        wifi_switch_syncing = false
    end
    if wifi_enabled then
        -- 开关开启：自动扫描（已保存热点由 netdrv_wifi 自动连接）
        set_switch_text("扫描中...")
        sys.publish("WIFI_SCAN_REQ")
    else
        set_switch_text("WiFi 已关闭")
    end
end

--[[
窗口创建回调

@local
@function on_create
@return nil
]]
local function on_create()
    log.info("wifi_win", "打开 WiFi 设置窗口")
    create_ui()
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
]]
local function on_destroy()
    hide_pwd_panel()
    if hotspot_table then
        hotspot_table:destroy()
        hotspot_table = nil
    end
    if hotspot_scroll then
        hotspot_scroll:destroy()
        hotspot_scroll = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    -- 子组件变量全部置 nil，防止窗口关闭后消息回调访问已销毁的 airui 对象
    wifi_switch = nil
    wifi_state_label = nil
    win_id = nil
end

--[[
打开 WiFi 设置窗口

@local
@function open_wifi_win
@return nil
]]
local function open_wifi_win()
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end
sys.subscribe("OPEN_WIFI_WIN", open_wifi_win)

-- 订阅消息
sys.subscribe("WIFI_SCAN_RESULT", on_scan_result)
sys.subscribe("WIFI_SAVED_RSP", on_saved_rsp)
sys.subscribe("WIFI_CONNECTED", on_wifi_connected)
sys.subscribe("WIFI_DISCONNECTED", on_wifi_disconnected)
sys.subscribe("WIFI_STATE_RSP", on_state_rsp)
sys.subscribe("NET_STATUS", on_net_status)
