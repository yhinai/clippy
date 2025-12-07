import os
import asyncio
from openai import AsyncOpenAI
from dotenv import load_dotenv
import base64

load_dotenv()

async def probe_model(model_name, is_vision=False):
    print(f"\n--- Probing {model_name} (Vision: {is_vision}) ---")
    client = AsyncOpenAI(
        api_key=os.environ.get("GROK_API_KEY"),
        base_url="https://api.x.ai/v1"
    )
    
    try:
        messages = []
        if is_vision:
            # Create a tiny 1x1 red dot png base64
            dummy_b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
            messages = [
                {
                    "role": "user", 
                    "content": [
                        {"type": "text", "text": "What color is this?"},
                        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{dummy_b64}"}}
                    ]
                }
            ]
        else:
            messages = [{"role": "user", "content": "Hello! Are you online?"}]

        completion = await client.chat.completions.create(
            model=model_name,
            messages=messages,
            stream=False
        )
        print(f"✅ Success! Response: {completion.choices[0].message.content}")
        return True
    except Exception as e:
        print(f"❌ Failed: {e}")
        return False

async def main():
    # Test Legacy/Current Models
    # await probe_model("grok-2-vision-1212", is_vision=True) 
    
    print("\n--- Testing NEW Models ---")
    await probe_model("grok-2-vision", is_vision=True)
    await probe_model("grok-beta")
    
    # Test The New Hotness
    await probe_model("grok-4-1-fast-reasoning")
    await probe_model("grok-4-1-fast-non-reasoning")

if __name__ == "__main__":
    asyncio.run(main())
