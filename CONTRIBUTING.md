# Contributing

## Scope

Contributions are welcome for:
1. SSH control workflow reliability
2. PowerShell/WSL execution safety
3. File transfer and directory reporting improvements
4. Documentation and troubleshooting quality

## Development Flow

1. Create a feature branch from `main`.
2. Keep each PR focused on one problem.
3. Run local checks before PR:
   - `bash -n scripts/winctl.sh scripts/windows-dir-report.sh`
4. If behavior changes, update `README.md` and `SKILL.md`.
5. Open PR with:
   - problem and context
   - what changed
   - risk and rollback note

## Pull Request Criteria

1. CI must pass.
2. No private hosts, keys, tokens, or personal paths.
3. Default examples remain generic placeholders.
4. Security boundary is not weakened (least privilege guidance remains).

## Commit Convention

Recommended prefixes:
1. `feat:`
2. `fix:`
3. `docs:`
4. `chore:`
5. `refactor:`
