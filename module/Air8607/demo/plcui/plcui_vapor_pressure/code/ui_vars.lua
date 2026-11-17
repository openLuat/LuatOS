--[[
@module  ui_vars
@summary 界面变量绑定表：元素 ID 与变量名 / 格式化 / 状态图映射
@version 2.0.0
@date    2026.11.17
@author  蒋骞
@usage
本文件为 plcui_vapor_pressure 的界面绑定数据表，界面层只按这里的条目刷值，
不直接读业务状态表；将来接真实设备时改 vp_app 的取数实现，本文件与 main.xml 不用动。

绑定三条约定：
1、text 表按页面分组，每项 { id, var, fmt, suffix }；fmt 为 nil 时直接写字符串，
   var 取出的必须是标量（数字或字符串），整表塞进 set_text 会让界面显示 table: 0x...
2、image 表为两态图切换，var 为 true 取 on，否则取 off。
3、state 表为多态图切换，var 取出的字符串是 map 的键。

布局件（液位块高度、滑块位置、波纹位置）不是简单赋值，由 ui_app 单独算，
不放在本文件的绑定表里。

本文件的对外接口有 0 个（纯数据表）。
]]

local ui_vars = {}

-- 文本绑定（按页面分组）
ui_vars.text = {
    run = {
        { id = "pv_pv", var = "pres", fmt = "%.1f" },
        { id = "pv_tv", var = "temp", fmt = "%.1f" },
        { id = "pv_lv", var = "lv_s" },
        { id = "pv_cv", var = "car_s" },
        { id = "pv_xv", var = "x_s" },
        { id = "rs_1", var = "stage_s" },
        { id = "rs_2", var = "valve_s" },
        { id = "rs_3", var = "pos_s" },
        { id = "rs_4", var = "lvl_s" },
        { id = "rs_5", var = "heat_s" },
        { id = "rs_6", var = "result_s" },
        { id = "ds_v1", var = "v1_s" },
        { id = "ds_v2", var = "v2_s" },
        { id = "ds_step", var = "step_s" },
        { id = "hs_temp", var = "tgt_s" },
    },
    man = {
        { id = "ms_1", var = "sum1" },
        { id = "ms_2", var = "sum2" },
        { id = "ms_3", var = "sum3" },
        { id = "ms_4", var = "sum4" },
        { id = "ms_5", var = "state_s" },
        { id = "ms_6", var = "sum6" },
    },
    test = {
        { id = "ts_a", var = "press0", fmt = "%.1f" },
        { id = "ts_b", var = "slope", fmt = "%.1f" },
        { id = "ts_c", var = "result", fmt = "%.1f" },
        { id = "ts_r", var = "rep", fmt = "%.2f", suffix = " kPa" },
    },
}

-- 两态图切换（阀门开 / 关）
ui_vars.image = {
    run = {
        { id = "pv_v1", var = "v1", on = "im_valve_o", off = "im_valve_c" },
        { id = "pv_v2", var = "v2", on = "im_valve_o", off = "im_valve_c" },
    },
}

-- 多态图切换（每页共用的顶栏状态灯）
ui_vars.state = {
    { id = "tb_lamp", var = "lamp", map = {
        idle = "im_lamp_idle", run = "im_lamp_run", alarm = "im_lamp_alarm" } },
}

-- 环节卡片状态灯与文字（环节手动页 6 张卡片）
ui_vars.card_lamp = { "mv_l1", "mv_l2", "mv_l3", "mv_l4", "mv_l5", "mv_l6" }
ui_vars.card_text = { "mv_s1", "mv_s2", "mv_s3", "mv_s4", "mv_s5", "mv_s6" }
ui_vars.card_map = {
    idle = "im_lamp_idle", run = "im_lamp_run",
    done = "im_lamp_done", alarm = "im_lamp_alarm",
}

-- 顶栏告警标签（急停时与 tb_badge 同位互斥显示）
ui_vars.ALARM_ID = "tb_alarm"
ui_vars.BADGE_ID = "tb_badge"
ui_vars.CLOCK_DATE_ID = "tb_cd"
ui_vars.CLOCK_TIME_ID = "tb_ct"

-- 液位分级素材：下标 1 对应液面 0mm，下标 11 对应液面 110mm（每级 11mm）。
-- 档位按活塞行程分（行程 110mm），液面最高就是 110mm = 腔高 62%，
-- 素材像素高度已按腔高 178mm 换算好；目标固件 PLCUI 1.0.1 没有
-- image:set_size，液位只能按级切图。
ui_vars.liq_src = {
    "im_liq00", "im_liq01", "im_liq02", "im_liq03", "im_liq04", "im_liq05",
    "im_liq06", "im_liq07", "im_liq08", "im_liq09", "im_liq10",
}

-- 软塞 11 个预置位置（下标 1 对应 0mm，下标 11 对应 110mm）。
-- 1.0.1 没有 set_pos，只能把软塞摆 11 份、按档位切显隐。
ui_vars.car_id = {
    "pv_car0", "pv_car1", "pv_car2", "pv_car3", "pv_car4", "pv_car5",
    "pv_car6", "pv_car7", "pv_car8", "pv_car9", "pv_car10",
}

-- 活塞杆 11 档长度，与 car_id 严格同档（同一下标同时切）：
-- 杆顶固定在电机底部，杆底正好等于软塞顶，所以杆不会从软塞下方露出来。
ui_vars.rod_id = {
    "pv_rod0", "pv_rod1", "pv_rod2", "pv_rod3", "pv_rod4", "pv_rod5",
    "pv_rod6", "pv_rod7", "pv_rod8", "pv_rod9", "pv_rod10",
}

-- 步骤条：环节 i 的三态资源（g 未开始 / a 进行中 / d 已完成）
ui_vars.CHIP_ID = { "stp1", "stp2", "stp3", "stp4", "stp5", "stp6" }
ui_vars.CHIP_SRC = {
    { g = "st1_g", a = "st1_a", d = "st1_d" },
    { g = "st2_g", a = "st2_a", d = "st2_d" },
    { g = "st3_g", a = "st3_a", d = "st3_d" },
    { g = "st4_g", a = "st4_a", d = "st4_d" },
    { g = "st5_g", a = "st5_a", d = "st5_d" },
    { g = "st6_g", a = "st6_a", d = "st6_d" },
}

return ui_vars
