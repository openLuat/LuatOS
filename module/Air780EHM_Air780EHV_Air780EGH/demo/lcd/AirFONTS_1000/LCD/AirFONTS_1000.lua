local AirFONTS_1000 = {}

--初始化AirFONTS_1000的SPI配置
--AirFONTS_1000通过SPI接口（SCK CS MOSI MISO）和主控相连
--主控设备为SPI主设备，AirFONTS_1000为SPI从设备

--spi_id：number类型；
--     表示主设备的SPI ID；
--     取值范围：主控产品上有效的SPI ID值，例如Air8101上的取值范围为0和1；
--     如果没有传入此参数或者传入了nil，则使用默认值0；
--spi_cs：number类型；
--     表示cs引脚的GPIO ID；
--     取值范围：主控产品上有效的GPIO ID值，例如Air8101上的取值范围为0到9,12,14到55；
--     如果没有传入此参数或者传入了nil，则使用默认值8；

--返回值：成功返回true，失败返回false
function AirFONTS_1000.init(spi_id, spi_cs)
    --创建一个SPI设备对象
    AirFONTS_1000.spi_gtfont = spi.deviceSetup(spi_id or 0, spi_cs or 8, 0, 0, 8, 20*1000*1000, spi.MSB, 1, 0)
    log.error("AirFONTS_1000.init", "spi.deviceSetup", type(AirFONTS_1000.spi_gtfont))
    --检查SPI设备对象是否创建成功
    if type(AirFONTS_1000.spi_gtfont) ~= "userdata" then
        log.error("AirFONTS_1000.init", "spi.deviceSetup error", type(AirFONTS_1000.spi_gtfont))
        return false
    end

    --初始化矢量字库
    if not gtfont.init(AirFONTS_1000.spi_gtfont) then
        log.error("AirFONTS_1000.init", "gtfont.init error")
        return false
    end

    return true
end

return AirFONTS_1000