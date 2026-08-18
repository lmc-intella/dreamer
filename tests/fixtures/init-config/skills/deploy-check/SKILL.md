---
name: deploy-check
description: Pre-deploy sanity sweep. Use on "check the deploy", "is this safe to ship".
---

# deploy-check

Run `just build` and confirm the artefact hash matches the tag.

1. Confirm the tag exists.
2. Build.
3. Compare hashes.
