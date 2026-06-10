-- 应用商店全生命周期测试模块
-- 支持两种模式:
--   1. 批量模式: 逐页直接HTTP拉取 → 逐个应用测试 → 汇总报告
--   2. 单app模式: 从 /testresult/single_app.json 读取一个app → 测试 → 写 /testresult/result.json

local M = {}

local exapp = rawget(_G, "exapp")
if not exapp then
    local ok2, mod2 = pcall(require, "exapp")
    exapp = ok2 and mod2 or nil
end

-- =================== 配置 ===================

local APP_STORE_API = "https://api.luatos.com/iot/appstore/list"

local TIMEOUT = {
    NETWORK_READY = 30000,
    FETCH_PAGE = 30000,
    INSTALL = 120000,
    LAUNCH = 5000,
    EXIT = 10000,
    UNINSTALL = 30000,
    PAGE_COOLDOWN = 10000,
    APP_INTERVAL = 3000,
    POLL_INTERVAL = 200,
}

local MAX_APPS = 10  -- nil = 全部

-- =================== 辅助函数 ===================

local function wait_until(check_fn, timeout_ms)
    local deadline = os.time() + math.ceil(timeout_ms / 1000)
    while not check_fn() do
        if os.time() >= deadline then
            return false
        end
        sys.wait(TIMEOUT.POLL_INTERVAL)
    end
    return true
end

-- =================== 直接 HTTP 拉取 (完全绕过图标下载!) ===================

