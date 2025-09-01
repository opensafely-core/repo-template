export VIRTUAL_ENV  := env("VIRTUAL_ENV", ".venv")

export BIN := VIRTUAL_ENV + if os_family() == "unix" { "/bin" } else { "/Scripts" }
export PIP := BIN + if os_family() == "unix" { "/python -m pip" } else { "/python.exe -m pip" }

export DEFAULT_PYTHON := if os_family() == "unix" { `cat .python-version` } else { "python" }


# list available commands
default:
    @"{{ just_executable() }}" --list


# clean up temporary files
clean:
    rm -rf .venv


# ensure valid virtualenv
virtualenv *args:
    #!/usr/bin/env bash
    set -euo pipefail

    # allow users to specify python version in .env
    PYTHON_VERSION=${PYTHON_VERSION:-$DEFAULT_PYTHON}

    # Create venv; installs `uv`-managed python if python interpreter not found
    test -d $VIRTUAL_ENV || uv venv --python $PYTHON_VERSION {{ args }}

    # Block accidentally usage of system pip by placing an executable at .venv/bin/pip
    echo 'echo "pip is not installed: use uv pip for a pip-like interface."' > .venv/bin/pip
    chmod +x .venv/bin/pip


# Wrap `uv` commands that alter the lockfile
_uv command +args: virtualenv
    #!/usr/bin/env bash
    set -euo pipefail

    # Set global timestamp cutoff
    if [ -n "$(grep "exclude-newer =" uv.lock)" ]; then
        LOCKFILE_TIMESTAMP=$(grep -n "exclude-newer =" uv.lock | cut -d'=' -f2 | cut -d'"' -f2)
    fi
    if [ -z "${UV_EXCLUDE_NEWER:-}" ] && [ -z "${LOCKFILE_TIMESTAMP:-}" ]; then
        echo 'No global timestamp found in the lockfile and UV_EXCLUDE_NEWER is not provided. Try setting a global timestamp via `just update-dependencies`.'
        exit 1
    elif [ -n "${UV_EXCLUDE_NEWER:-}" ] && [ -z "${LOCKFILE_TIMESTAMP:-}" ]; then
        echo "Global cutoff set to $UV_EXCLUDE_NEWER."
        GLOBAL_TIMESTAMP=$UV_EXCLUDE_NEWER
    elif [ -z "${UV_EXCLUDE_NEWER:-}" ] && [ -n "${LOCKFILE_TIMESTAMP:-}" ]; then
        GLOBAL_TIMESTAMP=$LOCKFILE_TIMESTAMP
    else
        touch -d "$UV_EXCLUDE_NEWER" $VIRTUAL_ENV/.target
        touch -d "$LOCKFILE_TIMESTAMP" $VIRTUAL_ENV/.existing
        if [ $VIRTUAL_ENV/.existing -nt $VIRTUAL_ENV/.target ]; then
            echo "Global cutoff set to lockfile timestamp ($LOCKFILE_TIMESTAMP) since it is newer than $UV_EXCLUDE_NEWER."
            GLOBAL_TIMESTAMP=$LOCKFILE_TIMESTAMP
        else
            echo "Global cutoff set to $UV_EXCLUDE_NEWER."
            GLOBAL_TIMESTAMP=$UV_EXCLUDE_NEWER
        fi
    fi
    unset UV_EXCLUDE_NEWER
    opts="--exclude-newer $GLOBAL_TIMESTAMP"

    # Get package-specific timestamps from lockfile and set them
    if [ -n "$(grep "options.exclude-newer-package" uv.lock)" ]; then
        touch -d "$GLOBAL_TIMESTAMP" $VIRTUAL_ENV/.target
        while IFS= read -r line; do
            package="$(echo "${line%%=*}" | xargs)"
            date="$(echo "${line#*=}" | xargs)"
            touch -d "$date" $VIRTUAL_ENV/.package
            if [ $VIRTUAL_ENV/.package -nt $VIRTUAL_ENV/.target ]; then
                opts="$opts --exclude-newer-package $package=$date"
            else
                echo "The cutoff for $package ($date) is older than the global cutoff and will no longer be specified."
            fi
        done < <(sed -n '/options.exclude-newer-package/,/^$/p' uv.lock | grep '=')
    fi

    uv {{ command }} $opts {{ args }} || exit 1


# update uv.lock if dependencies in pyproject.toml have changed
requirements *args: (_uv "lock" args)


# ensure prod requirements installed and up to date
prodenv: requirements
    uv sync --frozen --no-dev


# && dependencies are run after the recipe has run. Needs just>=0.9.9. This is
# a killer feature over Makefiles.
#
# ensure dev requirements installed and up to date
devenv: requirements && install-precommit
    uv sync --frozen


# ensure precommit is installed
install-precommit:
    #!/usr/bin/env bash
    set -euo pipefail

    BASE_DIR=$(git rev-parse --show-toplevel)
    test -f $BASE_DIR/.git/hooks/pre-commit || $BIN/pre-commit install


# upgrade dependencies (specify package to upgrade single package, all by default)
@upgrade package="" package-date="": virtualenv
    if [ -z "{{ package }}" ]; then \
        just _upgrade-all; \
    elif [ -n "${UV_EXCLUDE_NEWER:-}" ] && [ -n "{{ package }}" ]; then \
        echo "Global timestamp set via UV_EXCLUDE_NEWER for single package upgrade; exiting since intention is unclear." && exit 1; \
    else \
        just _upgrade-package {{ package }} "{{ package-date }}"; \
    fi

@_upgrade-all:
    just _uv "lock" "--upgrade"

@_upgrade-package package package-date="":
    if [ -z "{{ package-date }}" ]; then \
        just _uv "lock" "--upgrade-package {{ package }}"; \
    else \
        just _uv "lock" "--upgrade-package {{ package }} --exclude-newer-package {{ package }}=$(date -d "{{ package-date }}" +"%Y-%m-%dT%H:%M:%SZ")"; \
    fi

# Upgrade all dev and prod dependencies.
# This is the default input command to update-dependencies action
# https://github.com/bennettoxford/update-dependencies-action
@update-dependencies  date="":
    if [ -n "${UV_EXCLUDE_NEWER:-}" ] && [ -n "{{ date }}" ]; then \
        echo "Global timestamp set via UV_EXCLUDE_NEWER in addition to date argument; exiting since intention is unclear." && exit 1; \
    elif [ -z "${UV_EXCLUDE_NEWER:-}" ] && [ -n "{{ date }}" ]; then \
        UV_EXCLUDE_NEWER=$(date -d "{{ date }}" +"%Y-%m-%dT%H:%M:%SZ") just _upgrade-all; \
    else \
        just _upgrade-all; \
    fi

# *args is variadic, 0 or more. This allows us to do `just test -k match`, for example.
# Run the tests
test *args: devenv
    $BIN/coverage run --module pytest {{ args }}
    $BIN/coverage report || $BIN/coverage html


format *args=".": devenv
    $BIN/ruff format --check {{ args }}

lint *args=".": devenv
    $BIN/ruff check {{ args }}

# run the various dev checks but does not change any files
check: format lint


# fix formatting and import sort ordering
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

    # exit if lock file has not changed since we installed them. -nt == "newer than",
    # but we negate with || to avoid error exit code
    test package-lock.json -nt node_modules/.written || exit 0

    npm ci
    touch node_modules/.written


# Build the Node.js assets
assets-build:
    #!/usr/bin/env bash
    set -euo pipefail

    # find files which are newer than dist/.written in the src directory. grep
    # will exit with 1 if there are no files in the result.  We negate this
    # with || to avoid error exit code
    # we wrap the find in an if in case dist/.written is missing so we don't
    # trigger a failure prematurely
    if test -f assets/dist/.written; then
        find assets/src -type f -newer assets/dist/.written | grep -q . || exit 0
    fi

    npm run build
    touch assets/dist/.written


assets: assets-install assets-build


assets-rebuild: assets-clean assets
