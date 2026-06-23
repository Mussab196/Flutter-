import os
os.environ["GOOGLE_API_KEY"] = "fake" # or we just pass fake below
from agent import run_vision

try:
    print(run_jarvis("hello", "123", "fake_key"))
except Exception as e:
    import traceback
    traceback.print_exc()
