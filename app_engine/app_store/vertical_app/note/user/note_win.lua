local note_win = {}

-- ==================== 常量定义 ====================
local SCREEN_W, SCREEN_H = 480, 800

local C = {
    PRIMARY = 0xB0E2FF,
    NEW_BTN_BG = 0xFFF8DC,
    NEW_BTN_TEXT = 0x8B7355,
    NEW_BTN_BORDER = 0xE6D5A8,
    DANGER = 0xEF4444,
    TEXT_PRIMARY = 0x0F172A,
    TEXT_SECONDARY = 0x64748B,
    TEXT_LIGHT = 0x94A3B8,
    BG_HEADER = 0xFFFEF5,
    BG_BUTTON = 0xFFF8DC,
    BUTTON_BORDER = 0xE6D5A8,
    BG_CARD = 0xFFF8DC,
    CARD_BORDER = 0xE6D5A8,
    BG_TAG = 0xF6E6A2,
    BG_DROPDOWN = 0xFFFFFF,
    DROPDOWN_BORDER = 0xE6D5A8,
    WHITE = 0xFFFFFF,
    DIVIDER = 0xE8DEC0,
    EDITOR_BG = 0xFFFDF5,
    EDITOR_BUTTON_BG = 0xF0E8D0,
    EDITOR_BUTTON_BORDER = 0xD4C4A8,
    SORT_NEW_TO_OLD = 1,
    SORT_OLD_TO_NEW = 2,
    DELETE_BTN_BG = 0xFFE5E5,
    DELETE_BTN_BORDER = 0xFFB3B3
}

-- ==================== fskv存储键名 ====================
local KV_NOTES = "notes_data"
local KV_CATEGORIES = "categories"
local KV_NEXT_ID = "next_id"
local KV_SORT_MODE = "sort_mode"

-- ==================== 笔记数据结构 ====================
local notes = {}
local next_id = 1

-- 排序状态：1=新到旧，2=旧到新
local sort_mode = C.SORT_NEW_TO_OLD

-- ==================== 分类数据 ====================
local categories = {"全部笔记", "未分类"}
local current_category = "全部笔记"
local dropdown_visible = false
local selector_text = nil
local notes_list_container = nil
local note_cards = {}
local notes_count_label = nil

-- UI组件
local root_container = nil
local page_main = nil
local page_editor = nil
local page_search = nil
local category_dropdown = nil
local category_dropdown_items = {}
local modal_bg = nil
local modal_name_input = nil
local folder_keyboard = nil

-- 编辑器相关
local editing_note_id = nil
local editor_title_input = nil
local editor_content_input = nil
local editor_word_count_label = nil
local editor_category_label = nil
local category_select_modal = nil
local editor_keyboard = nil

-- 搜索相关
local search_input = nil
local search_results_container = nil
local search_result_cards = {}
local search_keyboard = nil
local search_timer = nil

-- 窗口ID
local win_id = nil

-- 前向声明
local rebuild_dropdown = nil
local hide_dropdown = nil
local show_dropdown = nil
local show_create_folder_modal = nil
local refresh_notes_list = nil
local save_current_note = nil
local show_category_select_modal = nil
local close_category_modal = nil
local show_toast = nil
local refresh_search_results = nil
local show_editor_func = nil
local toggle_sort_mode = nil
local save_data_to_kv = nil
local load_data_from_kv = nil
local delete_note = nil
local delete_category = nil

-- ==================== 时间函数 ====================

local function get_current_date_time()
    local now = os.date("*t")
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", now.year, now.month, now.day, now.hour, now.min, now.sec)
end

local function get_date_ymd()
    local now = os.date("*t")
    return string.format("%04d-%02d-%02d", now.year, now.month, now.day)
end

-- ==================== Toast提示 ====================
local toast_timer = nil
local current_toast = nil

