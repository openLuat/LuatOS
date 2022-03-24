local testsfud = {}

local sys = require "sys"

sys.taskInit(function()
    --根据实际设备选取不同的spi以及配置
    local spi_flash = spi.deviceSetup(1,pin.PA07,0,0,8,10*1000*1000,spi.MSB,1,0)
    log.info("sfud.init",sfud.init(spi_flash))
    log.info("sfud.getDeviceNum",sfud.getDeviceNum())
    local sfud_device = sfud.getDeviceTable()
    log.info("sfud.write",sfud.write(sfud_device,1024,"sfud"))
    log.info("sfud.read",sfud.read(sfud_device,1024,4))
    log.info("sfud.mount",sfud.mount(sfud_device,"/sfud"))
    log.info("fsstat", fs.fsstat("/sfud"))
    while 1 do
        sys.wait(1000)
    end
end)

return testsfud