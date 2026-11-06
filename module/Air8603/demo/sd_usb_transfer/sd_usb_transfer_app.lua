--[[
@module  sd_usb_transfer_app
@summary SD卡与U盘文件互传应用功能模块
@version 1.0
@date    2026.11.06
@author  黄何
@usage
本文件为sd_usb_transfer应用功能模块，核心业务逻辑为：
1、挂载SD卡到/sd，把USB切到主机模式并挂载U盘到/udisk；
2、按 CFG.direction 指定的方向，对两侧同名目录做整棵复制/同步；
3、复制按 CFG.chunk（默认32KB）分块读写，可选写完逐块回读比对；
4、可选复制成功后删除源文件（搬运模式）；
5、过程日志同时写一份到SD卡，拔盘或者串口断开之后也能查。

本文件没有对外接口，直接在main.lua中require "sd_usb_transfer_app"就可以加载运行；
]]

local sd    = require "sd_mount"
local udisk = require "udisk"
local xfer  = require "file_xfer"


-- ==================== 配置（改这里就够了） ====================
local CFG = {
    -- 复制方向：
    --   "sd2usb"  SD卡 -> U盘
    --   "usb2sd"  U盘 -> SD卡
    --   "both"    双向同步，两程都只补"对方没有"的文件，同名同大小直接跳过
    direction = "sd2usb",

    -- 两侧使用的同名目录（不存在会自动创建）
    pair_dir = "8603_xfer",

    delete_src = false,      -- true=搬运（复制并校验通过后删源文件）；false=只复制
    overwrite  = true,       -- 目标有同名文件时是否覆盖
    verify     = true,       -- 写完是否回读逐块比对
    chunk      = 32 * 1024,  -- 分块大小，32KB 在 SD(SPI) 和 U 盘上都是比较稳的值

    wait_usb_ms = 60000,     -- 上电后等U盘插入的最长时间
    log_to_sd   = true,      -- 是否把过程日志同时写进SD卡
}

local LOG_PATH = "/sd/sd_usb_transfer_log.txt"


-- ==================== 日志 ====================
local log_file_warned = false

-- 往SD卡上的日志文件追加一行
-- "a"打不开且文件还不存在时，用"w+"建一次（"w+"会清空，所以不能每行都用）
local function append_file(line)
    if not (CFG.log_to_sd and sd.is_mounted()) then return end

    local f = io.open(LOG_PATH, "a")
    if not f then
        local not_exist = not (io.dexist and select(2, pcall(io.dexist, LOG_PATH)))
        if not_exist then f = io.open(LOG_PATH, "w+") end
    end
    if not f then
        -- 偶发打不开（fatfs忙），隔50ms再试一次
        sys.wait(50)
        f = io.open(LOG_PATH, "a")
    end
    if not f then
        if not log_file_warned then
            log_file_warned = true
            log.warn("sd_usb_transfer", "日志文件打不开：" .. LOG_PATH .. "（不影响传输）")
        end
        return
    end

    f:write(line .. "\r\n")
    f:close()
end

-- 同时打串口日志和SD卡日志
local function say(fmt, ...)
    local text = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    log.info("sd_usb_transfer", text)
    append_file(string.format("[%s] %s", os.date("%Y-%m-%d %H:%M:%S"), text))
end


-- ==================== 工具函数 ====================
local aborted = false

-- 判断文件/目录是否存在
-- 说明：不同固件 io.dexist / io.exists 的可用性不一样，两个都试一遍
local function exists(path)
    if io.dexist then
        local ok, r = pcall(io.dexist, path)
        if ok and r then return true end
    end
    if io.exists then
        local ok, r = pcall(io.exists, path)
        if ok and r then return true end
    end
    return false
end

-- 拼接挂载点和目录名，去掉挂载点末尾多余的"/"
local function dir_of(root, name)
    local r = root
    if r:sub(-1) == "/" then r = r:sub(1, -2) end
    return r .. "/" .. name
end

-- 取挂载点总容量（KB），失败返回nil
local function total_kb_of(mount)
    local ok, d = pcall(fatfs.getfree, mount)
    if ok and type(d) == "table" then return d.total_kb end
    return nil
end

-- KB 数转成人看的大小
local function size_text(kb)
    if kb < 1024 then return string.format("%.0f KB", kb) end
    return string.format("%.1f MB", kb / 1024)
end


-- ==================== 复制一个方向 ====================
-- @param title     日志标题
-- @param from_root 源挂载点，如 "/sd"
-- @param to_root   目标挂载点，如 "/udisk"
-- @param skip_same 目标已存在且大小相同时是否跳过
-- @return stats 统计表
local function run_one(title, from_root, to_root, skip_same)
    local src = dir_of(from_root, CFG.pair_dir)
    local dst = dir_of(to_root, CFG.pair_dir)

    say("── %s ──", title)
    say("源目录：%s", src)
    say("目标目录：%s", dst)

    if not exists(src) then
        say("源目录不存在，跳过本方向（先在 %s 里放点文件）", src)
        return { ok = true, files = 0, bytes = 0, skipped = 0, failed = 0, ms = 0, errors = {} }
    end

    local stats = xfer.copy_tree(src, dst, {
        overwrite    = CFG.overwrite,
        skip_same    = skip_same,
        verify       = CFG.verify,
        delete_src   = CFG.delete_src,
        chunk        = CFG.chunk,
        -- U盘被拔掉或者外部要求中止时，尽快停下来
        should_abort = function() return aborted or not udisk.is_mounted() end,
        on_file      = function(path, i, total)
            say("  [%d/%d] %s", i, total, path)
        end,
    })

    say("结果：%s", xfer.summary_text(stats))
    for _, e in ipairs(stats.errors) do say("  ! %s", e) end
    return stats
end