show_toast = function(msg)
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end
    if current_toast then
        current_toast:destroy()
        current_toast = nil
    end
    if not root_container then
        return
    end

    current_toast = airui.container({
        parent = root_container,
        x = SCREEN_W / 2 - 130,
        y = SCREEN_H - 65,
        w = 260,
        h = 40,
        color = 0x1E293B,
        radius = 20
    })
    airui.label({
        parent = current_toast,
        x = 0,
        y = 8,
        w = 260,
        h = 24,
        text = msg,
        font_size = 13,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    toast_timer = sys.timerStart(function()
        if current_toast then
            current_toast:destroy()
            current_toast = nil
        end
        toast_timer = nil
    end, 2000)
end

-- 初始化示例笔记
local function init_sample_notes()
    if #notes == 0 then
        local now = get_current_date_time()
        notes = {{
            id = 1,
            title = "欢迎使用笔记",
            content = "这是你的第一篇笔记，点击编辑开始记录吧。",
            category = "未分类",
            create_time = now,
            update_time = now
        }}
        next_id = 2
    end
end

-- ==================== fskv存储函数 ====================

save_data_to_kv = function()
    if not fskv then
        log.warn("note_win", "fskv库不存在，无法保存数据")
        return false
    end

    fskv.init()

    local notes_copy = {}
    for i, note in ipairs(notes) do
        notes_copy[i] = {
            id = note.id,
            title = note.title,
            content = note.content,
            category = note.category,
            create_time = note.create_time,
            update_time = note.update_time
        }
    end
    fskv.set(KV_NOTES, notes_copy)

    local categories_copy = {}
    for i, cat in ipairs(categories) do
        if cat ~= "全部笔记" then
            table.insert(categories_copy, cat)
        end
    end
    fskv.set(KV_CATEGORIES, categories_copy)

    fskv.set(KV_NEXT_ID, next_id)
    fskv.set(KV_SORT_MODE, sort_mode)

    log.info("note_win", "数据已保存到fskv, 笔记数量:", #notes)
    return true
end

load_data_from_kv = function()
    if not fskv then
        log.warn("note_win", "fskv库不存在，使用默认数据")
        init_sample_notes()
        return false
    end

    fskv.init()

    local saved_notes = fskv.get(KV_NOTES)
    if saved_notes and type(saved_notes) == "table" and #saved_notes > 0 then
        notes = {}
        for i, note in ipairs(saved_notes) do
            notes[i] = {
                id = note.id,
                title = note.title or "无标题",
                content = note.content or "",
                category = note.category or "未分类",
                create_time = note.create_time or get_current_date_time(),
                update_time = note.update_time or get_current_date_time()
            }
        end
        log.info("note_win", "从fskv加载笔记成功, 数量:", #notes)
    else
        init_sample_notes()
        log.info("note_win", "无保存数据，使用示例笔记")
    end

    local saved_categories = fskv.get(KV_CATEGORIES)
    if saved_categories and type(saved_categories) == "table" and #saved_categories > 0 then
        categories = {"全部笔记"}
        for i, cat in ipairs(saved_categories) do
            table.insert(categories, cat)
        end
        log.info("note_win", "从fskv加载分类成功, 数量:", #categories)
    else
        categories = {"全部笔记", "未分类"}
        log.info("note_win", "使用默认分类")
    end

    local saved_next_id = fskv.get(KV_NEXT_ID)
    if saved_next_id and type(saved_next_id) == "number" then
        next_id = saved_next_id
    else
        local max_id = 0
        for _, note in ipairs(notes) do
            if note.id > max_id then
                max_id = note.id
            end
        end
        next_id = max_id + 1
    end
    log.info("note_win", "下一个ID:", next_id)

    local saved_sort_mode = fskv.get(KV_SORT_MODE)
    if saved_sort_mode and (saved_sort_mode == C.SORT_NEW_TO_OLD or saved_sort_mode == C.SORT_OLD_TO_NEW) then
        sort_mode = saved_sort_mode
    end
    log.info("note_win", "排序模式:", sort_mode)

    return true
end

-- ==================== 删除功能 ====================

delete_note = function(note_id, note_title)
    airui.msgbox({
        title = "确认删除",
        text = "确定要删除笔记「" .. note_title .. "」吗？",
        buttons = {"取消", "删除"},
        on_action = function(self, label)
            if label == "删除" then
                for i, note in ipairs(notes) do
                    if note.id == note_id then
                        table.remove(notes, i)
                        break
                    end
                end
                if editing_note_id == note_id then
                    editing_note_id = nil
                    if editor_title_input then
                        editor_title_input:set_text("")
                    end
                    if editor_content_input then
                        editor_content_input:set_text("")
                    end
                end
                refresh_notes_list()
                refresh_search_results()
                save_data_to_kv()
                show_toast("笔记已删除")
            end
            self:hide()
        end
    }):show()
end

delete_category = function(cat_name)
    if cat_name == "全部笔记" or cat_name == "未分类" then
        show_toast("不能删除系统文件夹")
        return
    end

    local note_count = 0
    for _, note in ipairs(notes) do
        if note.category == cat_name then
            note_count = note_count + 1
        end
    end

    local msg = "确定要删除文件夹「" .. cat_name .. "」吗？"
    if note_count > 0 then
        msg = msg .. "\n该文件夹下有" .. note_count .. "篇笔记，将移动到「未分类」"
    end

    airui.msgbox({
        title = "确认删除",
        text = msg,
        buttons = {"取消", "删除"},
        on_action = function(self, label)
            if label == "删除" then
                for i, note in ipairs(notes) do
                    if note.category == cat_name then
                        note.category = "未分类"
                        note.update_time = get_current_date_time()
                    end
                end
                for i, cat in ipairs(categories) do
                    if cat == cat_name then
                        table.remove(categories, i)
                        break
                    end
                end
                if current_category == cat_name then
                    current_category = "全部笔记"
                    if selector_text then
                        selector_text:set_text(current_category)
                    end
                end
                rebuild_dropdown()
                refresh_notes_list()
                refresh_search_results()
                save_data_to_kv()
                show_toast("文件夹「" .. cat_name .. "」已删除")
            end
            self:hide()
        end
    }):show()
end

-- 获取当前编辑笔记的分类
local function get_current_note_category()
    if editing_note_id then
        for _, note in ipairs(notes) do
            if note.id == editing_note_id then
                return note.category
            end
        end
    end
    if _G.pending_note_category then
        return _G.pending_note_category
    end
    if current_category == "全部笔记" then
        return "未分类"
    end
    return current_category
end

-- 更新编辑器中的分类标签显示
local function update_editor_category_display()
    if editor_category_label then
        local cat = get_current_note_category()
        editor_category_label:set_text(cat)
    end
end

-- 更新笔记分类
local function update_note_category(new_category)
    if editing_note_id then
        for i, note in ipairs(notes) do
            if note.id == editing_note_id then
                note.category = new_category
                note.update_time = get_current_date_time()
                break
            end
        end
    else
        _G.pending_note_category = new_category
    end
    if editor_category_label then
        editor_category_label:set_text(new_category)
    end
    if refresh_notes_list then
        refresh_notes_list()
    end
    show_toast("已移动到「" .. new_category .. "」")
    save_data_to_kv()
end

-- ==================== 排序功能 ====================

toggle_sort_mode = function()
    if sort_mode == C.SORT_NEW_TO_OLD then
        sort_mode = C.SORT_OLD_TO_NEW
        show_toast("按时间从旧到新排序")
    else
        sort_mode = C.SORT_NEW_TO_OLD
        show_toast("按时间从新到旧排序")
    end
    refresh_notes_list()
    save_data_to_kv()
end

-- ==================== 页面跳转函数 ====================

show_editor_func = function()
    if page_main then
        page_main:set_hidden(true)
    end
    if page_editor then
        page_editor:set_hidden(false)
    end
    if page_search then
        page_search:set_hidden(true)
        if search_keyboard then
            search_keyboard:hide()
        end
    end
    if editor_keyboard then
        editor_keyboard:hide()
    end
    if category_dropdown then
        category_dropdown:set_hidden(true)
        dropdown_visible = false
    end
    update_editor_category_display()
end

local function show_main()
    if page_main then
        page_main:set_hidden(false)
    end
    if page_editor then
        page_editor:set_hidden(true)
        if editor_keyboard then
            editor_keyboard:hide()
        end
    end
    if page_search then
        page_search:set_hidden(true)
        if search_keyboard then
            search_keyboard:hide()
        end
        if search_input then
            search_input:set_text("")
        end
        refresh_search_results()
    end
    if category_dropdown then
        category_dropdown:set_hidden(true)
        dropdown_visible = false
    end
    if refresh_notes_list then
        refresh_notes_list()
    end
end

local function show_search()
    if page_main then
        page_main:set_hidden(true)
    end
    if page_editor then
        page_editor:set_hidden(true)
        if editor_keyboard then
            editor_keyboard:hide()
        end
    end
    if page_search then
        page_search:set_hidden(false)
        if search_input then
            search_input:set_text("")
        end
        refresh_search_results()
    end
    if category_dropdown then
        category_dropdown:set_hidden(true)
        dropdown_visible = false
    end
end

local function back_to_main()
    if save_current_note then
        save_current_note()
    end
    editing_note_id = nil
    _G.pending_note_category = nil
    close_category_modal()
    show_main()
end

local function handle_back()
    if win_id then
        exwin.close(win_id)
        sys.publish("OPEN_MAIN_MENU_WIN")
    end
end

-- ==================== 分类选择弹窗 ====================

close_category_modal = function()
    if category_select_modal then
        category_select_modal:destroy()
        category_select_modal = nil
    end
end

local function refresh_category_modal()
    if category_select_modal then
        close_category_modal()
        show_category_select_modal()
    end
end

show_category_select_modal = function()
    close_category_modal()

    local current_note_cat = get_current_note_category()

    category_select_modal = airui.container({
        parent = page_editor,
        x = 60,
        y = 150,
        w = 360,
        h = 400,
        color = 0xFFFFFF,
        radius = 24,
        border_width = 1,
        border_color = C.DROPDOWN_BORDER
    })

    airui.label({
        parent = category_select_modal,
        x = 0,
        y = 20,
        w = 360,
        h = 30,
        text = "选择分类",
        font_size = 18,
        color = C.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local scroll_area = airui.container({
        parent = category_select_modal,
        x = 0,
        y = 60,
        w = 360,
        h = 280,
        color = 0xFFFFFF
    })

    local y_offset = 0
    local item_height = 48

    for i = 2, #categories do
        local cat = categories[i]
        local is_selected = (cat == current_note_cat)

        local item_bg = airui.container({
            parent = scroll_area,
            x = 20,
            y = y_offset,
            w = 320,
            h = item_height,
            color = is_selected and C.PRIMARY or C.BG_BUTTON,
            radius = 24,
            border_width = 1,
            border_color = is_selected and C.PRIMARY or C.BUTTON_BORDER,
            on_click = function()
                update_note_category(cat)
                close_category_modal()
                save_data_to_kv()
            end
        })

        airui.label({
            parent = item_bg,
            x = 20,
            y = 14,
            w = 200,
            h = 20,
            text = cat,
            font_size = 15,
            color = is_selected and 0xFFFFFF or C.TEXT_PRIMARY,
            align = airui.TEXT_ALIGN_LEFT
        })

        if is_selected then
            airui.label({
                parent = item_bg,
                x = 280,
                y = 12,
                w = 20,
                h = 24,
                symbol = airui.SYMBOL_OK,
                font_size = 16,
                color = 0xFFFFFF
            })
        end

        y_offset = y_offset + item_height + 8
    end

    local new_folder_btn = airui.container({
        parent = scroll_area,
        x = 20,
        y = y_offset,
        w = 320,
        h = item_height,
        color = 0xF0E8D0,
        radius = 24,
        border_width = 1,
        border_color = C.EDITOR_BUTTON_BORDER,
        on_click = function()
            close_category_modal()
            if show_create_folder_modal then
                show_create_folder_modal()
            end
        end
    })

    airui.label({
        parent = new_folder_btn,
        x = 20,
        y = 14,
        w = 200,
        h = 20,
        text = "+ 新建文件夹",
        font_size = 15,
        color = C.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    y_offset = y_offset + item_height + 20

    local cancel_btn = airui.container({
        parent = category_select_modal,
        x = 60,
        y = 350,
        w = 240,
        h = 40,
        color = C.BG_BUTTON,
        radius = 30,
        border_width = 1,
        border_color = C.BUTTON_BORDER,
        on_click = close_category_modal
    })

    airui.label({
        parent = cancel_btn,
        x = 0,
        y = 10,
        w = 240,
        h = 20,
        text = "取消",
        font_size = 14,
        color = C.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- ==================== 搜索功能 ====================

refresh_search_results = function()
    if not search_results_container then
        return
    end

    local keyword = ""
    if search_input then
        keyword = search_input:get_text() or ""
        keyword = keyword:gsub("^%s*(.-)%s*$", "%1")
    end

    for _, card in ipairs(search_result_cards) do
        card:destroy()
    end
    search_result_cards = {}

    if keyword == "" then
        local empty_label = airui.label({
            parent = search_results_container,
            x = 0,
            y = 20,
            w = SCREEN_W,
            h = 30,
            text = "输入关键词搜索笔记",
            font_size = 14,
            color = C.TEXT_LIGHT,
            align = airui.TEXT_ALIGN_CENTER
        })
        table.insert(search_result_cards, empty_label)
        return
    end

    local search_results = {}
    for _, note in ipairs(notes) do
        local title_lower = string.lower(note.title or "")
        local content_lower = string.lower(note.content or "")
        local keyword_lower = string.lower(keyword)

        if string.find(title_lower, keyword_lower, 1, true) or string.find(content_lower, keyword_lower, 1, true) then
            table.insert(search_results, note)
        end
    end

    table.sort(search_results, function(a, b)
        if sort_mode == C.SORT_NEW_TO_OLD then
            return a.update_time > b.update_time
        else
            return a.update_time < b.update_time
        end
    end)

    if #search_results == 0 then
        local empty_label = airui.label({
            parent = search_results_container,
            x = 0,
            y = 20,
            w = SCREEN_W,
            h = 30,
            text = "没有找到相关笔记",
            font_size = 14,
            color = C.TEXT_LIGHT,
            align = airui.TEXT_ALIGN_CENTER
        })
        table.insert(search_result_cards, empty_label)
        return
    end

    local card_height = 86
    local card_spacing = 8
    local y_offset = 0

    for i, note in ipairs(search_results) do
        local card = airui.container({
            parent = search_results_container,
            x = 16,
            y = y_offset,
            w = SCREEN_W - 32,
            h = card_height,
            color = C.BG_CARD,
            radius = 18,
            border_width = 1,
            border_color = C.CARD_BORDER,
            on_click = function()
                editing_note_id = note.id
                if editor_title_input then
                    editor_title_input:set_text(note.title)
                end
                if editor_content_input then
                    editor_content_input:set_text(note.content)
                end
                if editor_word_count_label then
                    editor_word_count_label:set_text(string.len(note.content) .. "字")
                end
                update_editor_category_display()
                show_editor_func()
            end
        })
        table.insert(search_result_cards, card)

        airui.label({
            parent = card,
            x = 14,
            y = 12,
            w = 245,
            h = 22,
            text = note.title,
            font_size = 15,
            color = C.TEXT_PRIMARY,
            align = airui.TEXT_ALIGN_LEFT
        })

        local preview = note.content
        if #preview > 30 then
            preview = string.sub(preview, 1, 30) .. "..."
        end
        if preview == "" then
            preview = "无内容"
        end
        airui.label({
            parent = card,
            x = 14,
            y = 38,
            w = 245,
            h = 18,
            text = preview,
            font_size = 11,
            color = C.TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_LEFT
        })

        airui.label({
            parent = card,
            x = 14,
            y = 60,
            w = 100,
            h = 14,
            text = note.update_time,
            font_size = 10,
            color = C.TEXT_LIGHT,
            align = airui.TEXT_ALIGN_LEFT
        })

        local tag_bg = airui.container({
            parent = card,
            x = 120,
            y = 58,
            w = 80,
            h = 18,
            color = C.BG_TAG,
            radius = 20
        })
        airui.label({
            parent = tag_bg,
            x = 8,
            y = 2,
            w = 64,
            h = 14,
            text = note.category,
            font_size = 9,
            color = C.TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_CENTER
        })

        y_offset = y_offset + card_height + card_spacing
    end
end

-- 搜索输入框文字变化时的回调
local function on_search_text_change()
    if search_timer then
        sys.timerStop(search_timer)
    end
    search_timer = sys.timerStart(function()
        refresh_search_results()
        search_timer = nil
    end, 300)
end

-- ==================== 笔记保存函数 ====================

save_current_note = function()
    if not editor_title_input then
        return
    end

    local title = editor_title_input:get_text()
    local content = ""
    if editor_content_input then
        content = editor_content_input:get_text()
    end

    if title == "" and content == "" and editing_note_id == nil then
        return
    end

    local now = get_current_date_time()
    local note_category = get_current_note_category()

    if editing_note_id then
        for i, note in ipairs(notes) do
            if note.id == editing_note_id then
                note.title = title ~= "" and title or "无标题"
                note.content = content
                note.category = note_category
                note.update_time = now
                break
            end
        end
        show_toast("笔记已更新")
    else
        local new_note = {
            id = next_id,
            title = title ~= "" and title or "无标题",
            content = content,
            category = note_category,
            create_time = now,
            update_time = now
        }
        table.insert(notes, new_note)
        editing_note_id = new_note.id
        next_id = next_id + 1
        show_toast("笔记已保存")
    end

    _G.pending_note_category = nil

    if refresh_notes_list then
        refresh_notes_list()
    end

    save_data_to_kv()
end

local function update_word_count()
    if editor_content_input and editor_word_count_label then
        local content = editor_content_input:get_text() or ""
        local count = #content
        editor_word_count_label:set_text(count .. "字")
    end
end

-- ==================== 刷新笔记列表 ====================

local function get_filtered_notes()
    if current_category == "全部笔记" then
        return notes
    elseif current_category == "未分类" then
        local filtered = {}
        for _, note in ipairs(notes) do
            if note.category == "未分类" then
                table.insert(filtered, note)
            end
        end
        return filtered
    else
        local filtered = {}
        for _, note in ipairs(notes) do
            if note.category == current_category then
                table.insert(filtered, note)
            end
        end
        return filtered
    end
end

refresh_notes_list = function()
    if not notes_list_container then
        return
    end

    for _, card in ipairs(note_cards) do
        card:destroy()
    end
    note_cards = {}

    local filtered_notes = get_filtered_notes()

    table.sort(filtered_notes, function(a, b)
        if sort_mode == C.SORT_NEW_TO_OLD then
            return a.update_time > b.update_time
        else
            return a.update_time < b.update_time
        end
    end)

    if notes_count_label then
        notes_count_label:set_text(#filtered_notes .. "篇")
    end

    if #filtered_notes == 0 then
        local empty_label = airui.label({
            parent = notes_list_container,
            x = 0,
            y = 20,
            w = SCREEN_W,
            h = 30,
            text = "暂无笔记，点击「新建笔记」开始记录",
            font_size = 14,
            color = C.TEXT_LIGHT,
            align = airui.TEXT_ALIGN_CENTER
        })
        table.insert(note_cards, empty_label)
        return
    end

    local card_height = 86
    local card_spacing = 8
    local y_offset = 0

    for i, note in ipairs(filtered_notes) do
        local card = airui.container({
            parent = notes_list_container,
            x = 16,
            y = y_offset,
            w = SCREEN_W - 32,
            h = card_height,
            color = C.BG_CARD,
            radius = 18,
            border_width = 1,
            border_color = C.CARD_BORDER,
            on_click = function()
                editing_note_id = note.id
                if editor_title_input then
                    editor_title_input:set_text(note.title)
                end
                if editor_content_input then
                    editor_content_input:set_text(note.content)
                end
                if editor_word_count_label then
                    editor_word_count_label:set_text(string.len(note.content) .. "字")
                end
                update_editor_category_display()
                show_editor_func()
            end
        })
        table.insert(note_cards, card)

        airui.label({
            parent = card,
            x = 14,
            y = 12,
            w = 245,
            h = 22,
            text = note.title,
            font_size = 15,
            color = C.TEXT_PRIMARY,
            align = airui.TEXT_ALIGN_LEFT
        })

        local preview = note.content
        if #preview > 30 then
            preview = string.sub(preview, 1, 30) .. "..."
        end
        if preview == "" then
            preview = "无内容"
        end
        airui.label({
            parent = card,
            x = 14,
            y = 38,
            w = 245,
            h = 18,
            text = preview,
            font_size = 11,
            color = C.TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_LEFT
        })

        airui.label({
            parent = card,
            x = 14,
            y = 60,
            w = 100,
            h = 14,
            text = note.update_time,
            font_size = 10,
            color = C.TEXT_LIGHT,
            align = airui.TEXT_ALIGN_LEFT
        })

        local tag_bg = airui.container({
            parent = card,
            x = 120,
            y = 58,
            w = 80,
            h = 18,
            color = C.BG_TAG,
            radius = 20
        })
        airui.label({
            parent = tag_bg,
            x = 8,
            y = 2,
            w = 64,
            h = 14,
            text = note.category,
            font_size = 9,
            color = C.TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_CENTER
        })

        -- 删除按钮
        local delete_btn = airui.container({
            parent = card,
            x = SCREEN_W - 88,
            y = 28,
            w = 38,
            h = 38,
            color = C.DELETE_BTN_BG,
            radius = 18,
            border_width = 1,
            border_color = C.DELETE_BTN_BORDER,
            on_click = function()
                delete_note(note.id, note.title)
            end
        })
        airui.label({
            parent = delete_btn,
            x = 4,
            y = 6,
            w = 28,
            h = 28,
            symbol = airui.SYMBOL_TRASH,
            font_size = 18,
            color = C.DANGER,
            align = airui.TEXT_ALIGN_CENTER
        })

        y_offset = y_offset + card_height + card_spacing
    end
end

-- ==================== 新建文件夹弹窗 ====================

local function close_modal()
    if modal_bg then
        modal_bg:destroy()
        modal_bg = nil
    end
    modal_name_input = nil
    if folder_keyboard then
        folder_keyboard:hide()
    end
end

local function do_create_folder()
    if not modal_name_input then
        return
    end

    local name = modal_name_input:get_text()
    name = name:gsub("^%s*(.-)%s*$", "%1")

    if name == "" then
        show_toast("名称不能为空")
        return
    end

    local exists = false
    for _, c in ipairs(categories) do
        if c == name then
            exists = true
            break
        end
    end

    if exists then
        show_toast("文件夹「" .. name .. "」已存在")
        return
    end

    if name == "全部笔记" then
        show_toast("不能创建名称为「全部笔记」的文件夹")
        return
    end

    table.insert(categories, name)
    close_modal()

    if rebuild_dropdown then
        rebuild_dropdown()
    end

    show_toast("文件夹「" .. name .. "」已创建")

    if editing_note_id then
        for i, note in ipairs(notes) do
            if note.id == editing_note_id then
                note.category = name
                note.update_time = get_current_date_time()
                break
            end
        end
    else
        _G.pending_note_category = name
    end

    if editor_category_label then
        editor_category_label:set_text(name)
    end

    if refresh_notes_list then
        refresh_notes_list()
    end

    if category_select_modal then
        close_category_modal()
        show_category_select_modal()
    end

    show_toast("当前笔记已移动到「" .. name .. "」")

    save_data_to_kv()
end

show_create_folder_modal = function()
    if not folder_keyboard then
        folder_keyboard = airui.keyboard({
            parent = root_container,
            x = 0,
            y = -20,
            w = SCREEN_W,
            h = 200,
            mode = "text",
            auto_hide = false,
            preview = true,
            preview_height = 40,
            on_commit = function()
                do_create_folder()
            end
        })
    end

    modal_bg = airui.container({
        parent = root_container,
        x = 90,
        y = 180,
        w = 300,
        h = 200,
        color = 0xFFFFFF,
        radius = 28,
        border_width = 1,
        border_color = C.DROPDOWN_BORDER
    })

    airui.label({
        parent = modal_bg,
        x = 50,
        y = 20,
        w = 200,
        h = 30,
        text = "新建文件夹",
        font_size = 18,
        color = C.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local input_bg = airui.container({
        parent = modal_bg,
        x = 25,
        y = 60,
        w = 250,
        h = 50,
        color = C.BG_BUTTON,
        radius = 40
    })

    modal_name_input = airui.textarea({
        parent = input_bg,
        x = 16,
        y = 10,
        w = 218,
        h = 30,
        text = "",
        placeholder = "文件夹名称",
        font_size = 14,
        color = C.TEXT_PRIMARY,
        bg_color = 0x00000000,
        keyboard = folder_keyboard
    })

    local btn_container = airui.container({
        parent = modal_bg,
        x = 30,
        y = 130,
        w = 240,
        h = 44,
        color = 0xFFFFFF,
        alpha = 0
    })

    airui.button({
        parent = btn_container,
        x = 0,
        y = 0,
        w = 110,
        h = 40,
        text = "取消",
        font_size = 14,
        style = {
            bg_color = C.BG_BUTTON,
            text_color = C.TEXT_SECONDARY,
            radius = 40
        },
        on_click = function()
            close_modal()
        end
    })

    airui.button({
        parent = btn_container,
        x = 130,
        y = 0,
        w = 110,
        h = 40,
        text = "确定",
        font_size = 14,
        style = {
            bg_color = C.PRIMARY,
            text_color = 0xFFFFFF,
            radius = 40
        },
        on_click = function()
            do_create_folder()
        end
    })

    if folder_keyboard then
        folder_keyboard:show()
        folder_keyboard:set_target(modal_name_input)
        modal_name_input:set_cursor(0)
    end
end

-- ==================== 分类下拉菜单 ====================

hide_dropdown = function()
    if category_dropdown then
        category_dropdown:set_hidden(true)
        dropdown_visible = false
    end
end

show_dropdown = function()
    if category_dropdown then
        category_dropdown:set_hidden(false)
        dropdown_visible = true
    end
end

rebuild_dropdown = function()
    if not category_dropdown then
        return
    end

    for _, item in ipairs(category_dropdown_items) do
        item:destroy()
    end
    category_dropdown_items = {}

    local y = 0
    local item_height = 44

    -- 全部笔记
    local item1 = airui.container({
        parent = category_dropdown,
        x = 0,
        y = y,
        w = 196,
        h = item_height,
        color = 0xFFFFFF,
        alpha = 255,
        on_click = function()
            current_category = "全部笔记"
            if selector_text then
                selector_text:set_text(current_category)
            end
            hide_dropdown()
            if refresh_notes_list then
                refresh_notes_list()
            end
            show_toast("切换到: " .. current_category)
        end
    })
    table.insert(category_dropdown_items, item1)
    airui.label({
        parent = item1,
        x = 16,
        y = 12,
        w = 160,
        h = 20,
        text = "全部笔记",
        font_size = 14,
        color = C.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    y = y + item_height

    -- 未分类
    local item2 = airui.container({
        parent = category_dropdown,
        x = 0,
        y = y,
        w = 196,
        h = item_height,
        color = 0xFFFFFF,
        alpha = 255,
        on_click = function()
            current_category = "未分类"
            if selector_text then
                selector_text:set_text(current_category)
            end
            hide_dropdown()
            if refresh_notes_list then
                refresh_notes_list()
            end
            show_toast("切换到: " .. current_category)
        end
    })
    table.insert(category_dropdown_items, item2)
    airui.label({
        parent = item2,
        x = 16,
        y = 12,
        w = 160,
        h = 20,
        text = "未分类",
        font_size = 14,
        color = C.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    y = y + item_height

    -- 用户创建的文件夹
    for i = 3, #categories do
        local cat = categories[i]
        local item = airui.container({
            parent = category_dropdown,
            x = 0,
            y = y,
            w = 196,
            h = item_height,
            color = 0xFFFFFF,
            alpha = 255,
            on_click = function()
                current_category = cat
                if selector_text then
                    selector_text:set_text(current_category)
                end
                hide_dropdown()
                if refresh_notes_list then
                    refresh_notes_list()
                end
                show_toast("切换到: " .. current_category)
            end
        })
        table.insert(category_dropdown_items, item)
        airui.label({
            parent = item,
            x = 16,
            y = 12,
            w = 140,
            h = 20,
            text = cat,
            font_size = 14,
            color = C.TEXT_PRIMARY,
            align = airui.TEXT_ALIGN_LEFT
        })

        -- 删除按钮
        local delete_btn = airui.container({
            parent = item,
            x = 170,
            y = 10,
            w = 24,
            h = 24,
            color = 0xFFFFFF,
            on_click = function()
                hide_dropdown()
                delete_category(cat)
            end
        })
        airui.label({
            parent = delete_btn,
            x = 0,
            y = 0,
            w = 24,
            h = 24,
            symbol = airui.SYMBOL_TRASH,
            font_size = 12,
            color = C.DANGER,
            align = airui.TEXT_ALIGN_CENTER
        })

        y = y + item_height
    end

    -- 新建文件夹按钮
    local add_item = airui.container({
        parent = category_dropdown,
        x = 0,
        y = y,
        w = 196,
        h = item_height,
        color = 0xFFFFFF,
        alpha = 255,
        on_click = function()
            hide_dropdown()
            if show_create_folder_modal then
                show_create_folder_modal()
            end
        end
    })
    table.insert(category_dropdown_items, add_item)
    airui.label({
        parent = add_item,
        x = 16,
        y = 12,
        w = 160,
        h = 20,
        text = "+ 新建文件夹",
        font_size = 14,
        color = C.PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    category_dropdown:set_hidden(true)
end

-- ==================== UI 构建 ====================

local function create_ui()
    root_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.BG_HEADER
    })

    page_main = airui.container({
        parent = root_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.BG_HEADER
    })

    local header = airui.container({
        parent = page_main,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 72,
        color = C.BG_HEADER
    })

    local back_btn = airui.button({
        parent = header,
        x = 20,
        y = 16,
        w = 40,
        h = 40,
        text = "",
        style = {
            bg_color = C.BG_BUTTON,
            radius = 30,
            pad = 0,
            border_width = 1,
            border_color = C.BUTTON_BORDER
        },
        on_click = handle_back
    })
    airui.label({
        parent = back_btn,
        x = 12,
        y = 12,
        w = 16,
        h = 16,
        symbol = airui.SYMBOL_LEFT,
        font_size = 14,
        color = C.TEXT_PRIMARY
    })

    local search_btn = airui.button({
        parent = header,
        x = 280,
        y = 16,
        w = 40,
        h = 40,
        text = "",
        style = {
            bg_color = C.BG_BUTTON,
            radius = 30,
            pad = 0,
            border_width = 1,
            border_color = C.BUTTON_BORDER
        },
        on_click = show_search
    })
    airui.label({
        parent = search_btn,
        x = 12,
        y = 12,
        w = 16,
        h = 16,
        symbol = airui.SYMBOL_GPS,
        font_size = 14,
        color = C.TEXT_PRIMARY
    })

    local sort_btn = airui.button({
        parent = header,
        x = 328,
        y = 16,
        w = 40,
        h = 40,
        text = "",
        style = {
            bg_color = C.BG_BUTTON,
            radius = 30,
            pad = 0,
            border_width = 1,
            border_color = C.BUTTON_BORDER
        },
        on_click = toggle_sort_mode
    })
    airui.label({
        parent = sort_btn,
        x = 12,
        y = 12,
        w = 16,
        h = 16,
        symbol = airui.SYMBOL_SHUFFLE,
        font_size = 14,
        color = C.TEXT_PRIMARY
    })

    local selector = airui.container({
        parent = header,
        x = 376,
        y = 18,
        w = 100,
        h = 40,
        color = C.BG_BUTTON,
        radius = 30,
        border_width = 1,
        border_color = C.BUTTON_BORDER,
        on_click = function()
            if dropdown_visible then
                hide_dropdown()
            else
                rebuild_dropdown()
                show_dropdown()
            end
        end
    })
    airui.label({
        parent = selector,
        x = 10,
        y = 12,
        w = 16,
        h = 16,
        symbol = airui.SYMBOL_DIRECTORY,
        font_size = 12,
        color = C.TEXT_SECONDARY
    })
    selector_text = airui.label({
        parent = selector,
        x = 30,
        y = 12,
        w = 58,
        h = 16,
        text = current_category,
        font_size = 11,
        color = C.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local divider = airui.container({
        parent = page_main,
        x = 0,
        y = 71,
        w = SCREEN_W,
        h = 2,
        color = C.DIVIDER
    })

    airui.button({
        parent = page_main,
        x = 20,
        y = 84,
        w = SCREEN_W - 40,
        h = 48,
        text = "新建笔记",
        style = {
            bg_color = C.NEW_BTN_BG,
            text_color = C.NEW_BTN_TEXT,
            radius = 28,
            border_width = 1,
            border_color = C.NEW_BTN_BORDER
        },
        on_click = function()
            editing_note_id = nil
            _G.pending_note_category = nil
            if editor_title_input then
                editor_title_input:set_text("")
            end
            if editor_content_input then
                editor_content_input:set_text("")
            end
            if editor_word_count_label then
                editor_word_count_label:set_text("0字")
            end
            update_editor_category_display()
            show_editor_func()
        end
    })

    local list_header = airui.container({
        parent = page_main,
        x = 0,
        y = 144,
        w = SCREEN_W,
        h = 36,
        color = C.BG_HEADER
    })
    airui.label({
        parent = list_header,
        x = 28,
        y = 12,
        w = 80,
        h = 16,
        text = "笔记列表",
        font_size = 11,
        color = C.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    notes_count_label = airui.label({
        parent = list_header,
        x = SCREEN_W - 80,
        y = 12,
        w = 60,
        h = 16,
        text = "0篇",
        font_size = 11,
        color = C.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_RIGHT
    })

    notes_list_container = airui.container({
        parent = page_main,
        x = 0,
        y = 180,
        w = SCREEN_W,
        h = SCREEN_H - 180,
        color = C.BG_HEADER
    })

    category_dropdown = airui.container({
        parent = page_main,
        x = 275,
        y = 60,
        w = 200,
        h = 300,
        color = 0xFFFFFF,
        radius = 12,
        border_width = 1,
        border_color = C.DROPDOWN_BORDER,
        hidden = true
    })

    rebuild_dropdown()

    -- ==================== 编辑器页面 ====================
    page_editor = airui.container({
        parent = root_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.EDITOR_BG,
        hidden = true
    })

    local editor_top = airui.container({
        parent = page_editor,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 72,
        color = C.EDITOR_BG
    })

    local editor_back = airui.button({
        parent = editor_top,
        x = 20,
        y = 16,
        w = 40,
        h = 40,
        text = "",
        style = {
            bg_color = C.EDITOR_BUTTON_BG,
            radius = 30,
            pad = 0,
            border_width = 1,
            border_color = C.EDITOR_BUTTON_BORDER
        },
        on_click = back_to_main
    })
    airui.label({
        parent = editor_back,
        x = 12,
        y = 12,
        w = 16,
        h = 16,
        symbol = airui.SYMBOL_LEFT,
        font_size = 14,
        color = C.TEXT_PRIMARY
    })

    local editor_done = airui.button({
        parent = editor_top,
        x = SCREEN_W - 60,
        y = 16,
        w = 40,
        h = 40,
        text = "",
        style = {
            bg_color = C.EDITOR_BUTTON_BG,
            radius = 30,
            pad = 0,
            border_width = 1,
            border_color = C.EDITOR_BUTTON_BORDER
        },
        on_click = back_to_main
    })
    airui.label({
        parent = editor_done,
        x = 12,
        y = 12,
        w = 16,
        h = 16,
        symbol = airui.SYMBOL_OK,
        font_size = 14,
        color = C.TEXT_PRIMARY
    })

    local editor_scroll = airui.container({
        parent = page_editor,
        x = 0,
        y = 72,
        w = SCREEN_W,
        h = SCREEN_H - 72,
        color = C.EDITOR_BG
    })

    editor_keyboard = airui.keyboard({
        x = 0,
        y = -20,
        w = SCREEN_W,
        h = 200,
        mode = "text",
        auto_hide = true,
        preview = true,
        preview_height = 40,
        on_commit = function()
        end
    })

    editor_title_input = airui.textarea({
        parent = editor_scroll,
        x = 24,
        y = 20,
        w = SCREEN_W - 48,
        h = 56,
        text = "",
        placeholder = "标题",
        font_size = 28,
        color = C.TEXT_PRIMARY,
        bg_color = 0x00000000,
        max_length = 100,
        keyboard = editor_keyboard
    })

    local info_bar = airui.container({
        parent = editor_scroll,
        x = 24,
        y = 84,
        w = SCREEN_W - 48,
        h = 30,
        color = C.EDITOR_BG
    })

    airui.label({
        parent = info_bar,
        x = 0,
        y = 5,
        w = 100,
        h = 20,
        text = get_date_ymd(),
        font_size = 11,
        color = C.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    editor_word_count_label = airui.label({
        parent = info_bar,
        x = 105,
        y = 5,
        w = 80,
        h = 20,
        text = "0字",
        font_size = 11,
        color = C.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.label({
        parent = info_bar,
        x = 190,
        y = 5,
        w = 20,
        h = 20,
        text = "|",
        font_size = 11,
        color = C.TEXT_LIGHT,
        align = airui.TEXT_ALIGN_CENTER
    })

    editor_category_label = airui.label({
        parent = info_bar,
        x = 210,
        y = 5,
        w = 120,
        h = 20,
        text = "未分类",
        font_size = 11,
        color = C.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT,
        on_click = function()
            show_category_select_modal()
        end
    })

    airui.label({
        parent = info_bar,
        x = 330,
        y = 5,
        w = 15,
        h = 20,
        symbol = airui.SYMBOL_DOWN,
        font_size = 10,
        color = C.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
        on_click = function()
            show_category_select_modal()
        end
    })

    editor_content_input = airui.textarea({
        parent = editor_scroll,
        x = 24,
        y = 120,
        w = SCREEN_W - 48,
        h = 500,
        text = "",
        placeholder = "写点什么…",
        font_size = 15,
        color = C.TEXT_SECONDARY,
        bg_color = 0x00000000,
        max_length = 5000,
        keyboard = editor_keyboard,
        on_text_change = function()
            update_word_count()
        end
    })

    -- ==================== 搜索页面 ====================
    page_search = airui.container({
        parent = root_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.EDITOR_BG,
        hidden = true
    })

    local search_header = airui.container({
        parent = page_search,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 80,
        color = C.EDITOR_BG
    })

    local search_back = airui.button({
        parent = search_header,
        x = 16,
        y = 18,
        w = 48,
        h = 48,
        text = "",
        style = {
            bg_color = C.EDITOR_BUTTON_BG,
            radius = 30,
            pad = 0,
            border_width = 1,
            border_color = C.EDITOR_BUTTON_BORDER
        },
        on_click = back_to_main
    })
    airui.label({
        parent = search_back,
        x = 14,
        y = 14,
        w = 20,
        h = 20,
        symbol = airui.SYMBOL_LEFT,
        font_size = 18,
        color = C.TEXT_PRIMARY
    })

    search_keyboard = airui.keyboard({
        x = 0,
        y = -20,
        w = SCREEN_W,
        h = 200,
        mode = "text",
        auto_hide = true,
        preview = true,
        preview_height = 40,
        on_commit = function()
            refresh_search_results()
        end
    })

    local search_wrapper = airui.container({
        parent = search_header,
        x = 80,
        y = 18,
        w = SCREEN_W - 96,
        h = 48,
        color = C.BG_BUTTON,
        radius = 30,
        border_width = 1,
        border_color = C.BUTTON_BORDER
    })

    airui.label({
        parent = search_wrapper,
        x = 16,
        y = 16,
        w = 18,
        h = 18,
        symbol = airui.SYMBOL_GPS,
        font_size = 16,
        color = C.TEXT_SECONDARY
    })

    search_input = airui.textarea({
        parent = search_wrapper,
        x = 42,
        y = 12,
        w = SCREEN_W - 150,
        h = 26,
        text = "",
        placeholder = "搜索笔记标题或内容...",
        font_size = 15,
        color = C.TEXT_PRIMARY,
        bg_color = 0x00000000,
        keyboard = search_keyboard,
        on_focus = function()
            if search_keyboard then
                search_keyboard:show()
                search_keyboard:set_target(search_input)
            end
        end,
        on_text_change = function()
            on_search_text_change()
        end
    })

    local search_scroll = airui.container({
        parent = page_search,
        x = 0,
        y = 80,
        w = SCREEN_W,
        h = SCREEN_H - 80,
        color = C.EDITOR_BG
    })

    search_results_container = airui.container({
        parent = search_scroll,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 500,
        color = C.EDITOR_BG
    })

    load_data_from_kv()

    refresh_notes_list()
    refresh_search_results()
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    create_ui()
    show_main()
end

local function on_destroy()
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end
    if current_toast then
        current_toast:destroy()
        current_toast = nil
    end
    if search_timer then
        sys.timerStop(search_timer)
        search_timer = nil
    end
    if editor_keyboard then
        pcall(editor_keyboard.destroy, editor_keyboard)
        editor_keyboard = nil
    end
    if search_keyboard then
        pcall(search_keyboard.destroy, search_keyboard)
        search_keyboard = nil
    end
    if folder_keyboard then
        pcall(folder_keyboard.destroy, folder_keyboard)
        folder_keyboard = nil
    end
    if root_container then
        root_container:destroy()
        root_container = nil
    end
    win_id = nil
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy
    })
end

sys.subscribe("OPEN_NOTE_WIN", open_handler)
_G.note_win = note_win

return note_win