local function init()
    fskv.init()
    local isInit = fskv.get("isInit")
    log.info("cfg", isInit)
    if isInit then
        return
    end
    fskv.set("monitorIP1", "data.18gps.net")
    fskv.set("monitorPort1", 7018)
    fskv.set("monitorIP2", "124.71.128.165")
    fskv.set("monitorPort2", 7808)
    fskv.set("authCode1", "")
    fskv.set("authCode2", "")
    fskv.set("isInit", true)
    fskv.set("phoneList", {})
end

init()