export VIRTUAL_ENV  := env("VIRTUAL_ENV", ".venv")

export BIN := VIRTUAL_ENV + if os_family() == "unix" { "/bin" } else { "/Scripts" }
export PIP := BIN + if os_family() == "unix" { "/python -m pip" } else { "/python.exe -m pip" }

export DEFAULT_PYTHON := if os_family() == "unix" { `cat .python-version` } else { "python" }


# List available commands
default:
    @"{{ just_executable() }}" --list


# create a valid .env if none exists
_dotenv:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -f .env ]]; then
      echo "No '.env' file found; creating a default '.env' from 'dotenv-sample'"
      cp dotenv-sample .env
    fi


# Clean up temporary files
clean:
    rm -rf .venv


# Ensure valid virtualenv
virtualenv:
    #!/usr/bin/env bash
    set -euo pipefail

    # Allow users to specify python version in .env
    PYTHON_VERSION=${PYTHON_VERSION:-$DEFAULT_PYTHON}

    # Create venv; installs `uv`-managed python if python interpreter not found
    test -d $VIRTUAL_ENV || uv venv --python $PYTHON_VERSION

    # Block accidental usage of system pip by placing an executable at .venv/bin/pip
    echo 'echo "pip is not installed: use uv pip for a pip-like interface."' > .venv/bin/pip
    chmod +x .venv/bin/pip


# Ensure `uv.lock` satisfies the constraints in `pyproject.toml` and update `uv.lock` if not
# Does not automatically upgrade packages if existing versions meet constraints - see `upgrade` for that
# Does not install the dependencies into the venv - use `prodenv` or `devenv` instead for that
requirements *args:
    #!/usr/bin/env bash
    set -euo pipefail

    uv lock {{ args }}


# ensure prod requirements installed and up to date
prodenv:
    #!/usr/bin/env bash
    set -euo pipefail

    uv sync --no-dev


# && dependencies are run after the recipe has run. Needs just>=0.9.9. This is
# a killer feature over Makefiles.
#
# Ensure dev requirements installed and up to date
devenv: && install-precommit
    #!/usr/bin/env bash
    set -euo pipefail

    uv sync


# Ensure precommit is installed
install-precommit:
    #!/usr/bin/env bash
    set -euo pipefail

    BASE_DIR=$(git rev-parse --show-toplevel)
    test -f $BASE_DIR/.git/hooks/pre-commit || $BIN/pre-commit install

# Format a relative date into YYYY-MM-DDTHH:MM:SSZ format, or return the input unchanged if it is already in YYYY-MM-DD(THH:MM:SSZ) format
_format-date date:
    #!/usr/bin/env bash
    set -euo pipefail

    # Input format for relative dates depends on BSD vs GNU `date` command. BSD is the default for MacOS.
    if date -v1d >/dev/null 2>&1; then
        flag="-v" # BSD - see `man date` for usage; example '-7d'
    else
        flag="--date" # GNU - see `date --help` for usage; example '7 days ago'
    fi
    if [[ "{{ date }}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)?$ ]]; then
        echo "{{ date }}"
    else
        eval "date $flag '{{ date }}' +'%Y-%m-%dT%H:%M:%SZ'"
    fi

# Upgrade dependencies (specify package to upgrade single package, all by default)
# Use `update-dependencies` instead if you want to set a new global timestamp cutoff
# Package-specific timestamps should be set in pyproject.toml
upgrade package="": virtualenv
    #!/usr/bin/env bash
    set -euo pipefail

    if [ -z "{{ package }}" ]; then
        uv "lock" "--upgrade";
    else
        uv "lock" "--upgrade-package {{ package }}";
    fi

# Upgrade all dev and prod dependencies; see `_format-date` for date argument format
# This is the default input command to update-dependencies action
# https://github.com/bennettoxford/update-dependencies-action
update-dependencies date="7 days ago":
    #!/usr/bin/env bash
    set -euo pipefail

    export UV_EXCLUDE_NEWER=$(just _format-date "{{ date }}")
    if [ -n "$(grep "exclude-newer =" uv.lock)" ]; then
        LOCKFILE_TIMESTAMP=$(grep "exclude-newer =" uv.lock | cut -d'=' -f2 | cut -d'"' -f2)
        touch -d "$UV_EXCLUDE_NEWER" $VIRTUAL_ENV/.target
        touch -d "$LOCKFILE_TIMESTAMP" $VIRTUAL_ENV/.existing
        if [ $VIRTUAL_ENV/.existing -nt $VIRTUAL_ENV/.target ]; then
            echo "Ignoring date argument ($UV_EXCLUDE_NEWER) since it is earlier than the lockfile timestamp ($LOCKFILE_TIMESTAMP)."
            unset UV_EXCLUDE_NEWER
        else
            sed -i "s|^exclude-newer = .*|exclude-newer = \"$UV_EXCLUDE_NEWER\"|" pyproject.toml
        fi
    fi
    just upgrade

# *args is variadic, 0 or more. This allows us to do `just test -k match`, for example.
# Run the tests
test *args: devenv
    $BIN/coverage run --module pytest {{ args }}
    $BIN/coverage report || $BIN/coverage html


format *args=".": devenv
    $BIN/ruff format --check {{ args }}

lint *args=".": devenv
    $BIN/ruff check {{ args }}

# Run the various dev checks but does not change any files
# The lockfile check should occur before `devenv` gets run
check: && format lint
    #!/usr/bin/env bash
    set -euo pipefail

    # Make sure pyproject.toml and uv.lock are in sync in a fresh terminal
    unset UV_EXCLUDE_NEWER
    uv lock --check


# Fix formatting and import sort ordering
fix: devenv
    $BIN/ruff check --fix .
    $BIN/ruff format .


# Run the dev project
run: devenv
    echo "Not implemented yet"



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
