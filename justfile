# just has no idiom for setting an default value for an environment variable
# so we shell out, as we need VIRTUAL_ENV in the justfile environment
export VIRTUAL_ENV  := `echo ${VIRTUAL_ENV:-.venv}`

# TODO: make it /scripts on windows?
export BIN := VIRTUAL_ENV + "/bin"
export PIP := BIN + "/python -m pip"
# enforce our chosed pip compile flags
export COMPILE := BIN + "/pip-compile --allow-unsafe --generate-hashes"


# list available commands
default:
    @{{ just_executable() }} --list


# clean up temporary files
clean:
    rm -rf .venv


# ensure valid virtualenv
virtualenv:
    #!/usr/bin/env bash
    # allow users to specify python version in .env
    PYTHON_VERSION=${PYTHON_VERSION:-python3.9}
    # create venv and upgrade pip
    test -d $VIRTUAL_ENV || { $PYTHON_VERSION -m venv $VIRTUAL_ENV && $PIP install --upgrade pip; }
    # ensure we have pip-tools so we can run pip-compile
    test -e $BIN/pip-compile || $PIP install pip-tools


# update requirements.prod.txt if requirement.prod.in has changed
requirements-prod: virtualenv
    @test requirements.prod.in -ot requirements.prod.txt || $COMPILE --output-file=requirements.prod.txt requirements.prod.in


# update requirements.dev.txt if requirements.dev.in has changed
requirements-dev: virtualenv
    @test requirements.dev.in -ot requirements.dev.txt || $COMPILE --output-file=requirements.dev.txt requirements.dev.in


# ensure prod requirements installed and up to date
prodenv: requirements-prod
    #!/usr/bin/env bash
    # have the requirements changed since we last installed them?
    test requirements.prod.txt -nt $VIRTUAL_ENV/.prod || exit 0
    $PIP install -r requirements.prod.txt
    touch $VIRTUAL_ENV/.prod
    # force dev rebuild too
    touch requirements.dev.in


# && dependencies are run after the recipe has run. Needs just>=0.9.9
#
# ensure dev requirements installed and up to date
devenv: prodenv requirements-dev && install-precommit
    #!/usr/bin/env bash
    # have the requirements changed since we last installed them?
    test requirements.dev.txt -nt $VIRTUAL_ENV/.dev || exit 0
    $PIP install -r requirements.dev.txt
    touch $VIRTUAL_ENV/.dev


# ensure precommit is installed
install-precommit:
    #!/usr/bin/env bash
    BASE_DIR=$(git rev-parse --show-toplevel)
    test -f $BASE_DIR/.git/hooks/pre-commit || $BIN/pre-commit install


# upgrade dev or prod dependencies (all by default, specify package to upgrade single package)
upgrade env package="": virtualenv
    #!/usr/bin/env bash
    opts="--upgrade"
    test -z "{{ package }}" || opts="--upgrade-package {{ package }}"
    $COMPILE $opts --output-file=requirements.{{ env }}.txt requirements.{{ env }}.in


# *ARGS is variadic, 0 or more. This allows us to do `just test -k match`, for example.
# Run the tests
test *ARGS: devenv
    $BIN/python -m pytest --cov=. --cov-report html --cov-report term-missing:skip-covered {{ ARGS }}


# runs the format (black), sort (isort) and lint (flake8) check but does not change any files
check: devenv
    $BIN/black --check .
    $BIN/isort --check-only --diff .
    $BIN/flake8


# fix formatting and import sort ordering
fix: devenv
    $BIN/black .
    $BIN/isort .

# Run the dev project
run: devenv
    echo "Not implemented yet"
