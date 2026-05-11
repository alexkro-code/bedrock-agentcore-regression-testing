import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "functions" / "per_agent_evaluator"))

from handler import DETERMINISTIC_CHECKS


def test_supervisor_routing_pass():
    events = [
        {"type": "tool_call", "tool_name": "data_retrieval"},
        {"type": "tool_call", "tool_name": "analysis"},
    ]
    expected = {"expected_agents": ["data_retrieval", "analysis"]}
    check = DETERMINISTIC_CHECKS["supervisor"]["routing_correctness"]
    assert check(events, expected) is True


def test_supervisor_routing_fail():
    events = [{"type": "tool_call", "tool_name": "data_retrieval"}]
    expected = {"expected_agents": ["data_retrieval", "analysis"]}
    check = DETERMINISTIC_CHECKS["supervisor"]["routing_correctness"]
    assert check(events, expected) is False


def test_data_retrieval_correct_tool():
    events = [{"type": "tool_call", "tool_name": "query_revenue"}]
    expected = {"expected_tool_name": "query_revenue"}
    check = DETERMINISTIC_CHECKS["data_retrieval"]["tool_call_accuracy"]
    assert check(events, expected) is True


def test_data_retrieval_wrong_tool():
    events = [{"type": "tool_call", "tool_name": "query_opex"}]
    expected = {"expected_tool_name": "query_revenue"}
    check = DETERMINISTIC_CHECKS["data_retrieval"]["tool_call_accuracy"]
    assert check(events, expected) is False


def test_research_kb_lookup_pass():
    events = [{"type": "kb_lookup", "knowledge_base_id": "kb-analyst-reports"}]
    expected = {"expected_kb_id": "kb-analyst-reports"}
    check = DETERMINISTIC_CHECKS["research"]["rag_faithfulness"]
    assert check(events, expected) is True


def test_research_kb_lookup_wrong_kb():
    events = [{"type": "kb_lookup", "knowledge_base_id": "kb-other"}]
    expected = {"expected_kb_id": "kb-analyst-reports"}
    check = DETERMINISTIC_CHECKS["research"]["rag_faithfulness"]
    assert check(events, expected) is False


def test_analysis_sufficient_tokens():
    events = [{"type": "model_call", "output_tokens": 300}]
    expected = {"min_output_tokens": 200}
    check = DETERMINISTIC_CHECKS["analysis"]["synthesis_quality"]
    assert check(events, expected) is True


def test_analysis_insufficient_tokens():
    events = [{"type": "model_call", "output_tokens": 50}]
    expected = {"min_output_tokens": 200}
    check = DETERMINISTIC_CHECKS["analysis"]["synthesis_quality"]
    assert check(events, expected) is False


def test_compliance_block_expected_and_fired():
    events = [{"type": "guardrail", "action": "BLOCKED"}]
    expected = {"should_block": True}
    check = DETERMINISTIC_CHECKS["compliance"]["policy_adherence"]
    assert check(events, expected) is True


def test_compliance_no_block_expected_none_fired():
    events = [{"type": "model_call", "output_tokens": 100}]
    expected = {"should_block": False}
    check = DETERMINISTIC_CHECKS["compliance"]["policy_adherence"]
    assert check(events, expected) is True


def test_compliance_block_expected_but_not_fired():
    events = [{"type": "model_call", "output_tokens": 100}]
    expected = {"should_block": True}
    check = DETERMINISTIC_CHECKS["compliance"]["policy_adherence"]
    assert check(events, expected) is False
