import base64
import hashlib
import os
import re
import shutil
import subprocess
import textwrap
import tomllib
import zipfile
from collections import defaultdict
from datetime import datetime
from pathlib import Path

import pytest


def pytest_runtest_setup(item):
    if os.path.exists("/.dockerenv"):  # pragma: nocover
        pytest.skip("Skipping the template tests inside Docker")


class LocalSimpleIndex:
    """A PEP 503 compliant simple file based index of packages.

    Each package has its own directory, and within that directory, an
    index.html with a list of package versions.

    add_package() will build a metadata-only wheel which is enough to be
    installable with the right metadata.

    add_locked_package() will use the package metadata already present in
    uv.lock to write an index.html entry without needing a local wheel.

    """

    def __init__(self, root: Path) -> None:
        self.simple_dir = root / "simple"
        self.simple_dir.mkdir(parents=True, exist_ok=True)
        self.package_links: defaultdict[str, list[tuple[str, str, datetime, str]]] = (
            defaultdict(list)
        )

    @property
    def url(self) -> str:
        return self.simple_dir.as_uri().rstrip("/") + "/"

    def package_dir(self, name):
        # PEP503-normalized package name
        normalised_name = re.sub(r"[-_.]+", "-", name).lower()
        pkg_dir = self.simple_dir / normalised_name
        pkg_dir.mkdir(exist_ok=True, parents=True)
        return pkg_dir

    def _write_package_index(self, package: str) -> None:
        pkg_dir = self.package_dir(package)
        links = self.package_links.get(package, [])
        # the data-upload-time attribute is what uv needs to know the upload time
        anchors = "\n".join(
            f'<a href="{href}#sha256={sha}" data-upload-time="{upload_time}">{text}</a>'
            for href, sha, upload_time, text in links
        )

        html = f"<html><body>{anchors}</body></html>"
        pkg_dir.joinpath("index.html").write_text(html)

    def add_package(self, name: str, version: str, upload_time: datetime) -> None:
        wheel_name, sha = self._build_wheel(name, version)

        self.package_links[name].append((wheel_name, sha, upload_time, wheel_name))
        self._write_package_index(name)

    def add_locked_package(self, lock_entry: dict[str, object]) -> None:
        """Add an entry for a package that already exists in uv.lock.

        This just sets up the metadata in the index.html so that uv can see it
        for resolution. Uses the upload-time recorded in uv.lock by default so
        timestamps match the lockfile. It's not actually installable, as we
        don't provide a wheel.
        """
        artifacts = []
        if wheels := lock_entry.get("wheels"):
            artifacts = wheels
        elif sdist := lock_entry.get("sdist"):  # pragma: nocover
            artifacts = [sdist]
        else:
            # virtual package, i.e. repo-template itself
            return

        links = []
        for artifact in artifacts:
            href = artifact["url"]
            sha = artifact["hash"].split(":", 1)[-1]
            link_text = Path(href).name
            links.append((href, sha, artifact.get("upload-time"), link_text))

        self.package_links[lock_entry["name"]].extend(links)
        self._write_package_index(lock_entry["name"])

    def _build_wheel(self, name: str, version: str) -> str:
        """Make a simple empty wheel with the right metadata to pretend to be a package."""
        dist_name = name.replace("-", "_")
        wheel_name = f"{dist_name}-{version}-py3-none-any.whl"
        dist_info = f"{dist_name}-{version}.dist-info"
        path = self.package_dir(name) / wheel_name

        metadata = textwrap.dedent(
            f"""\
            Metadata-Version: 2.1
            Name: {name}
            Version: {version}
            """
        ).encode()
        wheel_metadata = textwrap.dedent(
            """\
            Wheel-Version: 1.0
            Generator: repo-template-test
            Root-Is-Purelib: true
            Tag: py3-none-any
            """
        ).encode()

        files = {
            f"{dist_name}/__init__.py": b"",
            f"{dist_info}/METADATA": metadata,
            f"{dist_info}/WHEEL": wheel_metadata,
            f"{dist_info}/top_level.txt": f"{name}\n".encode(),
        }

        record_rows = []
        for filename, data in files.items():
            digest = (
                base64.urlsafe_b64encode(hashlib.sha256(data).digest())
                .decode()
                .rstrip("=")
            )
            record_rows.append(f"{filename},sha256={digest},{len(data)}")

        record_rows.append(f"{dist_info}/RECORD,,")
        files[f"{dist_info}/RECORD"] = ("\n".join(record_rows) + "\n").encode()

        with zipfile.ZipFile(path, "w") as zf:
            for filename, data in files.items():
                zf.writestr(filename, data)

        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        return wheel_name, sha


@pytest.fixture
def uv_cache(tmp_path, monkeypatch):
    """Ensure we have a clean cache for packaging tests, to avoid pollution."""
    monkeypatch.setitem(os.environ, "UV_CACHE_DIR", str(tmp_path / "uv-cache"))
    # also, make sure we don't emit ascii colours
    monkeypatch.setitem(os.environ, "UV_NO_COLOR", "1")


@pytest.fixture()
def project_copy(tmp_path, monkeypatch) -> Path:
    """Copy the repo into a temp directory and stub git hooks for pre-commit."""

    monkeypatch.delitem(os.environ, "VIRTUAL_ENV")
    repo_root = Path(__file__).resolve().parent.parent.parent
    dest = tmp_path / "repo"

    # make a copy of the project files
    shutil.copytree(
        repo_root,
        dest,
        ignore=shutil.ignore_patterns(
            ".venv", "htmlcov", "__pycache__", "*.pyc", ".git"
        ),
    )

    # install a no-op precommit hook, as devenv requires it
    subprocess.run(["git", "init", "-q"], cwd=dest, check=True)
    hooks_dir = dest / ".git" / "hooks"
    hooks_dir.mkdir(parents=True, exist_ok=True)
    hook_path = hooks_dir / "pre-commit"
    hook_path.write_text("#!/bin/sh\nexit 0\n")
    hook_path.chmod(0o755)

    return dest


@pytest.fixture()
def local_index(tmp_path, project_copy, uv_cache) -> LocalSimpleIndex:
    """Create a local PEP 503 index seeded with versions from uv.lock."""

    # first, ensure we have the correct versions for the current packages in
    # the cache. This means our index doesn't actually need to serve them.
    subprocess.run(["uv", "sync"], cwd=project_copy, check=True)

    index_root = tmp_path / "index"
    index = LocalSimpleIndex(index_root)

    # add all current packages using the metadata captured in uv.lock
    lock_data = tomllib.loads((project_copy / "uv.lock").read_text())
    for entry in lock_data.get("package", []):
        index.add_locked_package(entry)

    return index