-- ==================== 空间预检 ====================
-- 只统计源目录大小，和目标剩余空间比一下，避免传一半才发现放不下
local function check_space(from_root, to_root)
    local free_kb = 0
    pcall(function()
        local d = fatfs.getfree(to_root)
        if type(d) == "table" then free_kb = d.free_kb or 0 end
    end)

    local need_kb = 0
    pcall(function()
        -- 递归累加源目录大小（lsdir单页最多100条，要分页取）
        local function walk(p, depth)
            if depth > 6 then return end
            local px = p:sub(-1) == "/" and p or (p .. "/")
            local offset = 0
            while true do
                local ok, list = io.lsdir(px, 100, offset)
                if not ok or type(list) ~= "table" or #list == 0 then break end
                for _, it in ipairs(list) do
                    if it.type == 1 then
                        walk(px .. it.name, depth + 1)
                    else
                        need_kb = need_kb + (it.size or 0) / 1024
                    end
                end
                if #list < 100 then break end
                offset = offset + 100
            end
        end
        walk(dir_of(from_root, CFG.pair_dir), 0)
    end)

    if free_kb > 0 and need_kb > 0 then
        say("空间预检：目标剩 %s，待传约 %s", size_text(free_kb), size_text(need_kb))
        if need_kb > free_kb * 0.95 then
            say("目标空间不足（需要 %s，实际剩 %s），已停止", size_text(need_kb), size_text(free_kb))
            return false
        end
    end
    return true
end


-- ==================== 主流程 ====================
local function sd_usb_transfer_task()
    sys.wait(1000)

    say("===== SD卡 <-> U盘 文件互传 =====")
    say("方向=%s 目录=%s 覆盖=%s 校验=%s 删源=%s",
        CFG.direction, CFG.pair_dir, tostring(CFG.overwrite),
        tostring(CFG.verify), tostring(CFG.delete_src))

    -- 1、挂载SD卡
    local ok_sd, err_sd = sd.init()
    if not ok_sd then
        say("SD卡挂载失败：%s，本demo需要SD卡和U盘同时在位，退出", tostring(err_sd))
        return
    end

    -- 2、启动USB主机模式，等U盘接入
    local ok_usb, err_usb = udisk.start()
    if not ok_usb then
        say("USB主机模式启动失败：%s", tostring(err_usb))
        return
    end

    sys.subscribe("UDISK_REMOVED", function()
        aborted = true
        say("检测到U盘拔出，正在中止传输…")
    end)

    say("等待U盘插入（最多%d秒）…", math.floor(CFG.wait_usb_ms / 1000))
    if not udisk.wait_mounted(CFG.wait_usb_ms) then
        local freq = udisk.enum_fails()
        if freq > 0 then
            say("U盘没挂上：MSC握手失败%d次", freq)
            say("  排查：①换一个普通单分区U盘（多合一读卡器/空卡槽容易卡在TEST UNIT READY）")
            say("        ②优先用USB2.0的U盘  ③确认J14的+5.5V有电")
        else
            say("没等到U盘：一直没有任何MSC接入事件")
            say("  排查：U盘是否插在J14/J7、供电是否正常、D+/D-是否接反")
        end
        return
    end
    say("U盘已就绪：%s", udisk.mount_point())

    -- 3、安全检查：确认两个挂载点真的是两个不同的卷
    --    某些固件的fatfs只支持1个卷，第二个mount会把第一个顶成别名，
    --    这时候继续复制就是"把SD拷到SD自己"，开了delete_src还会把源文件删掉
    do
        local t_sd, t_usb = total_kb_of("/sd"), total_kb_of("/udisk")
        if t_sd and t_usb and t_sd == t_usb then
            say("中止：/sd 和 /udisk 指向了同一个卷（总容量都是%d KB）", t_sd)
            say("  说明当前固件的fatfs不支持多卷，SD和U盘不能同时挂载")
            say("  Air8603 需要 V1031 及以后的固件，旧版本（如V1028）只能挂一个卷")
            udisk.unmount(true)
            return
        end
    end

    -- 4、空间预检（双向同步时两程方向不同，跳过）
    if CFG.direction ~= "both" then
        local from_root = (CFG.direction == "sd2usb") and "/sd" or "/udisk"
        local to_root   = (CFG.direction == "sd2usb") and "/udisk" or "/sd"
        if not check_space(from_root, to_root) then
            udisk.unmount(true)
            return
        end
    end

    -- 5、开始复制
    if CFG.direction == "both" then
        run_one("第1程：SD卡 → U盘（只补U盘缺的）", "/sd", "/udisk", true)
        if not aborted then
            run_one("第2程：U盘 → SD卡（只补SD卡缺的）", "/udisk", "/sd", true)
        end
    elseif CFG.direction == "usb2sd" then
        run_one("U盘 → SD卡", "/udisk", "/sd", false)
    else
        run_one("SD卡 → U盘", "/sd", "/udisk", false)
    end

    if CFG.delete_src then
        say("注意：delete_src=true，已按搬运处理（校验通过的源文件已删除）")
    end

    -- 6、收尾
    local free_sd, free_usb = 0, 0
    pcall(function() local d = fatfs.getfree("/sd") if type(d) == "table" then free_sd = d.free_kb end end)
    pcall(function() local d = fatfs.getfree("/udisk") if type(d) == "table" then free_usb = d.free_kb end end)
    say("===== 完成，剩余空间：SD卡 %s / U盘 %s =====", size_text(free_sd), size_text(free_usb))

    -- 卸载U盘，让它处于可以安全拔出的状态
    udisk.unmount(true)
    say("过程日志：%s", LOG_PATH)
end


--创建一个task，并且运行task的主函数sd_usb_transfer_task
sys.taskInit(sd_usb_transfer_task)
