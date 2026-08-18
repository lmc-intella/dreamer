# toy-service

A four-file fixture repo for tests/ground.bats and for the worked example in
skills/plan/SKILL.md. It loads a YAML-ish config from disk and serves it.

There is no schema validation yet: `load_config` returns whatever keys the file
happened to contain, and `Service.start` trusts them.
