
sys = require "sys"

sys.taskInit(function()
    local str = "$GNRMC,005814.000,V,,,,,,,251123,,,M,V*24\r\n"
    libgnss.parse(str)
    log.info("rmc", json.encode(libgnss.getRmc(), "7f"))

    str = "$GNRMC,003657.000,A,2324.3944811,N,11313.8621125,E,0.430,43.152,020124,,,A,U*32\r\n"
    libgnss.parse(str)
    log.info("rmc", json.encode(libgnss.getRmc(), "7f"))

    print("==========================================================================")
    
    libgnss.clear()
    str, str2 = "$GNRMC,003657.000,A",",2324.3944811,N,11313.8621125,E,0.430,43.152,020124,,,A,U*32\r\n"
    libgnss.parse(str)
    libgnss.parse(str2)
    log.info("rmc分段传入", json.encode(libgnss.getRmc(), "7f"))
    libgnss.clear()
    
    libgnss.parse(str .. str2)
    log.info("rmc一次传入", json.encode(libgnss.getRmc(), "7f"))
    libgnss.clear()
end)

sys.run()

