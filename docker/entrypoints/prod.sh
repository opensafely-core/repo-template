#!/bin/bash
set -euo pipefail

# At the moment the command is simply executed;
# but any commands that should be run beforehand can be added here
# (e.g. ./manage.py check or ./manage.py migrate)

exec "$@"
