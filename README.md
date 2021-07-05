# ${GITHUB_REPOSITORY_NAME}

This is a template for an OpenSAFELY Core repository.

Put your project description here.

New repo checklist:
- [ ] Does the repo require a Dockerfile?
  If not, delete:
  - Dockerfile -
  - .dockerignore
  - hadolint pre-commit hook from `.pre-commit-config.yaml`
  - `lint-dockerfile` action from `.github/workflows/main.yml`
- [ ] Update DEVELOPERS.md with any project-specific requirements and commands
- [ ] Update commands in `justfile`


## Developer docs

Please see the [additional information](DEVELOPERS.md).
