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


# Wrap `uv` commands that alter the lockfile
_uv command *args: virtualenv
    #!/usr/bin/env bash
    set -euo pipefail

    # Set global timestamp cutoff
    if [ -n "${UV_EXCLUDE_NEWER:-}" ]; then
        unset UV_EXCLUDE_NEWER
        echo "UV_EXCLUDE_NEWER environment variable ignored."
    fi
    LOCKFILE_TIMESTAMP=$(grep "exclude-newer =" uv.lock | cut -d'=' -f2 | cut -d'"' -f2 || echo "")
    GLOBAL_TIMESTAMP="${TARGET_TIMESTAMP:-$LOCKFILE_TIMESTAMP}"
    if [ -z ${GLOBAL_TIMESTAMP:-} ]; then
        echo 'No global timestamp found in the lockfile. Try setting a global timestamp via `just update-dependencies`.'
        exit 1
    fi
    opts="--exclude-newer $GLOBAL_TIMESTAMP"

    # Get package-specific timestamps from lockfile and set them
    if [ -n "$(grep "options.exclude-newer-package" uv.lock)" ]; then
        touch -d "$GLOBAL_TIMESTAMP" $VIRTUAL_ENV/.target
        while IFS= read -r line; do
            package="$(cut -d= -f1 <<< "$line" | xargs)"
            date="$(cut -d= -f2 <<< "$line" | xargs)"
            touch -d "$date" $VIRTUAL_ENV/.package
            if [ $VIRTUAL_ENV/.package -nt $VIRTUAL_ENV/.target ]; then
                opts="$opts --exclude-newer-package $package=$date"
            else
                echo "The cutoff for $package ($date) is older than the global cutoff and will no longer be specified."
            fi
        done < <(sed -n '/options.exclude-newer-package/,/^$/p' uv.lock | grep '=')
    fi

    uv {{ command }} $opts {{ args }}


# Ensure `uv.lock` satisfies the constraints in `pyproject.toml` and update `uv.lock` if not
# Does not automatically upgrade packages if existing versions meet constraints - see `upgrade` for that
# Does not install the dependencies into the venv - use `prodenv` or `devenv` instead for that
requirements *args: (_uv "lock" args)


# ensure prod requirements installed and up to date
prodenv: requirements
    uv sync --frozen --no-dev


# && dependencies are run after the recipe has run. Needs just>=0.9.9. This is
# a killer feature over Makefiles.
#
# Ensure dev requirements installed and up to date
devenv: requirements && install-precommit
    uv sync --frozen


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
upgrade package="" package-date="": virtualenv
    #!/usr/bin/env bash
    set -euo pipefail

    if [ -z "{{ package }}" ]; then
        just _uv "lock" "--upgrade";
    elif [ -z "{{ package-date }}" ]; then
        just _uv "lock" "--upgrade-package {{ package }}";
    else
        PACKAGE_TIMESTAMP=$(just _format-date "{{ package-date }}")
        just _uv "lock" "--upgrade-package {{ package }} --exclude-newer-package {{ package }}=$PACKAGE_TIMESTAMP"
    fi

# Upgrade all dev and prod dependencies; see `_format-date` for date argument format
# This is the default input command to update-dependencies action
# https://github.com/bennettoxford/update-dependencies-action
update-dependencies date:
    #!/usr/bin/env bash
    set -euo pipefail

    export TARGET_TIMESTAMP=$(just _format-date "{{ date }}")
    if [ -n "$(grep "exclude-newer =" uv.lock)" ]; then
        LOCKFILE_TIMESTAMP=$(grep "exclude-newer =" uv.lock | cut -d'=' -f2 | cut -d'"' -f2)
        touch -d "$TARGET_TIMESTAMP" $VIRTUAL_ENV/.target
        touch -d "$LOCKFILE_TIMESTAMP" $VIRTUAL_ENV/.existing
        if [ $VIRTUAL_ENV/.existing -nt $VIRTUAL_ENV/.target ]; then
            echo "Ignoring date argument ($TARGET_TIMESTAMP) since it is earlier than the lockfile timestamp ($LOCKFILE_TIMESTAMP)."
            unset TARGET_TIMESTAMP
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
check: (_uv "lock" "--check") format lint


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
