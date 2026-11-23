--[[
@module  ui_vars
@summary 界面变量绑定表（组件 ← 变量），UI 模块只按这张表刷数，不直接碰业务变量
@version 1.0.0
@date    2026.11.16
@author  江访
@usage
本文件只描述「哪个组件的哪个属性，取 data_app.get() 里的哪个键」，三种角色都靠这张表拉平：
1、ui_vars.COMMON   四个页面共有的一层（顶栏 / 控制区 / 底栏都是同一套机箱）；
2、ui_vars.PAGES    每个页面的差异层（KPI、仪表、设备卡、报警行、参数框）；
3、ui_vars.TABS     页签 id 与页面 id 的对应，切页时同步选中态。
kind 取值：text 文本 / src 换图 / checked 选中 / disabled 禁用 / hidden 显隐 /
size 宽度（负载条） / angle 旋转角度（指针、旋钮） / slider 滑块值 /
state_color 设备状态文字配色 / level_color 报警级别文字配色 /
badge_hidden 未确认数归零时隐藏页签红点。
本文件的对外接口有 1 个函数（ui_vars.bind_list）与 4 张表（COMMON / PAGES / TABS / 两张配色表）。
]]

local ui_vars = {}

--[[ 设备状态文字配色 ]]
ui_vars.STATE_COLOR = {
    ["运行"] = "#8ff0ac",
    ["待机"] = "#f0cd7e",
    ["故障"] = "#ff9a90",
    ["急停"] = "#ff9a90",
}

--[[ 报警级别文字配色 ]]
ui_vars.LEVEL_COLOR = {
    ["严重"] = "#ff8b80",
    ["警告"] = "#f0cd7e",
    ["提示"] = "#9aa3a7",
}

--[[ 页签：id -> 页面 id ]]
ui_vars.TABS = {
    { id = "tab_ov", page = "overview" },
    { id = "tab_tr", page = "trend" },
    { id = "tab_al", page = "alarm" },
    { id = "tab_st", page = "settings" },
}

--[[ 四个页面共有的一层 ]]
ui_vars.COMMON = {
    { id = "clock",       var = "clock",       kind = "text" },
    { id = "shift",       var = "shift",       kind = "text" },
    { id = "status_text", var = "status_text", kind = "text" },
    { id = "lamp",        var = "lamp",        kind = "src" },
    { id = "comm_led",    var = "comm_led",    kind = "src" },
    { id = "comm_txt",    var = "comm_txt",    kind = "text" },
    { id = "total_out",   var = "total_out",   kind = "text" },
    { id = "pipe_txt",    var = "pipe_txt",    kind = "text" },
    { id = "sp_val",      var = "sp_val",      kind = "text" },
    { id = "knob_sp",     var = "knob_angle",  kind = "angle" },
    { id = "sl_sp",       var = "sp",          kind = "slider" },
    { id = "tab_num",     var = "tab_num",     kind = "text" },
    { id = "tab_badge",   var = "tab_num",     kind = "badge_hidden" },
}

