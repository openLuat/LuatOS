PROJECT = "EinkBook-LuatOS"
VERSION = "1.0.0"
MOD_TYPE = rtos.bsp()
log.info("MOD_TYPE", MOD_TYPE)
sys = require("sys")
require("sysplus")
wifiLib = require("wifiLib")


-- 兼容V1001固件的
if http == nil and http2 then
    http = http2
end


-- 兼容V1001固件的
if http == nil and http2 then
    http = http2
end

tag = "EINKBOOK"
-- 是否启用配网功能（配合esptouch使用）
USE_SMARTCONFIG = false
-- 这是已有的电纸书服务端地址，如果自己搭建或下面这个服务失效了，请修改
serverAdress = "http://47.96.229.157:2333/"
-- 改为需要连接的WiFi名称和密码（使用2.4Ghz频段，ESP32C3无法使用5GHz WiFi）
SSID, PASSWD = "Xiaomi_AX6000", "Air123456"

waitHttpTask, waitDoubleClick = false, false
einkPrintTime = 0
PAGE, gpage = "LIST", 1
onlineBooksTable, onlineBooksShowTable, onlineBooksShowTableTmp, einkBooksIndex, onlineBooksTableLen = {}, {}, {}, 1, 0
gBTN, gPressTime, gShortCb, gLongCb, gDoubleCb, gBtnStatus = 0, 1000, nil, nil, nil, "IDLE"

function printTable(tbl, lv)
    lv = lv and lv .. "\t" or ""
    print(lv .. "{")
    for k, v in pairs(tbl) do
        if type(k) == "string" then
            k = "\"" .. k .. "\""
        end
        if "string" == type(v) then
            local qv = string.match(string.format("%q", v), ".(.*).")
            v = qv == v and '"' .. v .. '"' or "'" .. v:toHex() .. "'"
        end
        if type(v) == "table" then
            print(lv .. "\t" .. tostring(k) .. " = ")
            printTable(v, lv)
        else

            print(lv .. "\t" .. tostring(k) .. " = " .. tostring(v) .. ",")
        end
    end
    print(lv .. "},")
end

function getTableSlice(intable, startIndex, endIndex)
    local outTable = {}
    for i = startIndex, endIndex do
        table.insert(outTable, intable[i])
    end
    return outTable
end

function getTableLen(t)
    local count = 0
    for _, _ in pairs(t) do
        count = count + 1
    end
    return count
end

function formatOnlineBooksTable(inTable)
    local outTable = {}
    local i = 1
    for k, v in pairs(inTable) do
        v["index"] = i
        table.insert(outTable, {
            [k] = v
        })
        i = i + 1
    end
    return outTable
end

function longTimerCb()
    gBtnStatus = "LONGPRESSED"
    gLongCb()
end

function btnHandle(val)
    if val == 0 then
        if waitDoubleClick == true then
            sys.timerStop(gShortCb)
            gDoubleCb()
            waitDoubleClick = false
            return
        end
        sys.timerStart(longTimerCb, gPressTime)
        gBtnStatus = "PRESSED"
    else
        sys.timerStop(longTimerCb)
        if gBtnStatus == "PRESSED" then
            sys.timerStart(gShortCb, 500)
            waitDoubleClick = true
            gBtnStatus = "IDLE"
        elseif gBtnStatus == "LONGPRESSED" then
            gBtnStatus = "IDLE"
        end
    end
end

function btnSetup(gpioNumber, pressTime, shortCb, longCb, doubleCb)
    gpio.setup(gpioNumber, btnHandle, gpio.PULLUP)
    gPressTime = pressTime
    gShortCb = shortCb
    gLongCb = longCb
    gDoubleCb = doubleCb
end

function showBookList(index)
    local firstIndex
    for k, v in pairs(onlineBooksShowTableTmp[1]) do
        firstIndex = v["index"]
    end
    if index > firstIndex + 10 then
        onlineBooksShowTableTmp = getTableSlice(onlineBooksShowTable, index - 10, index)
    end
    if index < firstIndex then
        onlineBooksShowTableTmp = getTableSlice(onlineBooksShowTable, index, index + 10)
    end
    einkShowStr(0, 16, "图书列表", 0, true)
    local ifShow = false
    local len = getTableLen(onlineBooksTable)
    local showLen = getTableLen(onlineBooksShowTableTmp)
    if len == 0 then
        einkShowStr(0, 32, "暂无在线图书", 0, false, true)
        return
    end
    local i = 1
    for k, v in pairs(onlineBooksShowTableTmp) do
        for name, info in pairs(v) do
            local bookName = string.split(name, ".")[1]
            local bookSize = tonumber(info["size"]) / 1024 / 1024
            if i == showLen then
                ifShow = true
            end
            if info["index"] == index then
                eink.rect(0, 16 * i, 200, 16 * (i + 1), 0, 1, nil, ifShow)
                einkShowStr(0, 16 * (i + 1), bookName .. "       " .. string.format("%.2f", bookSize) .. "MB", 1, nil,
                    ifShow)
            else
                einkShowStr(0, 16 * (i + 1), bookName .. "       " .. string.format("%.2f", bookSize) .. "MB", 0, nil,
                    ifShow)
            end
            i = i + 1
        end
    end
end

function showBook(bookName, bookUrl, page)
    sys.taskInit(function()
        waitHttpTask = true
        for i = 1, 3 do
            local code, headers, data = http.request("GET",bookUrl .. "/" .. page).wait()
            log.info("SHOWBOOK", code)
            if code ~= 200 then
                log.error("SHOWBOOK", "获取图书内容失败 ", data)
            else
                local bookLines = json.decode(data)
                for k, v in pairs(bookLines) do
                    if k == 1 then
                        einkShowStr(0, 16 * k, v, 0, true, false)
                    elseif k == #bookLines then
                        einkShowStr(0, 16 * k, v, 0, false, false)
                    else
                        einkShowStr(0, 16 * k, v, 0, false, false)
                    end
                end
                einkShowStr(60, 16 * 12 + 2, page .. "/" .. onlineBooksTable[bookName]["pages"], 0, false, true)
                break
            end
        end
        waitHttpTask = false
    end)
