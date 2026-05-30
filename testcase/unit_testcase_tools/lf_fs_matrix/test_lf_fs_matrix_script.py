import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parent
SCRIPTS = ROOT / "scripts"


class TestLfFsMatrixScript(unittest.TestCase):
    def test_matrix_scripts_exist_and_cover_four_fs(self):
        main_lua = SCRIPTS / "main.lua"
        test_lua = SCRIPTS / "lf_fs_matrix_test.lua"
        metas = SCRIPTS / "metas.json"

        self.assertTrue(main_lua.exists(), "main.lua is missing")
        self.assertTrue(test_lua.exists(), "lf_fs_matrix_test.lua is missing")
        self.assertTrue(metas.exists(), "metas.json is missing")
        main_content = main_lua.read_text(encoding="utf-8")
        self.assertIn('rtos_bsp == "PC"', main_content)
        self.assertIn("os.exit(0)", main_content)

        content = test_lua.read_text(encoding="utf-8")
        self.assertIn('"lfs2"', content)
        self.assertIn('"lfsn"', content)
        self.assertIn('"pgfs"', content)
        self.assertIn('"lfs3"', content)
        self.assertIn("LF_FS_MATRIX_RESULT", content)
        self.assertIn("fs.fsstat", content)
        self.assertIn("space_ok", content)
        self.assertIn("required_fs", content)
        self.assertIn("bad_ratio", content)
        self.assertIn('fs == "lfsn" or fs == "pgfs"', content)
        self.assertIn("aes.obj", content)

    def test_ratio_runner_exists_and_has_three_bad_block_levels(self):
        runner = ROOT / "run_lf_fs_matrix_ratios.py"
        self.assertTrue(runner.exists(), "run_lf_fs_matrix_ratios.py is missing")
        content = runner.read_text(encoding="utf-8")
        self.assertIn("0.01", content)
        self.assertIn("0.05", content)
        self.assertIn("0.10", content)


if __name__ == "__main__":
    unittest.main()