--[[ 每页差异层 ]]
ui_vars.PAGES = {
    overview = {
        { id = "kpi1",  var = "kpi1",  kind = "text" },
        { id = "foot1", var = "foot1", kind = "text" },
        { id = "kpi2",  var = "kpi2",  kind = "text" },
        { id = "kpi3",  var = "kpi3",  kind = "text" },
        { id = "foot3", var = "foot3", kind = "text" },
        { id = "kpi4",  var = "kpi4",  kind = "text" },
        { id = "foot4", var = "foot4", kind = "text" },

        { id = "v_t", var = "v_t", kind = "text" },
        { id = "v_p", var = "v_p", kind = "text" },
        { id = "nd_t", var = "nd_t", kind = "angle" },
        { id = "nd_p", var = "nd_p", kind = "angle" },

        { id = "dev_title", var = "dev_title", kind = "text" },
        { id = "dt1", var = "dt1", kind = "text" },
        { id = "dt2", var = "dt2", kind = "text" },
        { id = "dt3", var = "dt3", kind = "text" },
        { id = "dt4", var = "dt4", kind = "text" },
        { id = "dt5", var = "dt5", kind = "text" },
        { id = "dt6", var = "dt6", kind = "text" },

        { id = "estop_flag", var = "estop", kind = "hidden_invert" },

        { id = "led0", var = "led0", kind = "src" },
        { id = "led1", var = "led1", kind = "src" },
        { id = "led2", var = "led2", kind = "src" },
        { id = "st0",  var = "st0",  kind = "state_color" },
        { id = "st1",  var = "st1",  kind = "state_color" },
        { id = "st2",  var = "st2",  kind = "state_color" },
        { id = "ld0",  var = "ld0",  kind = "text" },
        { id = "ld1",  var = "ld1",  kind = "text" },
        { id = "ld2",  var = "ld2",  kind = "text" },
        { id = "bar0", var = "bar0", kind = "size", h = 6 },
        { id = "bar1", var = "bar1", kind = "size", h = 6 },
        { id = "bar2", var = "bar2", kind = "size", h = 6 },
        { id = "sel0", var = "sel0", kind = "checked" },
        { id = "sel1", var = "sel1", kind = "checked" },
        { id = "sel2", var = "sel2", kind = "checked" },

        { id = "al_cnt", var = "al_cnt", kind = "text" },
        { id = "alv0", var = "alv0", kind = "level_color" },
        { id = "alv1", var = "alv1", kind = "level_color" },
        { id = "alv2", var = "alv2", kind = "level_color" },
        { id = "alt0", var = "alt0", kind = "text" },
        { id = "alt1", var = "alt1", kind = "text" },
        { id = "alt2", var = "alt2", kind = "text" },
        { id = "ald0", var = "ald0", kind = "text" },
        { id = "ald1", var = "ald1", kind = "text" },
        { id = "ald2", var = "ald2", kind = "text" },
        { id = "ad0",  var = "ad0",  kind = "src" },
        { id = "ad1",  var = "ad1",  kind = "src" },
        { id = "ad2",  var = "ad2",  kind = "src" },
        { id = "ak0",  var = "ak0",  kind = "src" },
        { id = "ak1",  var = "ak1",  kind = "src" },
        { id = "ak2",  var = "ak2",  kind = "src" },
    },

    trend = {
        { id = "st_t",  var = "st_t",  kind = "text" },
        { id = "st_p",  var = "st_p",  kind = "text" },
        { id = "st_sp", var = "st_sp", kind = "text" },
        { id = "st_d",  var = "st_d",  kind = "text" },
    },

    alarm = {
        { id = "al_stat", var = "al_stat", kind = "text" },
    },

    settings = {
        -- p1~p6 只作登记：textarea 不参与周期刷数（会冲掉用户正在输入的内容），
        -- 实际由 ui_app.refresh_param_boxes 在进页 / 提交 / 取消时回写
        { id = "p1", var = "p1", kind = "textarea" },
        { id = "p2", var = "p2", kind = "textarea" },
        { id = "p3", var = "p3", kind = "textarea" },
        { id = "p4", var = "p4", kind = "textarea" },
        { id = "p5", var = "p5", kind = "textarea" },
        { id = "p6", var = "p6", kind = "textarea" },
        { id = "sw1", var = "sw1", kind = "checked" },
        { id = "sw2", var = "sw2", kind = "checked" },
        { id = "sw3", var = "sw3", kind = "checked" },
        { id = "st_br",  var = "st_br",  kind = "text" },
        { id = "st_msg", var = "st_msg", kind = "text" },
        { id = "sl_br",  var = "bright", kind = "slider" },
    },
}

--[[ 取某页要刷的绑定列表：共有层 + 该页差异层 ]]
function ui_vars.bind_list(page)
    local list = {}
    local common = ui_vars.COMMON
    for i = 1, #common do
        list[#list + 1] = common[i]
    end
    local own = ui_vars.PAGES[page]
    if own then
        for i = 1, #own do
            list[#list + 1] = own[i]
        end
    end
    return list
end

return ui_vars
