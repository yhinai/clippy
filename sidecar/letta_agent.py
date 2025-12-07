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
        
        # Define Tools
        self.tools = [
            {
                "type": "function",
                "function": {
                    "name": "search_github",
                    "description": "Search GitHub for repositories or code. Use this when the user asks to find a library or project.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "The search query (e.g., 'swiftui markdown parser')",
                            }
                        },
                        "required": ["query"],
                    },
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "paste_to_app",
                    "description": "Paste text content into the user's active application. Use this when the user explicitly asks to 'paste' something or 'put this here'.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "content": {
                                "type": "string",
                                "description": "The exact text content to paste.",
                            }
                        },
                        "required": ["content"],
                    },
                }
            }
        ]

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

    async def process_message(self, message: str, context: dict) -> Dict:
        # Return type changed from str to Dict to support tool_calls in response
        
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
                # Basic mock tool check
                if "github" in message.lower():
                     return {"response": "I'm in Mock Mode. I would search GitHub for that. (Set GROK_API_KEY for real tools)", "tool_calls": []}
                return {"response": self._mock_response(message), "tool_calls": []}
                
            completion = await self.client.chat.completions.create(
                model="grok-beta",
                messages=messages,
                tools=self.tools,
                tool_choice="auto",
                stream=False
            )
            
            response_message = completion.choices[0].message
            client_tool_calls = []
            
            # Handle Tool Calls
            if response_message.tool_calls:
                print("Tool call detected!")
                # Append assistant's message with tool calls to history
                messages.append(response_message)
                
                # Flag to check if we need a second loop (server-side execution)
                requires_second_pass = False
                
                for tool_call in response_message.tool_calls:
                    function_args = json.loads(tool_call.function.arguments)
                    
                    # Server-Side Tools
                    if tool_call.function.name == "search_github":
                        print(f"Executing search_github with args: {function_args}")
                        tool_result = await self._execute_search_github(function_args.get("query"))
                        messages.append({
                            "tool_call_id": tool_call.id,
                            "role": "tool",
                            "name": "search_github",
                            "content": tool_result,
                        })
                        requires_second_pass = True
                    
                    # Client-Side Tools (to be executed by Swift Host)
                    elif tool_call.function.name == "paste_to_app":
                         print(f"Delegating paste_to_app to Host: {function_args}")
                         # We don't execute here. We pass it up.
                         # But wait, if we don't execute, we can't continue the conversation loop easily *here*.
                         # Strategy: Return the tool call to Swift. Swift executes. Swift calls back?
                         # Simpler: Just return the intention to Swift.
                         client_tool_calls.append({
                             "name": "paste_to_app",
                             "parameters": function_args
                         })
                         # We mark this as "handled" for the LLM so it doesn't complain? 
                         # No, if we want the LLM to know it happened, we'd need a callback loop.
                         # For now, we just return the instruction to Swift and end the turn.
                         return {
                             "response": "I'm pasting that for you.",
                             "tool_calls": client_tool_calls
                         }

                if requires_second_pass:
                    # Get final response after server-side tool execution
                    second_response = await self.client.chat.completions.create(
                        model="grok-beta",
                        messages=messages
                    )
                    return {
                        "response": second_response.choices[0].message.content,
                        "tool_calls": []
                    }

            return {
                "response": response_message.content,
                "tool_calls": []
            }
            
        except Exception as e:
            print(f"Grok API Error: {e}")
            return {
                "response": f"I tried to think, but my brain (Grok API) hurt. Error: {e}",
                "tool_calls": []
            }

    async def _execute_search_github(self, query: str) -> str:
        # Simple mock/simulated search for now. 
        # In a real app, this would hit the GitHub API.
        print(f"Simulating GitHub Search for: {query}")
        return json.dumps({
            "results": [
                {"name": f"{query}-lib", "url": f"https://github.com/example/{query}-lib", "stars": 1200},
                {"name": f"awesome-{query}", "url": f"https://github.com/example/awesome-{query}", "stars": 4500},
            ]
        })

    def _mock_response(self, message: str) -> str:
        return (
            f"I'm in Mock Mode (No Grok API Key found). "
            f"I heard you say: '{message}'. "
            f"My persona is: {self.persona_block[:50]}..."
        )

# Singleton instance
agent = LettaLiteAgent()
