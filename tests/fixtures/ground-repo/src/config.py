"""Config loading for toy-service."""

DEFAULTS = {"port": 8080, "workers": 1}


def load_config(path):
    """Read `path` and return a dict merged over DEFAULTS.

    No validation happens here — an unknown key is passed straight through.
    """
    values = dict(DEFAULTS)
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition(":")
            values[key.strip()] = value.strip()
    return values
