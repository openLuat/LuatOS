--[[
@module  main
@summary FactoryHMI 入口 · Air8607（Air1603 主控 + 10 寸 1024x600 RGB 屏 + GT911 触摸）
@version 1.1
@date    2026.11.11
@usage
本demo用 PLCUI 核心库实现一套工厂自动化产线人机界面（3# 配料灌装线），
由 design\index.html 原型导出，4 个页面覆盖 PLCUI 全部 7 种组件：

1、工艺流程页：原料罐 / 进料泵 / 调节阀 / 混合罐 / 换热器 / 循环泵 / 灌装阀 / 输送线，
   管道流光交替、罐内液位五档、产品箱灌装、6 张 KPI 数据卡；
   手动模式下可点设备启停，自动模式与急停状态拦截并提示；
2、参数设定页：8 组设定值（textarea + 数字键盘）带范围校验，3 种配方选中与应用；
3、报警页：9 行 x 5 列表格、行选中高亮、单条/全部确认、报警复位兼解除急停；
4、趋势页：3 系列 60 点实时折线 + 当前/最高/最低统计卡。

文件说明：
1、lcd_app.lua / tp_app.lua / exd_air8607_rgb.lua：Air8607 板级显示与触摸初始化
2、data_sim.lua：工艺数据模拟器
3、topbar.lua：四页共用的顶栏与底部操作条刷新
4、flow_win.lua / param_win.lua / alarm_win.lua / trend_win.lua：四个页面窗口模块
5、ui_app.lua：UI 总装（plcui.load、handlers 注册、切页、刷新调度）
6、boot_app.lua：启动编排
]]

PROJECT = "FACTORY_HMI"
VERSION = "001.999.001"

-- PLCUI 核心库不是全局变量，必须 require 之后才能用；
-- 这里统一 require 一次并提升为全局 plcui，供 ui_app / flow_win / tp_app / boot_app 等模块直接调用。
-- pcall 兜底：万一固件未带 LUAT_USE_PLCUI，脚本不会直接崩，后面各类调用前都会判空并报明确日志。
-- local ok_plcui, mod_plcui = pcall(require, "plcui")
-- if ok_plcui and type(mod_plcui) == "table" then
--     plcui = mod_plcui
--     log.info("main", "plcui 库加载成功")
-- elseif not plcui then
--     log.error("main", "plcui 库不可用，请烧录带 LUAT_USE_PLCUI 的固件")
-- end

log.info("main", PROJECT, VERSION)

if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

require "lcd_app"
require "tp_app"
require "data_sim"
require "topbar"
require "flow_win"
require "param_win"
require "alarm_win"
require "trend_win"
require "ui_app"
require "boot_app"

sys.run()
