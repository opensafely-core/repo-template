# ${GITHUB_REPOSITORY_NAME}

This is a template for an OpenSAFELY Core repository.

Put your project description here.

New repo checklist:
- [ ] Is this repo a package? If not, delete setup.py
- [ ] Does the repo require a Dockerfile?
  If not, delete:
  - Dockerfile -
  - .dockerignore
  - hadolint pre-commit hook from `.pre-commit-config.yaml`
  - `lint-dockerfile` action from `.github/workflows/main.yml`
- [ ] Update DEVELOPERS.md with any project-specific requirements and commands
- [ ] Update scripts


## Developer docs

Please see the [additional information](DEVELOPERS.md).
