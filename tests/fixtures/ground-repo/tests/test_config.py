from config import load_config


def test_load_config_applies_defaults(tmp_path):
    path = tmp_path / "cfg.txt"
    path.write_text("port: 9000\n", encoding="utf-8")
    assert load_config(str(path))["workers"] == 1
