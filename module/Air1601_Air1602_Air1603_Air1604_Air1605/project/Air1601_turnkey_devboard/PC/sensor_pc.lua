-- sensor_pc.lua - PC模拟器传感器模块(Air1601版本)

local sensor_pc = {}

function sensor_pc.init()
    log.info("sensor_pc", "PC模拟器传感器模块初始化")
end

function sensor_pc.read_all()
    return {
        temperature = 25.5,
        humidity = 60.0,
        air_quality = 150
    }
end

return sensor_pc
