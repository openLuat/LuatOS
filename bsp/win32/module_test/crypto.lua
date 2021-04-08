local md5 = crypto.md5("abc")
log.info("md5 result",md5)
assert(md5:upper() == "900150983CD24FB0D6963F7D28E17F72","md5 error")

--todo

