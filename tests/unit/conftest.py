import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "functions" / "agent_factory"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "functions" / "test_runner"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "functions" / "per_agent_evaluator"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "functions" / "report_generator"))
