from langchain_core.tools import tool
from firebase_admin import firestore
import datetime
import urllib.request
import json

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

@tool
def reverse_geocode(latitude: float, longitude: float):
    """Converts GPS coordinates to a human-readable address/location name.
    Use this when the user asks 'where am I' or wants to know their current location.
    Returns the street name, area, city, and country."""
    try:
        url = (
            f"https://nominatim.openstreetmap.org/reverse?"
            f"format=json&lat={latitude}&lon={longitude}"
            f"&zoom=18&addressdetails=1"
        )
        req = urllib.request.Request(url, headers={"User-Agent": "VisionAidApp/2.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())

        address = data.get("address", {})
        parts = []

        # Build a natural spoken address
        road = address.get("road") or address.get("pedestrian") or address.get("footway")
        if road:
            parts.append(f"on {road}")

        neighbourhood = address.get("neighbourhood") or address.get("suburb") or address.get("quarter")
        if neighbourhood:
            parts.append(f"in {neighbourhood}")

        city = address.get("city") or address.get("town") or address.get("village")
        if city:
            parts.append(city)

        country = address.get("country")
        if country:
            parts.append(country)

        if parts:
            return f"You are located {', '.join(parts)}."
        else:
            display = data.get("display_name", "an unknown location")
            return f"You are near {display}."

    except Exception as e:
        return f"Could not determine your location name. Error: {str(e)}"
