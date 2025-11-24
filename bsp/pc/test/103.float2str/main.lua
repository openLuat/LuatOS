


local data = 6234567
log.info("data", data)
log.info("data %.2f", string.format("%.2f", data))
log.info("data %.3f", string.format("%.3f", data * 0.1))

log.info("data", string.format("%.3f", data * 0.1):toHex())
log.info("data", tostring(data * 0.1):toHex())
log.info("data", "[" .. tostring(data * 0.1) .. "]")