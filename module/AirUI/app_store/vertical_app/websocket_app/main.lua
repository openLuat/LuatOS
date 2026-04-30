PROJECT = "WEBSOCKET_TOOL"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

require "websocket_app"
require "websocket_win"

sys.publish("OPEN_WEBSOCKET_WIN")

sys.run()