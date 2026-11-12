--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.11.10
@author  孟伟
@usage
U盘FOTA升级方式（无UI界面通用版），适用于Air8607w、Air8603系列、Air8605系列模块：

1、开机5秒后设备自动进入U盘升级模式，USB切换为HOST主机模式；
2、插入带有升级包的U盘（升级包文件名固定为 update.bin，放在U盘根目录）；
3、设备自动给U盘座供电（UVC_EN=GPIO58）、挂载U盘，分块读取升级包文件写入flash中的fota分区；
4、升级包校验通过后设备自动重启，重启后自动应用升级；
5、升级结果可以通过观察日志中的版本号来区分；

注意：固件需支持usb库主机模式和fatfs的U盘挂载（要求见readme.md固件要求章节）；
切到主机模式后USB虚拟串口日志会消失，请通过UART物理日志串口观察日志。

适用场景：
    - 现场无网络、无法远程升级时，通过U盘本地升级固件；
    - 无屏幕等UI交互硬件的设备，仅通过日志观察升级过程；

更多说明参考本目录下的readme.md文件
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
PROJECT = "fota_usb_disk_test"
VERSION = "1.0.0" --不同于使用libfota2扩展库来升级必须是xxx.xxx.xxx的格式，这里可以自定义版本号格式。


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 循环打印版本号, 方便看版本号变化, 非必须
function print_version()
    while true do
        sys.wait(1000)
        log.info("fota", "version", VERSION)
    end
end
sys.taskInit(print_version)

-- U盘FOTA升级（无UI界面）：开机5秒后自动进入升级模式，插上U盘自动完成升级
require("fota_usb_disk")

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
