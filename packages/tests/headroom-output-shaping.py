"""Keep fixed verbosity steering available and stable on the stable rollout channel."""

import copy
import os
import unittest
from unittest.mock import patch

from headroom.proxy.output_shaper import (
    OutputShaperSettings,
    resolve_verbosity_level,
    shape_openai_chat_request,
)
from headroom.rollout import resolve_rollout

ENVIRONMENT = {
    "HEADROOM_ROLLOUT_CHANNEL": "stable",
    "HEADROOM_OUTPUT_SHAPER": "1",
    "HEADROOM_VERBOSITY_LEVEL": "3",
    "HEADROOM_VERBOSITY_AUTOTUNE": "0",
    "HEADROOM_OUTPUT_HOLDOUT": "0",
    "HEADROOM_MODE": "cache",
}


class OutputShapingTests(unittest.TestCase):
    def test_requested_output_shaping_is_enabled_on_stable(self):
        snapshot = resolve_rollout(ENVIRONMENT, strict=True)
        self.assertTrue(snapshot.is_enabled("proxy_output_shaper"))

    def test_cache_mode_honors_the_fixed_verbosity_level(self):
        with patch.dict(os.environ, ENVIRONMENT, clear=True):
            settings = OutputShaperSettings.from_env()
            level, _ = resolve_verbosity_level(settings)
        self.assertEqual(level, 3)

    def test_chat_steering_is_idempotent_and_preserves_model_and_tool_controls(self):
        body = {
            "model": "fixture-model",
            "messages": [
                {"role": "system", "content": "Keep the repository conventions."},
                {"role": "user", "content": "Review the change."},
            ],
            "reasoning_effort": "high",
            "max_completion_tokens": 8192,
            "tools": [
                {"type": "function", "function": {"name": "read", "parameters": {}}}
            ],
        }
        controls = {
            key: copy.deepcopy(value)
            for key, value in body.items()
            if key != "messages"
        }
        with patch.dict(os.environ, ENVIRONMENT, clear=True):
            settings = OutputShaperSettings.from_env()
            level, _ = resolve_verbosity_level(settings)
            result = shape_openai_chat_request(body, settings, level_override=level)
            self.assertTrue(result.changed)
            self.assertIn(
                "Keep the repository conventions.", body["messages"][0]["content"]
            )
            self.assertNotEqual(
                body["messages"][0]["content"], "Keep the repository conventions."
            )
            first = copy.deepcopy(body)
            shape_openai_chat_request(body, settings, level_override=level)
        self.assertEqual(body, first)
        self.assertEqual(
            {key: value for key, value in body.items() if key != "messages"}, controls
        )


if __name__ == "__main__":
    unittest.main()
