local md5 = crypto.md5("abc")
log.info("md5 result",md5)
assert(md5:upper() == "900150983CD24FB0D6963F7D28E17F72","md5 error")

local sha1 = crypto.sha1("abc")
log.info("sha1 result",sha1)
assert(sha1:upper() == "A9993E364706816ABA3E25717850C26C9CD0D89D","sha1 error")

local sha256 = crypto.sha256("abc")
log.info("sha256 result",sha256)
assert(sha256:upper() == "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD","sha256 error")

local sha512 = crypto.sha512("abc")
log.info("sha512 result",sha512)
assert(sha512:upper() == "DDAF35A193617ABACC417349AE20413112E6FA4E89A97EA20A9EEEE64B55D39A2192992A274FC1A836BA3C23A3FEEBBD454D4423643CE80E2A9AC94FA54CA49F","sha512 error")



--todo
