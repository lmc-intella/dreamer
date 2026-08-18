"""The service entry point."""

from config import load_config


class Service:
    def __init__(self, config):
        self.config = config

    def start(self):
        port = int(self.config["port"])
        return f"listening on {port}"


def main(path):
    return Service(load_config(path)).start()
