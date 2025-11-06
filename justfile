set dotenv-load := true

# List available commands
default:
    @"{{ just_executable() }}" --list

# Create a valid .env if none exists
_dotenv:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -f .env ]]; then
      echo "No '.env' file found; creating a default '.env' from 'dotenv-sample'"
      cp dotenv-sample .env
    fi

# Check if a .env exists
# Use this (rather than _dotenv or devenv) for recipes that require that a .env file exists.
# just will not pick up environment variables from a .env that it's just created,
# and there isn't an easy way to load those into the environment, so we just

# prompt the user to run just devenv to set up their local environment properly.
_checkenv:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -f .env ]]; then
        echo "No '.env' file found; run 'just devenv' to create one"
        exit 1
    fi

# Clean up temporary files
clean:
    rm -rf .venv

# Install production requirements into and remove extraneous packages from venv
prodenv:
    uv sync --no-dev

# && dependencies are run after the recipe has run. Needs just>=0.9.9. This is
# a killer feature over Makefiles.
#

# Install dev requirements into venv without removing extraneous packages
devenv: _dotenv && install-precommit
    uv sync --inexact

# Ensure precommit is installed
install-precommit:
    #!/usr/bin/env bash
    set -euo pipefail

    BASE_DIR=$(git rev-parse --show-toplevel)
    test -f $BASE_DIR/.git/hooks/pre-commit || uv run pre-commit install

# Upgrade a single package to the latest version as of the cutoff in pyproject.toml
upgrade-package package: && devenv
    uv lock --upgrade-package {{ package }}

# Upgrade all packages to the latest versions as of the cutoff in pyproject.toml
upgrade-all: && devenv
    uv lock --upgrade

# Move the cutoff date in pyproject.toml to N days ago (default: 7) at midnight UTC
bump-uv-cutoff days="7":
    #!/usr/bin/env -S uvx --with tomlkit python3.13
    # Note we specify the python version here and we don't care if it's different to
    # the .python-version; we need 3.11+ for the datetime code used.

    import datetime
    import tomlkit

    with open("pyproject.toml", "rb") as f:
        content = tomlkit.load(f)

    new_datetime = (
        datetime.datetime.now(datetime.UTC) - datetime.timedelta(days=int("{{ days }}"))
    ).replace(hour=0, minute=0, second=0, microsecond=0)
    new_timestamp = new_datetime.strftime("%Y-%m-%dT%H:%M:%SZ")
    if existing_timestamp := content["tool"]["uv"].get("exclude-newer"):
        if new_datetime < datetime.datetime.fromisoformat(existing_timestamp):
            print(
                f"Existing cutoff {existing_timestamp} is more recent than {new_timestamp}, not updating."
            )
            exit(0)
    content["tool"]["uv"]["exclude-newer"] = new_timestamp

    with open("pyproject.toml", "w") as f:
        tomlkit.dump(content, f)

# This is the default input command to update-dependencies action
# https://github.com/bennettoxford/update-dependencies-action

# Bump the timestamp cutoff to midnight UTC 7 days ago and upgrade all dependencies
update-dependencies: bump-uv-cutoff upgrade-all

# *args is variadic, 0 or more. This allows us to do `just test -k match`, for example.

# Run the tests
test *args:
    uv run coverage run --module pytest {{ args }}
    uv run coverage report || uv run coverage html

format *args:
    uv run ruff format --diff --quiet {{ args }} .

lint *args:
    uv run ruff check {{ args }} .

lint-actions:
    docker run --rm -v $(pwd):/repo:ro --workdir /repo rhysd/actionlint:1.7.8 -color

# Run the various dev checks but does not change any files
check:
    #!/usr/bin/env bash
    set -euo pipefail

    failed=0

    check() {
      echo -e "\e[1m=> ${1}\e[0m"
      rc=0
      # Run it
      eval $1 || rc=$?
      # Increment the counter on failure
      if [[ $rc != 0 ]]; then
        failed=$((failed + 1))
        # Add spacing to separate the error output from the next check
        echo -e "\n"
      fi
    }

    check "just check-lockfile"
    check "just format"
    check "just lint"
    check "just lint-actions"
    test -d docker/ && check "just docker/lint"

    if [[ $failed > 0 ]]; then
      echo -en "\e[1;31m"
      echo "   $failed checks failed"
      echo -e "\e[0m"
      exit 1
    fi

# validate uv.lock
check-lockfile:
    #!/usr/bin/env bash
    set -euo pipefail
    # Make sure dates in pyproject.toml and uv.lock are in sync
    unset UV_EXCLUDE_NEWER
    rc=0
    uv lock --check || rc=$?
    if test "$rc" != "0" ; then
        echo "Timestamp cutoffs in uv.lock must match those in pyproject.toml. See DEVELOPERS.md for details and hints." >&2
        exit $rc
    fi

# Fix formatting, import sort ordering, and justfile
fix:
    uv run ruff check --fix .
    uv run ruff format .
    just --fmt --unstable

# Run the dev project
run: devenv
    echo "Not implemented yet"
    # E.g. uv run python manage.py runserver
    # Note: devenv prerequisite can be removed if using uv run

# Remove built assets and collected static files
assets-clean:
    rm -rf assets/dist
    rm -rf staticfiles

# Install the Node.js dependencies
assets-install:
    #!/usr/bin/env bash
    set -euo pipefail

    # Exit if lock file has not changed since we installed them. -nt == "newer than",
    # but we negate with || to avoid error exit code
    test package-lock.json -nt node_modules/.written || exit 0

    npm ci
    touch node_modules/.written

# Build the Node.js assets
assets-build:
    #!/usr/bin/env bash
    set -euo pipefail

    # Find files which are newer than dist/.written in the src directory. grep
    # will exit with 1 if there are no files in the result.  We negate this
    # with || to avoid error exit code
    # We wrap the find in an if in case dist/.written is missing so we don't
    # trigger a failure prematurely
    if test -f assets/dist/.written; then
        find assets/src -type f -newer assets/dist/.written | grep -q . || exit 0
    fi

    npm run build
    touch assets/dist/.written

assets: assets-install assets-build

assets-rebuild: assets-clean assets
