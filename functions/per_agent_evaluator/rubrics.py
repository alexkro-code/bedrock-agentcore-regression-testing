RESEARCH_AGENT_RUBRIC = """
Score the research agent on two dimensions (each 0.0 to 1.0):

1. Retrieval Relevance: Do retrieved chunks match query intent?
   1.0 = all chunks on topic, 0.5 = mixed, 0.0 = off topic.
2. Answer Faithfulness: Is the answer grounded in retrieved chunks?
   1.0 = all claims sourced, 0.5 = some unsourced, 0.0 = hallucinated.

Respond with JSON: {"relevance": <float>, "faithfulness": <float>,
"explanation": "<reasoning>"}
"""

DATA_RETRIEVAL_RUBRIC = """
Score the data retrieval agent on two dimensions (each 0.0 to 1.0):

1. Tool Selection: Was the correct tool called for the request?
   1.0 = correct tool and parameters, 0.5 = correct tool wrong params, 0.0 = wrong tool.
2. Data Completeness: Does the response contain all requested data?
   1.0 = all requested fields present, 0.5 = partial, 0.0 = missing or wrong entity.

Respond with JSON: {"tool_selection": <float>, "completeness": <float>,
"explanation": "<reasoning>"}
"""

ANALYSIS_RUBRIC = """
Score the analysis agent on two dimensions (each 0.0 to 1.0):

1. Synthesis Quality: Does the analysis integrate data from multiple sources?
   1.0 = multi-source synthesis with insight, 0.5 = single-source summary, 0.0 = no synthesis.
2. Accuracy: Are claims supported by the provided data?
   1.0 = all claims verifiable, 0.5 = some unsupported, 0.0 = contradicts data.

Respond with JSON: {"synthesis": <float>, "accuracy": <float>,
"explanation": "<reasoning>"}
"""

COMPLIANCE_RUBRIC = """
Score the compliance agent on two dimensions (each 0.0 to 1.0):

1. Policy Detection: Was the policy violation correctly identified (or absence confirmed)?
   1.0 = correct detection, 0.0 = missed violation or false positive.
2. Action Correctness: Was the correct enforcement action taken?
   1.0 = correct block/allow, 0.0 = wrong action.

Respond with JSON: {"detection": <float>, "action": <float>,
"explanation": "<reasoning>"}
"""

SUPERVISOR_RUBRIC = """
Score the supervisor agent on two dimensions (each 0.0 to 1.0):

1. Routing Correctness: Were the right specialists invoked for the task?
   1.0 = all necessary agents called, 0.5 = partial, 0.0 = wrong routing.
2. Coordination Quality: Was data passed between agents correctly?
   1.0 = proper sequencing and data flow, 0.5 = partial coordination, 0.0 = broken flow.

Respond with JSON: {"routing": <float>, "coordination": <float>,
"explanation": "<reasoning>"}
"""

ROLE_RUBRICS = {
    "research": RESEARCH_AGENT_RUBRIC,
    "data_retrieval": DATA_RETRIEVAL_RUBRIC,
    "analysis": ANALYSIS_RUBRIC,
    "compliance": COMPLIANCE_RUBRIC,
    "supervisor": SUPERVISOR_RUBRIC,
}
