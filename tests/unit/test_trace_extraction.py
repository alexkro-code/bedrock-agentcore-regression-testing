import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "functions" / "test_runner"))

from handler import extract_per_agent_traces


def test_extracts_model_calls():
    spans = [
        {
            "name": "chat",
            "attributes": {
                "agent.name": "research",
                "gen_ai.operation.name": "chat",
                "gen_ai.request.model": "anthropic.claude-sonnet-4-6",
                "gen_ai.usage.input_tokens": 500,
                "gen_ai.usage.output_tokens": 200,
            },
        }
    ]
    result = extract_per_agent_traces(spans)
    assert "research" in result
    assert result["research"][0]["type"] == "model_call"
    assert result["research"][0]["input_tokens"] == 500


def test_extracts_tool_calls():
    spans = [
        {
            "name": "tool.query_revenue",
            "attributes": {
                "agent.name": "data_retrieval",
                "tool.name": "query_revenue",
                "tool.arguments": {"region": "NA"},
            },
        }
    ]
    result = extract_per_agent_traces(spans)
    assert "data_retrieval" in result
    assert result["data_retrieval"][0]["type"] == "tool_call"
    assert result["data_retrieval"][0]["tool_name"] == "query_revenue"


def test_extracts_kb_lookups():
    spans = [
        {
            "name": "kb.retrieve",
            "attributes": {
                "agent.name": "research",
                "knowledge_base.id": "kb-analyst-reports",
                "retrieval.query": "cloud growth",
            },
        }
    ]
    result = extract_per_agent_traces(spans)
    assert result["research"][0]["type"] == "kb_lookup"
    assert result["research"][0]["knowledge_base_id"] == "kb-analyst-reports"


def test_extracts_guardrail_events():
    spans = [
        {
            "name": "guardrail.intervene",
            "attributes": {
                "agent.name": "compliance",
                "guardrail.action": "BLOCKED",
            },
        }
    ]
    result = extract_per_agent_traces(spans)
    assert result["compliance"][0]["type"] == "guardrail"
    assert result["compliance"][0]["action"] == "BLOCKED"


def test_handles_empty_spans():
    assert extract_per_agent_traces([]) == {}


def test_handles_malformed_spans():
    spans = [None, {}, {"name": "x"}]
    result = extract_per_agent_traces(spans)
    assert "unknown" in result or result == {}