end

function btnShortHandle()
    if waitHttpTask == true then
        waitDoubleClick = false
        return
    end
    if PAGE == "LIST" then
        if einkBooksIndex == onlineBooksTableLen then
            einkBooksIndex = 1
        else
            einkBooksIndex = einkBooksIndex + 1
        end
        showBookList(einkBooksIndex)
    else
        local i = 1
        local bookName = nil
        for k, v in pairs(onlineBooksTable) do
            if i == einkBooksIndex then
                bookName = k
            end
            i = i + 1
        end
        local thisBookPages = tonumber(onlineBooksTable[bookName]["pages"])
        if thisBookPages == gpage then
            waitDoubleClick = false
            return
        end
        gpage = gpage + 1
        showBook(bookName, serverAdress .. string.urlEncode(bookName), gpage)
        log.info(bookName, gpage)
        fdb.kv_set(bookName, gpage)
    end
    waitDoubleClick = false
end

function btnLongHandle()
    if waitHttpTask == true then
        return
    end
    if PAGE == "LIST" then
        PAGE = "BOOK"
        local i = 1
        local bookName = nil
        for k, v in pairs(onlineBooksTable) do
            if i == einkBooksIndex then
                bookName = k
            end
            i = i + 1
        end
        local pageCache = fdb.kv_get(bookName)
        log.info(bookName, pageCache)
        if pageCache == nil then
            gpage = 1
            showBook(bookName, serverAdress .. string.urlEncode(bookName), gpage)
        else
            gpage = pageCache
            showBook(bookName, serverAdress .. string.urlEncode(bookName), pageCache)
        end

    elseif PAGE == "BOOK" then
        PAGE = "LIST"
        showBookList(einkBooksIndex)
    end
end

function btnDoublehandle()
    if waitHttpTask == true then
        return
    end
    if PAGE == "LIST" then
        if einkBooksIndex == 1 then
            einkBooksIndex = onlineBooksTableLen
        else
            einkBooksIndex = einkBooksIndex - 1
        end
        showBookList(einkBooksIndex)
    else
        if gpage == 1 then
            return
        end
        gpage = gpage - 1
        local i = 1
        local bookName = nil
        for k, v in pairs(onlineBooksTable) do
            if i == einkBooksIndex then
                bookName = k
            end
            i = i + 1
        end
        log.info(bookName, gpage)
        fdb.kv_set(bookName, gpage)
        showBook(bookName, serverAdress .. string.urlEncode(bookName), gpage)
    end
end

function einkShowStr(x, y, str, colored, clear, show)
    if einkPrintTime > 20 then
        einkPrintTime = 0
        eink.rect(0, 0, 200, 200, 0, 1)
        eink.show(0, 0, true)
        eink.rect(0, 0, 200, 200, 1, 1)
        eink.show(0, 0, true)
    end
    if clear == true then
        eink.clear()
    end
    eink.print(x, y, str, colored)
    if show == true then
        einkPrintTime = einkPrintTime + 1
        eink.show(0, 0, true)
    end
end

sys.taskInit(function()
    assert(fdb.kvdb_init("env", "onchip_flash") == true, tag .. ".kvdb_init ERROR")
    eink.model(eink.MODEL_1in54)
    if MOD_TYPE == "AIR101" then
        eink.setup(1, 0, 16, 19, 17, 20)
    elseif MOD_TYPE == "ESP32C3" then
        eink.setup(1, 2, 11, 10, 6, 7)
    end
    eink.setWin(200, 200, 0)
    eink.clear(0, true)
    eink.show(0, 0)
    eink.clear(1, true)
    eink.show(0, 0)
    -- eink.setFont(fonts.get("sarasa_regular_12"))
    eink.setFont(eink.font_opposansm12_chinese)

    if USE_SMARTCONFIG == true then
        einkShowStr(0, 16, "开机中 等待配网...", 0, false, true)
        local connectRes = wifiLib.connect()
        if connectRes == false then
            einkShowStr(0, 16, "配网失败 重启中...", 0, true, true)
            rtos.reboot()
        end
    else
        einkShowStr(0, 16, "开机中...", 0, false, true)
        local connectRes = wifiLib.connect(SSID, PASSWD)
        if connectRes == false then
            einkShowStr(0, 16, "联网失败 重启中...", 0, true, true)
            rtos.reboot()
        end
    end
    for i = 1, 5 do
        local code, headers, data = http.request("GET", serverAdress .. "getBooks").wait()
        log.info("SHOWBOOK", code)
        if code ~= 200 then
            log.error(tag, "获取图书列表失败 ", data)
            if i == 5 then
                einkShowStr(0, 16, "连接图书服务器失败 正在重启", 0, true, true)
                rtos.reboot()
            end
        else
            onlineBooksTable = json.decode(data)
            printTable(onlineBooksTable)
            onlineBooksTableLen = getTableLen(onlineBooksTable)
            onlineBooksShowTable = formatOnlineBooksTable(onlineBooksTable)
            onlineBooksShowTableTmp = getTableSlice(onlineBooksShowTable, 1, 11)
            showBookList(1)
            btnSetup(9, 1000, btnShortHandle, btnLongHandle, btnDoublehandle)
            break
        end
        sys.wait(1000)
    end
end)

sys.run()
