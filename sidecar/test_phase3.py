
import requests
import json
import time
import sys
from PIL import Image

def create_dummy_image():
    # Create a 100x100 red image
    img = Image.new('RGB', (100, 100), color = 'red')
    img.save('dummy.png')

def test_vision():
    print("\n--- Testing Vision Endpoint ---")
    create_dummy_image()
    url = "http://127.0.0.1:8000/v1/agent/vision"
    
    files = {'file': open('dummy.png', 'rb')}
    try:
        response = requests.post(url, files=files)
        print(f"Status: {response.status_code}")
        # Check if response is JSON
        try:
            print(f"Response: {response.json()}")
        except:
            print(f"Response Text: {response.text}")
    except Exception as e:
        print(f"FAILED: {e}")

def test_tools_search():
    print("\n--- Testing Tool: Search GitHub ---")
    url = "http://127.0.0.1:8000/v1/agent/message"
    payload = {
        "message": "Find a SwiftUI markdown parser on GitHub.",
        "context": {"app_name": "Xcode"}
    }
    try:
        response = requests.post(url, json=payload)
        print(f"Status: {response.status_code}")
        print(f"Response: {response.json()}")
    except Exception as e:
        print(f"FAILED: {e}")

def test_tools_paste():
    print("\n--- Testing Tool: Paste ---")
    url = "http://127.0.0.1:8000/v1/agent/message"
    payload = {
        "message": "Paste 'Hello World' here please.",
        "context": {"app_name": "Notes"}
    }
    try:
        response = requests.post(url, json=payload)
        data = response.json()
        print(f"Status: {response.status_code}")
        print(f"Response Text: {data.get('response')}")
        print(f"Tool Calls: {data.get('tool_calls')}")
        
        # Verify we got a tool call
        calls = data.get('tool_calls', [])
        if calls and calls[0]['name'] == 'paste_to_app':
            print("✅ SUCCESS: Received paste_to_app tool call")
        else:
            print("❌ FAILED: Did not receive paste_to_app tool call (or mock mode behavior differs)")
            
    except Exception as e:
        print(f"FAILED: {e}")

if __name__ == "__main__":
    # Wait for server to potentially start if run in parallel
    time.sleep(2) 
    test_vision()
    test_tools_search()
    test_tools_paste()
