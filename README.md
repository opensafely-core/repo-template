# ${GITHUB_REPOSITORY_NAME}

This is a template for an OpenSAFELY Core repository.

Put your project description here.

New repo checklist:
- [ ] Does the repo require a Dockerfile?
  - If not, delete:
    - Dockerfile -
    - .dockerignore
    - hadolint pre-commit hook from `.pre-commit-config.yaml`
    - `lint-dockerfile` action from `.github/workflows/main.yml`
  - If so, and if it's a python repo using `uv` for managing dependencies,
    add the following to your Dockerfile after python installation:
    ```dockerfile
    COPY --from=ghcr.io/astral-sh/uv:<commit sha of latest release> /uv /usr/local/bin/uv
    ENV UV_LINK_MODE=copy \
        UV_COMPILE_BYTECODE=1 \
        UV_PYTHON_DOWNLOADS=never \
        UV_PYTHON=python< python version (e.g. 3.10) > \
        UV_PROJECT_ENVIRONMENT="/opt/venv"

    RUN uv venv
    ENV VIRTUAL_ENV=/opt/venv/ PATH="/opt/venv/bin:$PATH"

    COPY pyproject.toml /tmp/pyproject.toml
    COPY uv.lock /tmp/uv.lock

    # DL3042: using cache mount instead
    # hadolint ignore=DL3042
    RUN --mount=type=cache,target=/root/.cache/uv \
        uv sync  --frozen --no-dev --no-install-project --directory /tmp
    ```
    - For creating dev images, remove the `--no-dev` flag from the `RUN` command.
- [ ] Is this a Django project?
  If so, you probably need to add the following per-file ignores to `.flake8`
  ```
  per-file-ignores =
    manage.py:INP001
    gunicorn.conf.py:INP001
  ```
- [ ] Update DEVELOPERS.md with any project-specific requirements and commands
- [ ] Update commands in `justfile`


## Developer docs

Please see the [additional information](DEVELOPERS.md).
