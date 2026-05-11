import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "functions" / "agent_factory"))


@patch("handler._AGENTCORE_CTRL")
def test_wait_ready_success(mock_ctrl):
    from handler import _wait_ready

    mock_ctrl.get_agent_runtime.return_value = {"status": "READY"}
    _wait_ready("test-id", timeout_s=10)
    mock_ctrl.get_agent_runtime.assert_called_once_with(agentRuntimeId="test-id")


@patch("handler._AGENTCORE_CTRL")
def test_wait_ready_polls_until_ready(mock_ctrl):
    from handler import _wait_ready

    mock_ctrl.get_agent_runtime.side_effect = [
        {"status": "CREATING"},
        {"status": "CREATING"},
        {"status": "READY"},
    ]
    _wait_ready("test-id", timeout_s=30)
    assert mock_ctrl.get_agent_runtime.call_count == 3


@patch("handler._AGENTCORE_CTRL")
def test_wait_ready_raises_on_failure(mock_ctrl):
    from handler import _wait_ready
    import pytest

    mock_ctrl.get_agent_runtime.return_value = {"status": "CREATE_FAILED"}
    with pytest.raises(RuntimeError, match="failed"):
        _wait_ready("test-id", timeout_s=10)
