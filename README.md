# ${GITHUB_REPOSITORY_NAME}

This is a template for an OpenSAFELY Core repository.

Put your project description here.

New repo checklist:
- [ ] Delete tests/template dir. These are tests for the template functionality, not the new project
- [ ] Does the repo require a Dockerfile?
  If not, delete:
  - the `docker/` directory
  - .dockerignore
  - hadolint pre-commit hook from `.pre-commit-config.yaml`
  - `lint-dockerfile` action from `.github/workflows/main.yml`
  If so:
  - run `grep -iR new-project docker` to find places where you need to insert information about your project
  - update the files in the `docker/` directory as needed
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
