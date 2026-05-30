import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
SPI_PC = ROOT / "bsp" / "pc" / "port" / "driver" / "luat_spi_pc.c"


class TestPcVnandOobModel(unittest.TestCase):
    def test_pc_vnand_uses_independent_oob_storage(self):
        content = SPI_PC.read_text(encoding="utf-8")
        self.assertIn("uint32_t oob_size;", content)
        self.assertIn("uint8_t* oob;", content)
        self.assertIn("uint8_t* cache_oob;", content)
        self.assertIn("LUAT_PC_NAND_DEFAULT_OOB_SIZE", content)
        self.assertIn("LUAT_PC_NAND_OOB_SIZE", content)
        self.assertIn("pc_vnand_mark_bad_block_oob", content)
        self.assertIn("pos < (sim->page_size + sim->oob_size)", content)


if __name__ == "__main__":
    unittest.main()
