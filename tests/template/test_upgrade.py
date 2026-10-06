import os
import subprocess
import tomllib
from datetime import UTC, datetime, timedelta
from pathlib import Path


def load_packages(project_dir):
    lock_path = project_dir / "uv.lock"
    lock_data = tomllib.loads(lock_path.read_text())
    return {entry["name"]: entry["version"] for entry in lock_data.get("package", [])}


def assert_locked_version(project_dir: Path, package: str, version: str) -> str:
    packages = load_packages(project_dir)
    mirror_data = project_dir / "requirements.uvmirror.txt"

    assert packages[package] == version
    assert f"{package}=={version}" in mirror_data.read_text()


def test_upgrade_all(project_copy: Path, local_index) -> None:
    """Functional test of `upgrade all` just command."""
    current_version = load_packages(project_copy)["coverage"]
    new_major = int(current_version.split(".")[0]) + 1
    target_version = f"{new_major}.0.0"

    env = {
        **os.environ,
        "UV_INDEX_URL": local_index.url,
        "UV_DEFAULT_INDEX": local_index.url,
        "UV_EXTRA_INDEX_URL": "",
    }

    # verify current version
    assert_locked_version(project_copy, "coverage", current_version)

    # no new packages in our index, so should be no change
    subprocess.run(["just", "upgrade-all"], cwd=project_copy, env=env, check=True)
    assert_locked_version(project_copy, "coverage", current_version)

    # Default cooldown is 7 days ago from now
    now = datetime.now(tz=UTC)

    # add new version to index, one day newer than the exclude date.
    local_index.add_package("coverage", target_version, now - timedelta(days=6))
    subprocess.run(["just", "upgrade-all"], cwd=project_copy, env=env, check=True)
    # should not be upgraded, as is newer
    assert_locked_version(project_copy, "coverage", current_version)

    # add new version to index, one day earlier than the exclude date.
    local_index.add_package("coverage", target_version, now - timedelta(days=8))
    subprocess.run(["just", "upgrade-all"], cwd=project_copy, env=env, check=True)
    # should now be upgraded
    assert_locked_version(project_copy, "coverage", target_version)
