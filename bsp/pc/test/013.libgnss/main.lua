
_G.sys = require("sys")

PROJECT = "logtest"
VERSION = "1.0.0"

sys.taskInit(function()
    local tm = {
        year = 2023,
        month = 11,
        mon = 11,
        day = 22,
        hour = 15, 
        min = 30,
        sec = 44
    }
    local lla = {
        lat = "113.5",
        lng = "022.5"
    }
    log.info(">>", json.encode(os.date("!*t")))
    local aid = libgnss.casic_aid(tm, lla)
    log.info("AID", aid:toHex())
    -- BACE38000B010000000000605C400000000000803640000000000000000000000000D43A1341
    -- 0000000000000000000000000000000000000000F108 00 23         FD 23 B1 E5 
    -- BACE38000B010000000000605C400000000000803640000000000000000000000000D43A1341
    -- 0000000000000000000000000000000060FD0601F108 00 23         5D 21 B8 E6
    -- BACE38000B010000000000605C400000000000803640000000000000000000000000D43A1341
    -- 0000000000000000000000000000000000000000F108 00 23         FD 23 B1 E5

    local str = "$GNRMC,000625.00,A,3557.35652,N,13854.27058,E,1.681,73.98,111223,,,A,V*32\r\n"
    -- libgnss.init()
    libgnss.parse(str)
    log.info("GNSS", libgnss.getIntLocation())
    log.info("GNSS", 1.681 * 1852)
    log.info("GNSS", libgnss.getIntLocation(1))
    log.info("GNSS", libgnss.getIntLocation(2))
    log.info("GNSS", libgnss.getIntLocation(3))
end)

sys.run()
