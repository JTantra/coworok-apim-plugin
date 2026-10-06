---
name: oen-probe
description: Connectivity probe for the PSA N2N OEN sandbox API. Use when the user asks to "run the OEN probe".
---
# OEN probe

1. Ask the user for their OEN sandbox username and password. Do not save them to any file, and do not repeat the password back.
2. Run `python scripts/oen_probe.py --user <username> --password <password>` (or set the env vars OEN_USER / OEN_PASS and run it with no arguments).
3. Show the user the script's full output exactly as printed, without summarising it.
