# Contributing

Contributions should preserve the starter's small, framework-neutral surface.

## Before changing code

1. Read the relevant script, template, test, and architecture section.
2. Keep personal paths, private repositories, and machine configuration out of
   the public tree.
3. Add structure only when a demonstrated project need justifies it.

## Verification

Run:

```bash
bash -n \
  install.sh \
  bin/andx-continuity \
  bin/andx-project \
  skills/continuity/scripts/continuity-state.sh \
  tests/*.sh \
  tests/fixtures/*.sh

bash tests/run.sh
skills/continuity/scripts/continuity-state.sh audit
```

Validate the continuity skill with a compatible Agent Skills validator when
available.

## Pull requests

- Keep each contribution to one logical change. The maintained `main` branch
  has exactly one root commit; maintainers fold verified changes into that
  commit and update the branch with `--force-with-lease`.
- Explain the observable behavior changed.
- Include the executed checks and their results.
- Do not combine unrelated cleanup with a feature or fix.
- Never include credentials, private paths, or real secret values in fixtures.
