--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2026.10.27
@usage
本demo演示的核心功能为：
1、把日志口复用成命令通道（合宙 adb，即 hzadb 协议 v2），不额外占用 UART：
   上位机（Luatools 的"设备文件管理"界面，或本目录 host/luat_usercmd.py）可以
   读写设备文件、枚举挂载点、查询分区空间/文件指纹/内存/网络状态；
2、设备端只安装"标准操作集"，开放哪些能力完全由脚本控制：
   hzadb.fs() 装 13 条文件系统指令（默认拦截 /luadb 的读文件，防固件脚本被读走）、
   hzadb.mem() 装内存状态指令、hzadb.netdrv() 装网络状态指令；
3、可选的 HMAC 挑战应答鉴权（hzadb.set_auth）：配置 token 后，未鉴权的连接只能
   HELLO/AUTH，避免别人插上日志口就能读文件；
4、可选的只读模式：hzadb_app.READ_ONLY=true 时用 hzadb.reg_op 覆盖写类指令，
   一律回 E_DENIED，演示"权限由脚本决定"这一设计；
5、命令帧与普通日志在同一根日志线上共存：本 demo 每 5 秒打一条心跳日志，
   用来验证收发文件时日志不会互相干扰；
6、启动时打印协议栈版本、挂载点、根分区空间和固件能力自检，
   出问题看日志就能分清"固件没开宏"还是"库没打包进去"。

固件要求（重要）：
- hzadb 依赖固件的 log.set_usercmd_cb / log.usercmd_write，需要固件打开
  LUAT_USE_LOG_USER_CMD；截至 2026-09-22 只有 Air1601/Air1602 固件提供该能力；
- 在 Air1603/Air1604/Air1605 等其它型号上，hzadb.start() 返回 false，
  本 demo 只打一条 warn、心跳照跑，不会阻塞启动，便于同一份脚本跨型号试跑；
- 开了 AUTH_TOKEN 但固件缺 crypto 时，鉴权配置失败会直接放弃启动（不会裸奔），
  同样返回 false，日志里有明确的 error 行。

打包要求（重要）：
- 设备端协议栈是通用库 script/libs/hzadb.lua，用 Luatools 烧录时要勾选"添加默认lib"，
  否则 require "hzadb" 会失败；本目录不再自带协议栈副本。

上位机：
- 图形界面：Luatools 的"设备文件管理"；
- 命令行：python host/demo_hzadb.py --port COMx（用法与参数见 readme.md）。

更多说明见本目录下的readme.md文件
]]


--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为999
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
PROJECT = "HZADB"
VERSION = "001.999.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


-- 如果内核固件支持wdt看门狗功能，此处对看门狗进行初始化和定时喂狗处理
-- 如果脚本程序死循环卡死，就会无法及时喂狗，最终会自动重启
if wdt then
    --配置喂狗超时时间为9秒钟
    wdt.init(9000)
    --启动一个循环定时器，每隔3秒钟喂一次狗
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级
-- 远程升级的详细用法，见fota的demo


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- 注意：hzadb 本身也提供 MEMINFO 指令，上位机可以直接查内存，这里只是本地打印
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)


-- 加载 hzadb 设备端应用功能模块
-- hzadb 协议栈在 script/libs/hzadb.lua，Luatools 需勾选"添加默认lib"才会一起打包；
-- 这里用 pcall 包一层：库没打进去时给一条明确提示，而不是抛出一堆堆栈让人猜
local ok, hzadb_app = pcall(require, "hzadb_app")


-- 启动应用任务
-- 任务体用具名函数，便于日志定位，也避免在 sys.taskInit 里写匿名函数
local function main_task()
    if not ok then
        log.error("main", "加载 hzadb_app 失败，请确认烧录时勾选了\"添加默认lib\"",
            "原始错误:", tostring(hzadb_app))
        return
    end

    -- ########## 1、安装指令集 + 启动协议栈 ##########
    -- 返回 false 有两种原因，具体是哪一种看 hzadb_app 里紧挨着的那条日志：
    --   1) 固件没开 LUAT_USE_LOG_USER_CMD（不支持 hzadb）；
    --   2) 配了 AUTH_TOKEN 但鉴权开启失败（如固件缺 crypto），此时宁可不启动也不裸奔
    -- 两种情况都不影响日志查看，脚本继续跑
    if hzadb_app.start() then
        log.info("main", "日志口已被 hzadb 接管，可以用 Luatools 设备文件管理或上位机连接了")
    else
        log.warn("main", "hzadb 未就绪，功能不可用",
            "需要 Air1601/Air1602 且固件打开 LUAT_USE_LOG_USER_CMD；配了 AUTH_TOKEN 时还需固件带 crypto")
    end
end

sys.taskInit(main_task)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
