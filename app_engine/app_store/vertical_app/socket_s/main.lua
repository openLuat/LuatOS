PROJECT = "SOCKET_TOOL"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

require "socket_server_win"

sys.publish("OPEN_SOCKET_WIN")

sys.run()
