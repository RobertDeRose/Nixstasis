#!/usr/bin/env python3
"""Exercise stack validation with fake Docker calls, without building images."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


COMPOSE_DIR = Path(__file__).resolve().parents[1]


class StackValidationTest(unittest.TestCase):
    """Check token length boundaries and the complete static validation path."""

    def test_proxy_token_length(self):
        """Quotes are delimiters, not bytes of the container's proxy token."""
        for quote in ["", "'", '"']:
            for length in [30, 31, 32, 64]:
                with self.subTest(quote=quote, length=length), tempfile.TemporaryDirectory() as tmp:
                    directory = Path(tmp)
                    docker = directory / "docker"
                    docker.write_text("#!/bin/sh\nexit 0\n")
                    docker.chmod(0o700)
                    env_file = directory / "stack.env"
                    env_file.write_text((COMPOSE_DIR / ".env.example").read_text().replace(
                        "NIXSTASIS_PROXY_AUTH_TOKEN=replace-me",
                        f"NIXSTASIS_PROXY_AUTH_TOKEN={quote}{'a' * length}{quote}",
                    ))
                    result = subprocess.run(
                        ["sh", str(COMPOSE_DIR / "scripts/validate_stack.sh"), str(env_file)],
                        env={**os.environ, "PATH": f"{directory}{os.pathsep}{os.environ['PATH']}"},
                        capture_output=True, text=True, check=False,
                    )
                    if length < 32:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn("NIXSTASIS_PROXY_AUTH_TOKEN must be at least 32", result.stderr)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn("compose stack validation passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
