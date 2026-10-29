-- 通用 USB SoC 日志口文件管理；与 TTS、字体和资源部署服务无关。
PROJECT = "usb_filemgr"
VERSION = "1.0.0"

sys = require "sys"
local hzadb = require "hzadb"

-- 如有外置 Flash，请先完成你自己的供电、SPI 和文件系统挂载。
-- hzadb 不绑定任何板型或 Flash 型号，io.lsmount() 中的挂载点会自动呈现给工具。
hzadb.fs()
hzadb.mem()

-- 文件定位、写入和关闭可能耗时。回调仅接收并排队，实际 I/O 在固定任务中执行。
local ready = hzadb.start({deferred = true})
if ready then
    log.info("filemgr", "ready", hzadb.version(), "USB SoC log port")
    if io.lsmount then
        for _, mount in ipairs(io.lsmount() or {}) do
            log.info("filemgr", "mount", mount.path, mount.fs)
        end
    end
else
    log.error("filemgr", "firmware requires LUAT_USE_LOG_USER_CMD")
end

-- 用于观察普通日志和文件传输能否同时工作；不等待联网、不自动修改设备文件。
sys.timerLoopStart(function()
    log.info("filemgr", "alive")
end, 5000)

sys.run()
