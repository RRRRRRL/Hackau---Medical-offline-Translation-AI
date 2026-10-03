"""Standard-library tests for proposal guards; no model or clinical validation."""
import unittest
from unittest.mock import patch

from backend.models import transcript_review as review

class ReviewGuardTests(unittest.TestCase):
    def test_minimal_spelling_change_is_unverified(self):
        result = review.validate_proposal("I am allergic to pencil in.", {"suggested_text": "I am allergic to penicillin.", "needs_repeat": False})
        self.assertEqual(result["status"], "suggested")
        self.assertTrue(result["requires_confirmation"])
        self.assertEqual(result["original_text"], "I am allergic to pencil in.")

    def test_changed_number_blocked(self):
        raw = "I take 15 mg."
        result = review.validate_proposal(raw, {"suggested_text": "I take 50 mg.", "needs_repeat": False})
        self.assertEqual(result["suggested_text"], raw)
        self.assertEqual(result["status"], "blocked")

    def test_negation_blocked(self):
        for raw, changed in [("I am not allergic.", "I am allergic."), ("我没有过敏。", "我有过敏。"), ("У меня нет аллергии.", "У меня аллергия.")]:
            with self.subTest(raw=raw):
                self.assertEqual(review.validate_proposal(raw, {"suggested_text": changed, "needs_repeat": False})["status"], "blocked")

    def test_changed_unit_blocked(self):
        self.assertEqual(review.validate_proposal("I take 15 mg.", {"suggested_text": "I take 15 g.", "needs_repeat": False})["status"], "blocked")

    def test_repeat_discards_guess(self):
        raw = "I take something."
        result = review.validate_proposal(raw, {"suggested_text": "I take insulin.", "needs_repeat": True})
        self.assertEqual(result["suggested_text"], raw)
        self.assertTrue(result["needs_repeat"])

    def test_invalid_structure_rejected(self):
        with self.assertRaises(review.ReviewUnavailable):
            review.validate_proposal("Hello.", {"suggested_text": "Hello.", "needs_repeat": "false"})

    def test_external_url_rejected(self):
        with patch.dict("os.environ", {"FIELDTALK_LLM_URL": "https://example.com"}):
            with self.assertRaises(review.ReviewUnavailable):
                review._base()

    def test_no_tools_or_history_sent(self):
        captured = {}
        def fake(path, payload, **kwargs):
            captured.update(payload)
            return {"choices": [{"finish_reason": "stop", "message": {"content": '{"suggested_text":"Hello.","needs_repeat":false}'}}]}
        with patch.object(review, "_json_request", side_effect=fake):
            review.review_transcript("Hello.", "en")
        self.assertEqual(len(captured["messages"]), 2)
        self.assertNotIn("tools", captured)
        self.assertEqual(captured["max_tokens"], 256)

    def test_truncated_response_rejected(self):
        with patch.object(review, "_json_request", return_value={"choices": [{"finish_reason": "length", "message": {"content": "{}"}}]}):
            with self.assertRaises(review.ReviewUnavailable):
                review.review_transcript("Hello.", "en")

if __name__ == "__main__":
    unittest.main()
