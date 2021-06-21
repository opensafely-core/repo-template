help:
	@echo "Usage:"
	@echo "    make help             prints this help."
	@echo "    make check            runs the format (black), sort (isort) and lint (flake8) check but does not change any files"
	@echo "    make fix              fix formatting and import sort ordering."
	@echo "    make setup            set up/update the local dev env."
	@echo "    make run              run the dev project."
	@echo "    make test             run the test suite."

.PHONY: check
check:
	@echo "Running black" && \
		black --check . \
		isort --check-only --diff . \
		flake8 \
		|| exit 1

.PHONY: fix
fix:
	black .
	isort .


.PHONY: setup
setup:
	pip install --require-hashes -r requirements.dev.txt
	pre-commit install

.PHONY: run
run:

.PHONY: test
test:
