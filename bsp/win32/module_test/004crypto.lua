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

local data_encrypt = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", "12345678901234 > 123456000000000", "1234567890123456")
log.info("AES", "aes-128-ecb encrypt", data_encrypt:toHex())
assert(data_encrypt:toHex():upper() == "A37DE67837A1A3006E47A7BC25AA0ECCEF744534DF0A80686810235A6450E2E2050187A0CDE5A9872CBAB091AB73E553", "AES aes-128-ecb encrypt error")

local data_decrypt = crypto.cipher_decrypt("AES-128-ECB", "PKCS7", data_encrypt, "1234567890123456")
log.info("AES", "aes-128-ecb decrypt", data_decrypt)
assert(data_decrypt:upper() == "12345678901234 > 123456000000000", "AES aes-128-ecb decrypt error")

local data2_encrypt = crypto.cipher_encrypt("AES-128-CBC", "PKCS7", "12345678901234 > 123456", "1234567890123456", "1234567890666666")
log.info("AES", "aes-128-cbc encrypt", data2_encrypt:toHex())
assert(data2_encrypt:toHex():upper() == "26D98EA512AE92BC487536B83F2BE99B467649A9700338F4B4FF75AA2654DD2C", "AES aes-128-cbc encrypt error")

local data2_decrypt = crypto.cipher_decrypt("AES-128-CBC", "PKCS7", data2_encrypt, "1234567890123456", "1234567890666666")
log.info("AES", "aes-128-cbc decrypt", data2_decrypt)
assert(data2_decrypt:upper() == "12345678901234 > 123456", "AES aes-128-cbc decrypt error")

local crc16 = crypto.crc16("IBM", "1234567890")
log.info("crc16", crc16)
assert(crc16 == 50554, "crc16 error")

local crc16_modbus = crypto.crc16_modbus("1234567890")
log.info("crc16_modbus", crc16_modbus)
assert(crc16_modbus == 49674, "crc16_modbus error")

local crc32 = crypto.crc32("1234567890")
log.info("crc32", crc32)
assert(crc32 == 639479525, "crc32 error")

local crc8 = crypto.crc8("1234567890", 0x31, 0xff, false)
log.info("crc8", crc8)
assert(crc8 == 208, "crc8 error")

local ts = 1646796576
local otp = crypto.totp("VK54ZXPO74ISEM2E", ts)
log.info("totp", otp)
assert(otp == 522113, "totp error")