local function fetch_one_page_direct(page, size)
    size = size or 10
    log.info("appstore_test", string.format("HTTP拉取第%d页...", page))

    local body = json.encode({
        category = "全部",
        sort = "recommend",
        page = page,
        size = size,
        query = ""
    })

    local code, headers, resp_body = http.request("POST", APP_STORE_API, {
        ["Content-Type"] = "application/json"
    }, body, { timeout = 30000 }).wait()

    if code ~= 200 or not resp_body then
        log.warn("appstore_test", string.format("第%d页HTTP请求失败 code=%d", page, code or -1))
        return {}, {has_more = false, total = 0, pages = 0}, false
    end

    local ok, resp = pcall(json.decode, resp_body)
    if not ok or type(resp) ~= "table" or resp.code ~= 0 then
        log.warn("appstore_test", "第%d页JSON解析失败或API错误", page)
        return {}, {has_more = false, total = 0, pages = 0}, false
    end

    local v = resp.value or {}
    local records = v.records or {}
    local total = tonumber(v.total) or 0
    local pages = tonumber(v.pages) or 1

    -- 标准化字段名 (跟 exapp.enrich 逻辑一致)
    for _, app in ipairs(records) do
        if not app.aid then
            app.aid = app.app_name or app.appname
        end
        if app.app_id and not app.appid then
            app.appid = app.app_id
        end
    end

    log.info("appstore_test", string.format("第%d页: %d个应用, 总计%d, 共%d页",
        page, #records, total, pages))

    return records, {has_more = page < pages, total = total, pages = pages}, true
end

-- =================== 单应用生命周期 ===================

local function install_app(app)
    local aid, name, url = tostring(app.aid), app.title or app.name or app.aid, app.url
    if not url or url == "" then return false, "应用URL为空" end
    log.info("appstore_test", string.format("  安装: %s (aid=%s)", name, aid))

    local success, received = false, false
    local handler = function(rx_aid, action, rx_success)
        if tostring(rx_aid) == aid and action == "install" then
            success, received = rx_success, true
        end
    end
    sys.subscribe("APP_STORE_ACTION_DONE", handler)
    sys.publish("APP_STORE_INSTALL", aid, url, name, "全部", "recommend")
    local ok = wait_until(function() return received end, TIMEOUT.INSTALL)
    sys.unsubscribe("APP_STORE_ACTION_DONE", handler)

    if not ok or not received then return false, "安装超时" end
    if not success then return false, "安装失败(服务器返回)" end
    if not exapp.list_installed()[aid] then return false, "安装后未在installed_info中找到" end
    return true, nil
end

local function launch_app(aid, path)
    log.info("appstore_test", string.format("  启动: aid=%s", aid))
    if not path then return false, "路径为空" end
    if exapp.is_running(path) then exapp.close(path); sys.wait(1000) end
    if not exapp.open(path) then return false, "exapp.open返回失败" end
    local ok = wait_until(function() return exapp.is_running(path) end, TIMEOUT.LAUNCH)
    if not ok then return false, "启动超时" end
    sys.wait(1000)
    if not exapp.is_running(path) then return false, "启动后立即退出(可能崩溃)" end
    return true, nil
end

local function exit_app(aid, path)
    log.info("appstore_test", string.format("  退出: aid=%s", aid))
    if not exapp.is_running(path) then return true, nil end
    exapp.close(path)
    local ok = wait_until(function() return not exapp.is_running(path) end, TIMEOUT.EXIT)
    if not ok then return false, "退出超时" end
    return true, nil
end

local function uninstall_app(aid, app)
    local name = app and (app.title or app.name) or aid
    log.info("appstore_test", string.format("  卸载: %s (aid=%s)", name, aid))
    if not exapp.list_installed()[aid] then return true, nil end

    local success, received = false, false
    local handler = function(rx_aid, action, rx_success)
        if tostring(rx_aid) == aid and action == "uninstall" then
            success, received = rx_success, true
        end
    end
    sys.subscribe("APP_STORE_ACTION_DONE", handler)
    sys.publish("APP_STORE_UNINSTALL", aid, "全部", "recommend")
    local ok = wait_until(function() return received end, TIMEOUT.UNINSTALL)
    sys.unsubscribe("APP_STORE_ACTION_DONE", handler)

    if not ok or not received then return false, "卸载超时" end
    if not success then return false, "卸载失败(服务器返回)" end
    if exapp.list_installed()[aid] then return false, "卸载后仍存在" end
    return true, nil
end

-- 测试单个应用的 4 阶段
local function test_one_app(app, idx, total)
    local aid, name = tostring(app.aid), app.title or app.name or app.aid
    log.info("appstore_test", string.rep("-", 40))
    log.info("appstore_test", string.format("[%d/%d] 测试: %s (aid=%s)", idx, total, name, aid))

    local stages = {}

    -- Install
    local ok, err = install_app(app)
    stages.install = {ok = ok, err = err}
    if not ok then
        log.error("appstore_test", "  FAIL [安装]: " .. (err or "?"))
        return {aid = aid, name = name, stages = stages, passed = false}
    end
    log.info("appstore_test", "  PASS [安装]")

    local info = exapp.list_installed()[aid]
    if not info or not info.path then
        stages.install = {ok = false, err = "无法获取安装路径"}
        sys.publish("APP_STORE_UNINSTALL", aid, "全部", "recommend"); sys.wait(2000)
        return {aid = aid, name = name, stages = stages, passed = false}
    end
    local path = info.path

    -- Launch
    ok, err = launch_app(aid, path)
    stages.launch = {ok = ok, err = err}
    if not ok then
        log.error("appstore_test", "  FAIL [启动]: " .. (err or "?"))
        if exapp.is_running(path) then exapp.close(path); sys.wait(1000) end
        sys.publish("APP_STORE_UNINSTALL", aid, "全部", "recommend"); sys.wait(2000)
        return {aid = aid, name = name, stages = stages, passed = false}
    end
    log.info("appstore_test", "  PASS [启动]")

    -- Exit
    ok, err = exit_app(aid, path)
    stages.exit = {ok = ok, err = err}
    if not ok then
        log.error("appstore_test", "  FAIL [退出]: " .. (err or "?"))
        if exapp.is_running(path) then exapp.close(path); sys.wait(2000) end
        sys.publish("APP_STORE_UNINSTALL", aid, "全部", "recommend"); sys.wait(2000)
        return {aid = aid, name = name, stages = stages, passed = false}
    end
    log.info("appstore_test", "  PASS [退出]")

    sys.wait(1000)

    -- Uninstall
    ok, err = uninstall_app(aid, app)
    stages.uninstall = {ok = ok, err = err}
    if not ok then
        log.error("appstore_test", "  FAIL [卸载]: " .. (err or "?"))
        return {aid = aid, name = name, stages = stages, passed = false}
    end
    log.info("appstore_test", "  PASS [卸载]")

    log.info("appstore_test", string.format("[%d/%d] PASS: %s", idx, total, name))
    sys.wait(TIMEOUT.APP_INTERVAL)
    return {aid = aid, name = name, stages = stages, passed = true}
end

-- =================== 主测试 ===================

function M.test_appstore_lifecycle()
    log.info("appstore_test", "========================================")
    log.info("appstore_test", "应用商店全生命周期测试 (直接HTTP拉取)")
    log.info("appstore_test", "========================================")

    -- 等待网络
    log.info("appstore_test", "等待网络就绪...")
    local net_ok = wait_until(function()
        return exapp.is_network_ready and exapp.is_network_ready()
    end, TIMEOUT.NETWORK_READY)
    if not net_ok then
        local ok_ip = sys.waitUntil("IP_READY", TIMEOUT.NETWORK_READY)
        if not ok_ip then assert(false, "网络未就绪") end
    end
    log.info("appstore_test", "网络已就绪")

    -- exapp 在 require 时已自动初始化, 无需重复调用

    -- 清理残留应用 (上次测试可能留下未卸载的 app)
    log.info("appstore_test", "清理残留应用...")
    local installed = exapp.list_installed()
    local cleaned = 0
    for aid, info in pairs(installed) do
        log.info("appstore_test", "  清理残留: " .. aid)
        -- 先确保应用未运行
        if info.path and exapp.is_running(info.path) then
            exapp.close(info.path)
            sys.wait(2000)
        end
        -- 事件驱动卸载
        local received = false
        local handler = function(rx_aid, action, rx_success)
            if tostring(rx_aid) == aid and action == "uninstall" then received = true end
        end
        sys.subscribe("APP_STORE_ACTION_DONE", handler)
        sys.publish("APP_STORE_UNINSTALL", aid, "全部", "recommend")
        local ok = wait_until(function() return received end, 15000)
        sys.unsubscribe("APP_STORE_ACTION_DONE", handler)
        if ok then cleaned = cleaned + 1 end
    end
    if cleaned > 0 then
        log.info("appstore_test", string.format("清理了 %d 个残留应用", cleaned))
        sys.wait(3000)  -- 让 HTTP 清理连接释放
    else
        log.info("appstore_test", "无残留应用")
    end

    -- 逐页测试
    local results = {
        apps = {},
        total_tested = 0, total_passed = 0,
        failed = {},
        pages_fetched = 0, store_total = 0,
    }
    local SIZE = 10
    local page = 1
    local has_more = true
    local global_idx = 0

    while has_more do
        -- 直接HTTP拉取 (无图标下载!)
        local apps, page_info, ok = fetch_one_page_direct(page, SIZE)
        if not ok or #apps == 0 then
            log.warn("appstore_test", string.format("第%d页拉取失败或无数据, 停止", page))
            break
        end

        results.pages_fetched = page
        results.store_total = page_info.total
        log.info("appstore_test", string.format("=== 第%d/%d页: %d个应用 ===",
            page, page_info.pages, #apps))

        -- 本页应用逐个下载+测试
        for _, app in ipairs(apps) do
            global_idx = global_idx + 1
            if MAX_APPS and results.total_tested >= MAX_APPS then
                has_more = false; break
            end

            local r = test_one_app(app, global_idx, page_info.total)
            results.total_tested = results.total_tested + 1
            table.insert(results.apps, r)
            if r.passed then
                results.total_passed = results.total_passed + 1
            else
                table.insert(results.failed, r)
            end
            -- 强制GC清理沙箱残留, 防止堆损坏传播到下一个应用
            collectgarbage("collect")
            collectgarbage("collect")  -- 两次GC确保finalizer清理干净
            sys.wait(2000)  -- 给后台线程时间释放资源
            log.info("appstore_test", string.format("  内存: %d KB", math.floor(collectgarbage("count"))))
        end

        -- 检查是否有更多页
        has_more = has_more and page_info.has_more
        if has_more then
            log.info("appstore_test", string.format("页间冷却 %ds...", TIMEOUT.PAGE_COOLDOWN / 1000))
            sys.wait(TIMEOUT.PAGE_COOLDOWN)
        end
        page = page + 1
    end

    -- 输出报告
    local total = results.total_tested
    local passed = results.total_passed
    local failed_count = #results.failed
    log.info("appstore_test", "========================================")
    log.info("appstore_test", "应用商店全生命周期测试结果")
    log.info("appstore_test", string.format("应用商店总应用数: %d", results.store_total))
    log.info("appstore_test", string.format("已测试: %d | 通过: %d | 失败: %d | 通过率: %.1f%%",
        total, passed, failed_count, total > 0 and (passed / total * 100) or 0))
    log.info("appstore_test", string.format("测试覆盖: %d/%d 页", results.pages_fetched, math.ceil(results.store_total / SIZE)))

    -- 紧凑输出通过列表
    if passed > 0 then
        local names = {}
        for _, r in ipairs(results.apps) do
            if r.passed then table.insert(names, r.name) end
        end
        log.info("appstore_test", "通过列表(" .. passed .. "): " .. table.concat(names, ", "))
    end

    -- 失败详情
    if failed_count > 0 then
        log.info("appstore_test", "--- 失败详情 (" .. failed_count .. ") ---")
        for i, f in ipairs(results.failed) do
            local fs = {}
            for stage, s in pairs(f.stages) do
                if not s.ok then table.insert(fs, stage .. ":" .. (s.err or "?")) end
            end
            log.info("appstore_test", string.format("  %d. %s(%s) [%s]",
                i, f.name, f.aid, table.concat(fs, ", ")))
        end
    end
    log.info("appstore_test", "========================================")

    assert(failed_count == 0,
        string.format("%d/%d 个应用测试失败", failed_count, total))
end

	-- =================== 单 App 模式 (供外部编排器调用) ===================

	-- 从 /testresult/single_app.json 读取单个app信息, 执行4阶段测试, 结果写入 /testresult/result.json
	-- single_app.json 格式: {'aid':'xxx','url':'https://...','name':'显示名称'}
	-- result.json 格式: {'aid':'xxx','name':'xxx','passed':true/false,'stages':{...},'error':'...'}
	function M.test_single_app()
		log.info('appstore_test', '=== 单App测试模式 ===')

		-- 等待网络
		log.info('appstore_test', '等待网络就绪...')
		local ok_ip = sys.waitUntil('IP_READY', TIMEOUT.NETWORK_READY)
		if not ok_ip then
			local result = {aid = '?', name = '?', passed = false, stages = {}, error = '网络未就绪'}
			io.writeFile('/testresult/result.json', json.encode(result))
			log.error('appstore_test', '网络未就绪, 退出')
			os.exit(1)
		end
		log.info('appstore_test', '网络已就绪')

		-- 读取配置
		local cfg_raw = io.readFile('/testresult/single_app.json')
		if not cfg_raw then
			local result = {aid = '?', name = '?', passed = false, stages = {}, error = '无法读取 /testresult/single_app.json'}
			io.writeFile('/testresult/result.json', json.encode(result))
			log.error('appstore_test', result.error)
			os.exit(1)
		end
		local ok, cfg = pcall(json.decode, cfg_raw)
		if not ok or not cfg or not cfg.aid or not cfg.url then
			local result = {aid = cfg and cfg.aid or '?', name = cfg and cfg.name or '?', passed = false, stages = {}, error = 'single_app.json 格式无效: ' .. (ok and '缺少字段' or cfg)}
			io.writeFile('/testresult/result.json', json.encode(result))
			log.error('appstore_test', result.error)
			os.exit(1)
		end

		log.info('appstore_test', string.format('测试单应用: %s (aid=%s)', cfg.name or cfg.aid, cfg.aid))
		log.info('appstore_test', '  url=' .. cfg.url)

		-- 初始化 exapp (需要 AirUI + exwin)
		-- 参考 app_engine/factory/drv/lcd/lcd_common.lua 的 PC 初始化流程
		-- 1. lcd.init(custom, {w,h}) → PC 模拟器 SDL2 虚拟显示
		-- 2. airui.init(w, h) → AirUI/LVGL 渲染引擎
		-- 3. 设置 density_scale 等全局变量（app 代码依赖）
		if rtos and rtos.bsp and rtos.bsp() == "PC" then
			log.info("appstore_test", "PC模拟器: 初始化 LCD 480x854")
			if lcd and lcd.init then
				lcd.init("custom", {w = 480, h = 854})
			end
		end
		if airui and airui.init then
			airui.init(480, 854)
			-- factory 在 airui_init 里设置这些全局变量, 测试环境需手动设置
			_G.screen_w = 480
			_G.screen_h = 854
			_G.density_scale = 1.0
		end

		-- 预初始化 hzfont (PC内嵌字体)
		if hzfont and hzfont.init then
			hzfont.init()
		end

		-- 执行4阶段测试
		local r = test_one_app({aid = cfg.aid, url = cfg.url, title = cfg.name or cfg.aid, name = cfg.name or cfg.aid}, 1, 1)

		-- 写入结果
		local result = {
			aid = r.aid,
			name = r.name,
			passed = r.passed,
			stages = {},
			error = nil,
		}
		for stage, s in pairs(r.stages) do
			result.stages[stage] = {ok = s.ok, err = s.err}
			if not s.ok and not result.error then
				result.error = stage .. ': ' .. (s.err or '?')
			end
		end
		io.writeFile('/testresult/result.json', json.encode(result))
		log.info('appstore_test', string.format('结果已写入 /testresult/result.json (passed=%s)', tostring(r.passed)))

		-- 确保卸载 (如果还残留)
		local installed = exapp.list_installed()
		if installed[cfg.aid] then
			log.info('appstore_test', '最终清理: 卸载 ' .. cfg.aid)
			local received = false
			local handler = function(rx_aid, action, rx_success)
				if tostring(rx_aid) == cfg.aid and action == 'uninstall' then received = true end
			end
			sys.subscribe('APP_STORE_ACTION_DONE', handler)
			sys.publish('APP_STORE_UNINSTALL', cfg.aid, '全部', 'recommend')
			local ok = wait_until(function() return received end, TIMEOUT.UNINSTALL)
			sys.unsubscribe('APP_STORE_ACTION_DONE', handler)
		end

		-- 等待一下让日志刷出
		sys.wait(1000)
		log.info('appstore_test', '单App测试完成, 退出')
		os.exit(r.passed and 0 or 1)
	end

return M
