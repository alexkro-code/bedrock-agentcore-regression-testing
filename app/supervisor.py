import os
from strands import Agent
from strands.models import BedrockModel
from bedrock_agentcore.runtime import BedrockAgentCoreApp


def _model(role):
    model_id = os.environ.get(f"MODEL_ID_{role.upper()}", os.environ["MODEL_ID"])
    return BedrockModel(model_id=model_id, temperature=0.0)


DATA_RETRIEVAL = Agent(name="data_retrieval", model=_model("data_retrieval"),
    system_prompt="Query financial databases for the requested data.")
RESEARCH = Agent(name="research", model=_model("research"),
    system_prompt="Search the knowledge base for analyst reports.")
ANALYSIS = Agent(name="analysis", model=_model("analysis"),
    system_prompt="Synthesize data from other agents into an analysis.")
COMPLIANCE = Agent(name="compliance", model=_model("compliance"),
    system_prompt="Enforce tenant policies and block restricted content.")

SUPERVISOR = Agent(
    name="supervisor", model=_model("supervisor"),
    system_prompt=("You coordinate financial analysis requests. Call the "
        "data_retrieval, research, analysis, and compliance tools."),
    tools=[
        DATA_RETRIEVAL.as_tool(name="data_retrieval", description="Query financial data."),
        RESEARCH.as_tool(name="research", description="Search analyst reports."),
        ANALYSIS.as_tool(name="analysis", description="Synthesize findings."),
        COMPLIANCE.as_tool(name="compliance", description="Check tenant policy."),
    ],
)

app = BedrockAgentCoreApp()


@app.entrypoint
def handler(payload):
    return {"output": str(SUPERVISOR(payload["input"]))}


if __name__ == "__main__":
    app.run()
