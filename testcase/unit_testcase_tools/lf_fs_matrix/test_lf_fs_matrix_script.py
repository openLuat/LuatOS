import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parent
SCRIPTS = ROOT / "scripts"


class TestLfFsMatrixScript(unittest.TestCase):
    def test_matrix_scripts_exist_and_cover_three_fs(self):
        main_lua = SCRIPTS / "main.lua"
        test_lua = SCRIPTS / "lf_fs_matrix_test.lua"
        metas = SCRIPTS / "metas.json"

        self.assertTrue(main_lua.exists(), "main.lua is missing")
        self.assertTrue(test_lua.exists(), "lf_fs_matrix_test.lua is missing")
        self.assertTrue(metas.exists(), "metas.json is missing")

        content = test_lua.read_text(encoding="utf-8")
        self.assertIn('"lfs2"', content)
        self.assertIn('"lfsn"', content)
        self.assertIn('"pgfs"', content)
        self.assertIn("LF_FS_MATRIX_RESULT", content)


if __name__ == "__main__":
    unittest.main()
