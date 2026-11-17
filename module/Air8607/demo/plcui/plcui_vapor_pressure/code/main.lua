--[[
@module  main
@summary 蒸气压测定仪 HMI（plcui 3 页界面，Air8607 10 寸 1024x600）
@version 2.0.0
@date    2026.11.17
@board   Air8607（Air1603）+ 10 寸 RGB 1024x600 + GT911 电容触摸

页面：运行总览(run，含电磁阀/步进/加热操作) / 环节手动(man) / 膨胀参数(test)。
界面素材与布局见 main.xml（由 tools/ui_spec.py 经 tools/gen_xml.py 生成），
本文件只做加载器，业务与界面分别在 vp_app.lua、ui_app.lua 里。

部署：main.lua / boot_app.lua / ui_app.lua / ui_vars.lua / vp_app.lua /
      tp_app.lua / exd_air8607_rgb.lua / main.xml 与全部 png / jpg 平铺到 /luadb。
]]

PROJECT = "plcui_vapor_pressure"
VERSION = "2.0.0"

log.info("main", PROJECT, VERSION)

-- 看门狗：9 秒超时，3 秒喂一次
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 加载顺序即依赖顺序，不许调换
require "ui_vars"
require "vp_app"
require "ui_app"
require "boot_app"

-- errDump / fota 的预留位：量产固件按需在本行下方追加加载（本演示不启用）

sys.run()
