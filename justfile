# list available commands
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


# ensure prod requirements installed and up to date
prodenv:
    uv sync --no-dev


# && dependencies are run after the recipe has run. Needs just>=0.9.9. This is
# a killer feature over Makefiles.
#
# ensure dev requirements installed and up to date
devenv: && install-precommit
    uv sync --inexact


# ensure precommit is installed
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


# Upgrade all dev and prod dependencies.
# This is the default input command to update-dependencies action
# https://github.com/bennettoxford/update-dependencies-action
update-dependencies:
    just upgrade-all

# *args is variadic, 0 or more. This allows us to do `just test -k match`, for example.
# Run the tests
test *args:
    uv run coverage run --module pytest {{ args }}
    uv run coverage report || uv run coverage html


format *args=".":
    uv run ruff format --check {{ args }}

lint *args=".":
    uv run ruff check {{ args }}

# run the various dev checks but does not change any files
check: format lint


# fix formatting and import sort ordering
fix:
    uv run ruff check --fix .
    uv run ruff format .


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
