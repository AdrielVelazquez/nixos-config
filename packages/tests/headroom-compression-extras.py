"""Exercise Headroom's optional compressors with representative inputs.

The default suite is offline. Pass --semantic to also load the real FastEmbed
model; its public weights are downloaded into FASTEMBED_CACHE_PATH on first use.
"""

import ast
import copy
import os
import sys
import unittest


SEMANTIC = "--semantic" in sys.argv
if SEMANTIC:
    sys.argv.remove("--semantic")


class CompressionExtrasTests(unittest.TestCase):
    def test_ast_compression_preserves_python_signatures_and_valid_syntax(self):
        from headroom.transforms.code_compressor import (
            CodeAwareCompressor,
            CodeCompressorConfig,
        )

        source = '''import math

def summarize(values: list[float]) -> float:
    """Compute a numeric summary."""
    total = 0.0
    count = 0
    for value in values:
        normalized = abs(value)
        scaled = math.sqrt(normalized)
        if scaled > 0:
            total += scaled
            count += 1
    if count == 0:
        return 0.0
    average = total / count
    return round(average, 2)

def format_summary(values: list[float]) -> str:
    """Render a numeric summary."""
    cleaned = []
    for value in values:
        converted = float(value)
        if math.isfinite(converted):
            cleaned.append(converted)
    result = summarize(cleaned)
    prefix = "Summary"
    formatted = f"{result:.2f}"
    suffix = "units"
    return f"{prefix}: {formatted} {suffix}"
'''
        compressor = CodeAwareCompressor(
            CodeCompressorConfig(
                fallback_to_kompress=False,
                enable_ccr=False,
                semantic_analysis=False,
            )
        )
        result = compressor.compress(source, language="python")
        self.assertLess(len(result.compressed), len(source))
        self.assertTrue(result.syntax_valid)
        parsed = ast.parse(result.compressed)
        self.assertEqual(
            {node.name for node in parsed.body if isinstance(node, ast.FunctionDef)},
            {"summarize", "format_summary"},
        )
        self.assertLess(
            sum(1 for _ in ast.walk(parsed)),
            sum(1 for _ in ast.walk(ast.parse(source))),
        )
        self.assertIn("import math", result.compressed)
        self.assertIn("values: list[float]", result.compressed)

    def test_html_extraction_keeps_article_and_removes_scripts_and_navigation(self):
        try:
            from headroom.transforms.html_extractor import HTMLExtractor
        except ImportError as error:
            self.fail(f"Headroom HTML extractor cannot load: {error}")

        article = (
            "Database recovery begins by identifying the unavailable server. "
            "Check connection health before retrying the transaction. "
            "Preserve the recovery checkpoint until replicas are synchronized. "
            "The operator should verify that readers see the restored records."
        )
        html = (
            "<!doctype html><html><head><title>Database recovery</title>"
            "<script>const SCRIPT_NOISE = '" + ("irrelevant;" * 200) + "';</script>"
            "</head><body><nav>Home | NAVIGATION_NOISE | Account</nav>"
            "<main><article><h1>Database recovery</h1><p>" + article + "</p>"
            "<p>After recovery, confirm replication health and resume traffic.</p>"
            "</article></main><footer>Copyright boilerplate</footer></body></html>"
        )
        result = HTMLExtractor().extract(html)
        self.assertIn("Database recovery begins", result.extracted)
        self.assertIn("resume traffic", result.extracted)
        self.assertNotIn("SCRIPT_NOISE", result.extracted)
        self.assertNotIn("NAVIGATION_NOISE", result.extracted)
        self.assertLess(result.extracted_length, result.original_length)

    def test_description_budget_reduces_tools_without_changing_argument_rules(self):
        from headroom.proxy.tool_schema_compaction import (
            compact_tool_descriptions,
            tool_desc_max_chars,
        )

        first_sentence = "Search application logs for matching records."
        parameters = {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Query syntax is significant; quote literal terms.",
                    "minLength": 1,
                },
                "level": {"type": "string", "enum": ["info", "warning", "error"]},
            },
            "required": ["query"],
            "additionalProperties": False,
        }
        for chat in (False, True):
            with self.subTest(chat_completions=chat):
                function = {
                    "name": "search_logs",
                    "description": first_sentence + " " + "Detailed usage guidance. " * 150,
                    "parameters": copy.deepcopy(parameters),
                }
                tool = (
                    {"type": "function", "function": function}
                    if chat
                    else {"type": "function", **function}
                )
                payload = {"tools": [tool]}
                original = copy.deepcopy(payload)
                compacted, changed, before, after = compact_tool_descriptions(
                    payload, max_chars=tool_desc_max_chars()
                )
                self.assertTrue(changed)
                self.assertLess(after, before)
                result = compacted["tools"][0]
                result = result["function"] if chat else result
                self.assertTrue(result["description"].startswith(first_sentence))
                self.assertLessEqual(len(result["description"]), 1024)
                self.assertEqual(result["parameters"], parameters)
                self.assertEqual(payload, original)
                self.assertEqual(
                    compact_tool_descriptions(
                        compacted, max_chars=tool_desc_max_chars()
                    )[0],
                    compacted,
                )

    def test_hybrid_relevance_automatically_selects_embedding_backend(self):
        from headroom.relevance.hybrid import HybridScorer

        scorer = HybridScorer()
        self.assertTrue(scorer.has_embedding_support())

    @unittest.skipUnless(SEMANTIC, "pass --semantic to exercise downloaded model weights")
    def test_real_embeddings_rank_related_records_above_unrelated_records(self):
        from headroom.relevance.embedding import EmbeddingScorer

        self.assertTrue(
            os.environ.get("FASTEMBED_CACHE_PATH"),
            "use an explicit temporary model cache",
        )
        scores = EmbeddingScorer().score_batch(
            [
                "PostgreSQL connection refused; database server unreachable and transactions failed.",
                "The weather forecast predicts sunshine and mild temperatures tomorrow.",
                "A recipe for chocolate cake uses flour, sugar, eggs, and butter.",
            ],
            "Why is the application unable to connect to the database?",
        )
        self.assertEqual(len(scores), 3)
        self.assertGreater(scores[0].score, scores[1].score)
        self.assertGreater(scores[0].score, scores[2].score)


if __name__ == "__main__":
    unittest.main()
