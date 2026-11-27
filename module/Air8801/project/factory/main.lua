--[[
@module  main
@summary K8801 出厂（factory）整机入口：改 PROJECT 一行切换型号，其余全部配置驱动
@version 2.0
@date    2026.11.24

=== PROJECT 命名规范 ===

    K8801_<TTL|232>_<LCD|CTP|RTP>_<尺寸>_<宽>x<高>[_<尾段>]

      K8801    : 整机型号
      TTL/232  : 串口电平。TTL 收发器不贴，GPIO12 保持低；232 收发器实贴，测试时 GPIO12 供电
      LCD      : 裸屏，板上没有触摸芯片
      CTP      : 电容触摸（GT911）
      RTP      : 电阻触摸（NS2009 四线）
      尺寸     : 屏幕尺寸（寸，整数，不带小数）。7 寸为主；480x272 工装屏按 4 记
      宽 x 高   : 1024x600 / 800x480 / 1280x800 / 480x272（宽高之间用 x，不用下划线）
      尾段      : 当前只用 _1，原样保留在型号里，程序不解释其含义；省略按 _1

  各段分隔符统一用下划线 `_`，例如 K8801_TTL_RTP_7_1024x600_1。
  解析器同时兼容连字符 `-`（老型号 K8801-TTL-RTP-7-1024x600-1 仍能识别），但新写法一律用下划线。

  PROJECT 必须是 ASCII 型号字符串：LuaTools 用它做工程标识，云端 FOTA 也按它鉴权。
  （本工程是厂测整包，不走云端 FOTA，故不设 PROJECT_KEY。）

=== 当前可选型号（改下方 PROJECT 一行即可切换）===

  无触摸（LCD）：
    K8801_TTL_LCD_7_1024x600_1
    K8801_232_LCD_7_1024x600_1

  电容触摸（CTP，GT911）：
    K8801_TTL_CTP_7_1024x600_1
    K8801_232_CTP_7_1024x600_1


  电阻触摸（RTP，NS2009）：
    K8801_TTL_RTP_7_1024x600_1
    K8801_232_RTP_7_1024x600_1
    K8801_TTL_RTP_4_480x272_1
    K8801_232_RTP_4_480x272_1


  当前实物：7 寸 1024x600，首板是电阻触摸 + TTL（RTP-1 型号）；电容屏型号同样可直接用。
  480x272 是 4.3 寸工装屏；电阻/裸屏版本语法同样成立，把 CTP 换成 RTP/LCD 即可。
  800x480 / 1280x800 暂未列入可选表，但语法合法：panels 里有对应 profile 就能直接填。

  解析在 core/platform_loader.lua 的 parse_model()；型号不合法时回退出厂默认屏并打 warn，
  不会黑屏，但型号与实装不符，产线核对日志里的 `型号解析` 一行。

=== 型号决定整机行为（无需额外开关）===

  电平段 → cfg.serial.mode：功能测试页只出现「TTL 串口」或「RS232 串口」一项；
  屏型段 → cfg.touch_mode：裸屏(LCD) 跳过触摸初始化，标定项与校准入口自动消失；
            CTP → 电容 GT911，RTP → 电阻 NS2009（带四点标定）。
  同一份代码因此能同时覆盖裸屏/电容/电阻三种整机，不靠运行期菜单让人猜硬件。

=== 系统启动流程 ===

  阶段1: require "platform_loader" → PROJECT 解析 → air8801_config.load → 板级输出上电
  阶段2: require "lcd_common"     → 按 project_config.hw 构建 _G.lcd_drv / _G.tp_drv
  阶段3: require "air8801_debug"  → CH343 调试口（PING# / PANEL?# / PANEL,RESET# / TP_CAL#）
  阶段4: require "boot_ui"        → 点屏 → logo → 背光 → 触摸 → 桌面
  阶段5: sys.run()                → 事件循环，模块间 publish/subscribe 解耦
]]

-- 出厂整机型号：一行同时定屏型（裸屏/电容/电阻）、分辨率、尺寸与串口电平
-- 当前调试目标 = 480x272 电阻触摸（尺寸段 4 = 4.3 寸工装屏）
-- 232 段决定串口走 RS232（GPIO12 供电）；板上是 TTL 收发器就改回 TTL
PROJECT = "K8801_TTL_CTP_7_1024x600_1"
-- 三段式版本号 XXX.YYY.ZZZ
VERSION = "001.000.001"

sys = require "sys"
log.info("main", PROJECT, VERSION)
require "platform_loader"
require "lcd_common"
require "air8801_debug"
require "boot_ui"
sys.run()

