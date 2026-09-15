"""Regression checks for the packaged Codex WebSocket compression deadline."""

import os
import unittest
from unittest.mock import patch

from headroom.proxy.handlers import openai


TIMEOUT_ENV = "HEADROOM_CODEX_WS_COMPRESSION_TIMEOUT_SECONDS"


class CodexWebSocketTimeoutTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {})
        self.env.start()
        self.addCleanup(self.env.stop)
        os.environ.pop(TIMEOUT_ENV, None)
        self.general_timeout = patch.object(openai, "COMPRESSION_TIMEOUT_SECONDS", 30.0)
        self.general_timeout.start()
        self.addCleanup(self.general_timeout.stop)

    def test_upstream_default_remains_five_seconds(self):
        self.assertEqual(openai._codex_ws_compression_timeout_seconds(), 5.0)

    def test_can_increase_timeout_to_fifteen_seconds(self):
        os.environ[TIMEOUT_ENV] = "15"
        self.assertEqual(openai._codex_ws_compression_timeout_seconds(), 15.0)

    def test_fractional_timeout_is_supported(self):
        os.environ[TIMEOUT_ENV] = "12.5"
        self.assertEqual(openai._codex_ws_compression_timeout_seconds(), 12.5)

    def test_can_choose_a_shorter_timeout(self):
        os.environ[TIMEOUT_ENV] = "2"
        self.assertEqual(openai._codex_ws_compression_timeout_seconds(), 2.0)

    def test_general_compression_deadline_is_still_respected(self):
        os.environ[TIMEOUT_ENV] = "60"
        self.assertEqual(openai._codex_ws_compression_timeout_seconds(), 30.0)
        with patch.object(openai, "COMPRESSION_TIMEOUT_SECONDS", 3.0):
            self.assertEqual(openai._codex_ws_compression_timeout_seconds(), 3.0)

    def test_invalid_values_preserve_a_finite_positive_deadline(self):
        for value in ("", "invalid", "0", "-1", "nan", "inf", "-inf", "1e999"):
            with self.subTest(value=value):
                os.environ[TIMEOUT_ENV] = value
                self.assertEqual(openai._codex_ws_compression_timeout_seconds(), 5.0)


if __name__ == "__main__":
    unittest.main()
