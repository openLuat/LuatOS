local md5 = crypto.md5("abc")
log.info("md5 result",md5)
assert(md5:upper() == "900150983CD24FB0D6963F7D28E17F72","md5 error")

local hmac_md5 = crypto.hmac_md5("abc", "1234567890")
log.info("hmac_md5 result",hmac_md5)
assert(hmac_md5:upper() == "416478FC0ACE1C4AB37F85F4F86A16B1","hmac_md5 error")

local sha1 = crypto.sha1("abc")
log.info("sha1 result",sha1)
assert(sha1:upper() == "A9993E364706816ABA3E25717850C26C9CD0D89D","sha1 error")

local hmac_sha1 = crypto.hmac_sha1("abc", "1234567890")
log.info("hmac_sha1 result",hmac_sha1)
assert(hmac_sha1:upper() == "DAE54822C0DAF6C115C97B0AD62C7BCBE9D5E6FC","hmac_md5 error")

local sha256 = crypto.sha256("abc")
log.info("sha256 result",sha256)
assert(sha256:upper() == "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD","sha256 error")

local hmac_sha256 = crypto.hmac_sha256("abc", "1234567890")
log.info("hmac_sha256 result",hmac_sha256)
assert(hmac_sha256:upper() == "86055184805B4A466A7BE398FF4A7159F9055EA7EEF339FC94DCEC6F165898BA","hmac_sha256 error")

local sha512 = crypto.sha512("abc")
log.info("sha512 result",sha512)
assert(sha512:upper() == "DDAF35A193617ABACC417349AE20413112E6FA4E89A97EA20A9EEEE64B55D39A2192992A274FC1A836BA3C23A3FEEBBD454D4423643CE80E2A9AC94FA54CA49F","sha512 error")

local hmac_sha512 = crypto.hmac_sha512("abc", "1234567890")
log.info("hmac_sha512 result",hmac_sha512)
assert(hmac_sha512:upper() == "0F92B9AC88949E0BF7C9F1E6F9901BAB8EDFDC9E561DFDE428BC4339961A0569AD01B44343AA56E439949655D15C4D28492D459E75015489920243F3C9986F2A","hmac_sha512 error")


--todo
