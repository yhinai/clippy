import asyncio
import os
from typing import Dict, List, Optional
import json
from openai import AsyncOpenAI
from lancedb_store import store

import base64

class LettaLiteAgent:
    def __init__(self):
        print("Initializing Letta-Lite Agent...")
        
        # Core Memory Blocks
        self.persona_block = (
            "You are Clippy, a helpful, slightly mischievous desktop assistant for macOS. "
            "You have a dry sense of humor. You love helping developers. "
            "You prefer concise answers but occasionally make a paperclip joke."
        )
        
        self.human_block = (
            "User is a developer working on a hackathon project. "
            "They are using Swift and Python."
        )
        
        self.scratchpad_block = ""
        
        # Client setup
        api_key = os.environ.get("GROK_API_KEY") or "xai-dummy-key"
        self.client = AsyncOpenAI(
            api_key=api_key,
            base_url="https://api.x.ai/v1"
        )
        
    def _construct_system_prompt(self, context: Dict) -> str:
        # Dynamic context from host
        app_name = context.get("app_name", "Unknown")
        clipboard_context = context.get("clipboard_items", [])
        
        # Format clipboard context for the prompt
        rag_text = ""
        if clipboard_context:
            rag_text = "\nRELEVANT CLIPBOARD HISTORY:\n"
            for item in clipboard_context:
                content = item.get('content', '')[:200] # Truncate for prompt
                rag_text += f"- [{item.get('timestamp')}] {content}\n"
        
        prompt = (
            f"SYSTEM MEMORY:\n"
            f"[PERSONA]\n{self.persona_block}\n\n"
            f"[HUMAN]\n{self.human_block}\n\n"
            f"[CONTEXT]\nUser is currently using: {app_name}\n"
            f"{rag_text}\n"
            f"INSTRUCTIONS:\n"
            f"Answer the user's query based on your memory and the context provided. "
            f"You can update your memory if you learn something new about the user or yourself."
        )
        return prompt

    async def process_vision(self, image_data: bytes) -> str:
        print(f"Processing vision data: {len(image_data)} bytes")
        
        # In a real Grok 2 Vision implementation, we would send the image
        # For now, if no API key, return mock.
        if self.client.api_key == "xai-dummy-key":
            return "I see an image! (Mock Vision Response - Set GROK_API_KEY to use Grok Vision)"
            
        try:
            # Encode image
            base64_image = base64.b64encode(image_data).decode('utf-8')
            
            messages = [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "Describe this image in detail for a blind user. Focus on UI elements, text hierarchy, and visible content."},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{base64_image}",
                            },
                        },
                    ],
                }
            ]
            
            completion = await self.client.chat.completions.create(
                model="grok-2-vision-1212", # Latest Grok Vision model
                messages=messages,
                stream=False
            )
            
            return completion.choices[0].message.content
            
        except Exception as e:
            print(f"Grok Vision Error: {e}")
            return f"I tried to look, but my eyes (Grok Vision) failed. Error: {e}"

    async def process_message(self, message: str, context: dict) -> str:
        # 1. Update LanceDB with current clipboard content if meaningful
        # (In a real scenario, the host sends *new* clipboard items to a separate ingestion endpoint, 
        # but here we assume the 'context' might contain relevant stuff or we just search)
        
        # 2. Search Archival Memory (LanceDB)
        # We search based on the user query
        search_results = store.search(message, limit=3)
        formatted_results = "\nARCHIVAL MEMORY SEARCH RESULTS:\n"
        for res in search_results:
            formatted_results += f"- {res['text_content'][:100]}...\n"
            
        # 3. Construct Prompt
        system_prompt = self._construct_system_prompt(context)
        system_prompt += formatted_results
        
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": message}
        ]
        
        # 4. Call Grok
        try:
            # We use a standard model; xAI supports 'grok-beta' or similar
            # If API key is dummy, this will fail, so we mock if needed.
            if self.client.api_key == "xai-dummy-key":
                return self._mock_response(message)
                
            completion = await self.client.chat.completions.create(
                model="grok-beta",
                messages=messages,
                stream=False
            )
            
            response_text = completion.choices[0].message.content
            return response_text
            
        except Exception as e:
            print(f"Grok API Error: {e}")
            return f"I tried to think, but my brain (Grok API) hurt. Error: {e}"

    def _mock_response(self, message: str) -> str:
        return (
            f"I'm in Mock Mode (No Grok API Key found). "
            f"I heard you say: '{message}'. "
            f"My persona is: {self.persona_block[:50]}..."
        )

# Singleton instance
agent = LettaLiteAgent()
