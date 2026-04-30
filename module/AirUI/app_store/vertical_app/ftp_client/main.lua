PROJECT = "FTP_CLIENT"
VERSION = "001.999.001"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "ftp_client_win"

sys.publish("OPEN_FTP_CLIENT_WIN")

sys.run()