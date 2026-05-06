PROJECT = "CARD_DUEL"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "card_duel_win"
sys.publish("OPEN_CARD_DUEL_WIN")

sys.run()
