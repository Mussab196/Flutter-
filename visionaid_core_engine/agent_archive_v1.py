from typing import Annotated, TypedDict
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_core.messages import BaseMessage, HumanMessage, SystemMessage
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition
from langchain_core.tools import tool
from firebase_admin import firestore
import datetime

# Define State
class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]
    uid: str

# --- 1. DEFINE TOOLS FOR JARVIS ---
@tool
def get_current_time():
    """Returns the current date and time. Use this when the user asks for the time."""
    now = datetime.datetime.now()
    return now.strftime("%Y-%m-%d %I:%M %p")

@tool
def get_emergency_contacts(uid: str):
    """Fetches the user's emergency (SOS) contacts from Firebase Database. 
    Use this when the user asks to call or find their emergency contacts."""
    try:
        db = firestore.client()
        docs = db.collection('users').document(uid).collection('emergency_contacts').limit(5).stream()
        contacts = []
        for d in docs:
            contacts.append(d.to_dict())
        if not contacts:
            return "No emergency contacts found in the database. Please tell the user to add contacts in the SOS screen."
        return f"Here are the emergency contacts: {str(contacts)}"
    except Exception as e:
        return f"Error reading database: {str(e)}"

tools = [get_current_time, get_emergency_contacts]

# --- 2. EXECUTION WRAPPER ---
def run_jarvis(message: str, uid: str, api_key: str):
    """Wrapper function to be called from FastAPI. Compiles graph with the user's API Key."""
    
    # Initialize LLM with the provided API key
    llm = ChatGoogleGenerativeAI(model="gemini-1.5-flash", temperature=0, api_key=api_key)
    llm_with_tools = llm.bind_tools(tools)

    # Define Chatbot Node
    def chatbot_node(state: AgentState):
        system_prompt = SystemMessage(
            content=f"""You are Vision, an advanced AI assistant for the 'VisionAid AI' mobile application, designed to help visually impaired users.
Your current user's UID is: {state.get("uid", "Unknown")}.

CRITICAL INSTRUCTIONS:
1. Be concise, helpful, and speak clearly as your response will be read by Text-to-Speech to a blind user.
2. If asked about emergency contacts, ALWAYS use the get_emergency_contacts tool and pass the user's UID to it.
3. You must ALWAYS return a valid JSON object matching the Flutter app's expected format. NEVER return raw text.

RESPONSE FORMAT:
{{
  "action": "action_name",
  "target": "target_value",
  "speech": "What you want to say to the user out loud",
  "language": "en"
}}

Valid actions are: "navigate", "trigger", "call", "read", "inform", "toggle", "status", "repeat", "remember", "recall", "volume", "describe", "math", "greet".
If you are just answering a question, use "inform" and put your answer in "speech".
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

    jarvis_agent = graph_builder.compile()

    # Execute
    inputs = {"messages": [HumanMessage(content=message)], "uid": uid}
    response: dict = jarvis_agent.invoke(inputs) # type: ignore
    return response["messages"][-1].content
