from typing import Annotated, TypedDict
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_core.messages import BaseMessage, HumanMessage, SystemMessage
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition
from agents.tools import get_current_time, get_emergency_contacts, reverse_geocode

# Define State
class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]
    uid: str

# Define Tools
tools = [get_current_time, get_emergency_contacts, reverse_geocode]

# ══════════════════════════════════════════════
#  GRAPH CACHE — Compile once per API key, not every request.
#  Graph compilation involves building the state machine,
#  validating edges, and setting up tool routing. This is
#  expensive (~500ms) and completely unnecessary to repeat.
# ══════════════════════════════════════════════
_cached_graph = None
_cached_api_key = None


def _build_graph(api_key: str):
    """Build and compile the LangGraph with the given API key."""
    global _cached_graph, _cached_api_key

    # Return cached graph if API key hasn't changed
    if _cached_graph is not None and _cached_api_key == api_key:
        return _cached_graph

    # Initialize LLM with the provided API key
    llm = ChatGoogleGenerativeAI(
        model="gemini-2.0-flash",
        temperature=0,
        api_key=api_key,
        max_retries=2,
    )
    llm_with_tools = llm.bind_tools(tools)

    # Define Chatbot Node
    def chatbot_node(state: AgentState):
        system_prompt = SystemMessage(
            content=f"""You are Vision, an advanced AI assistant for the 'VisionAid AI' mobile application, designed to help visually impaired users.
Your current user's UID is: {state.get("uid", "Unknown")}.

CRITICAL INSTRUCTIONS:
1. Be concise, helpful, and speak clearly as your response will be read by Text-to-Speech to a blind user.
2. If asked about emergency contacts, ALWAYS use the get_emergency_contacts tool and pass the user's UID to it.
3. If the user asks "where am I" or about their surroundings, use the reverse_geocode tool if latitude/longitude are available in context.
4. You must ALWAYS return a valid JSON object matching the Flutter app's expected format. NEVER return raw text.

RESPONSE FORMAT:
{{
  "action": "action_name",
  "target": "target_value",
  "speech": "What you want to say to the user out loud",
  "language": "en"
}}

Valid actions are: "navigate", "trigger", "call", "read", "inform", "toggle", "status", "repeat", "remember", "recall", "volume", "describe", "math", "greet", "where_am_i", "read_document", "read_medicine", "scene_memory", "guide_to".
If you are just answering a question, use "inform" and put your answer in "speech".
For Urdu/Hindi users, set "language" to "ur" or "hi" and write speech in that language.
"""
        )
        messages_to_send = [system_prompt] + state["messages"]
        response = llm_with_tools.invoke(messages_to_send)
        return {"messages": [response]}

    # Build LangGraph
    graph_builder = StateGraph(AgentState)
    graph_builder.add_node("chatbot", chatbot_node)
    graph_builder.add_node("tools", ToolNode(tools=tools))

    graph_builder.add_edge(START, "chatbot")
    graph_builder.add_conditional_edges("chatbot", tools_condition)
    graph_builder.add_edge("tools", "chatbot")

    _cached_graph = graph_builder.compile()
    _cached_api_key = api_key

    return _cached_graph


def run_vision_agent(message: str, uid: str, api_key: str) -> str:
    """Wrapper function to be called from FastAPI.
    Uses cached graph for performance — only recompiles when API key changes."""

    if not api_key or api_key.strip() == "":
        raise ValueError("Gemini API key is missing. Please set it in the app settings.")

    try:
        graph = _build_graph(api_key)
        inputs = {"messages": [HumanMessage(content=message)], "uid": uid}
        response: dict = graph.invoke(inputs)  # type: ignore
        return response["messages"][-1].content

    except Exception as e:
        error_msg = str(e).lower()

        # Provide actionable error messages for common failures
        if "invalid api key" in error_msg or "api_key_invalid" in error_msg or "permission_denied" in error_msg:
            # Invalidate cache so next request with a new key works
            global _cached_graph, _cached_api_key
            _cached_graph = None
            _cached_api_key = None
            raise ValueError(f"INVALID_API_KEY: Your Gemini API key is invalid or expired. Please update it in Settings. Detail: {e}")

        if "quota" in error_msg or "resource_exhausted" in error_msg:
            raise ValueError(f"QUOTA_EXCEEDED: Your Gemini API quota has been exhausted. Try again later or upgrade your API plan. Detail: {e}")

        if "model" in error_msg and "not found" in error_msg:
            raise ValueError(f"MODEL_ERROR: The AI model is temporarily unavailable. Please try again in a moment. Detail: {e}")

        # Re-raise with context
        raise ValueError(f"AGENT_ERROR: {e}")
