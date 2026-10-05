# Notes for developers

## System requirements

### just

Follow installation instructions from the [Just Programmer's Manual](https://just.systems/man/en/chapter_4.html) for your OS.

Add completion for your shell. E.g. for bash:
```
source <(just --completions bash)
```

Show all available commands
```
just #  shortcut for just --list
```

### uv

Follow installation instructions from the [uv documentation](https://docs.astral.sh/uv/getting-started/installation/) for your OS.

## Local development environment


Set up a local development environment with:
```
just devenv
```

## Dependency management
Dependencies are managed with `uv`.

### Overview
See the [uv documentation](https://docs.astral.sh/uv/concepts/projects/dependencies) for details on usage.

Changes to dependencies should be made via `uv` commands, or by modifying `pyproject.toml` directly followed by
[locking and syncing](https://docs.astral.sh/uv/concepts/projects/sync/) via `uv` or `just` commands like
`just devenv` or `just upgrade-all`. You should not modify `uv.lock` manually.

Note that `uv.lock` must be reproducible from `pyproject.toml`. Otherwise, `just check` will fail.

## Tests
Run the tests with:
```
just test <args>
```
