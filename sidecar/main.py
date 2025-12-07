from fastapi import FastAPI, HTTPException, UploadFile, File
from pydantic import BaseModel
import uvicorn
import os
import asyncio
from dotenv import load_dotenv

load_dotenv()

from letta_agent import agent
from lancedb_store import store

app = FastAPI(title="Clippy Sidecar")

from typing import Optional, List, Dict

class AgentMessageRequest(BaseModel):
    message: str
    context: Optional[Dict] = None

class AgentMessageResponse(BaseModel):
    response: str
    tool_calls: Optional[List] = None

@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "Clippy Sidecar", "letta": "initialized", "lancedb": "connected"}

class MemoryItemRequest(BaseModel):
    text: str
    source_app: str
    tags: List[str] = []

@app.post("/v1/memory/add")
async def add_memory_item(request: MemoryItemRequest):
    print(f"Adding memory item: {request.text[:50]}...")
    try:
        item_id = store.add_item(request.text, request.source_app, request.tags)
        return {"status": "success", "id": item_id}
    except Exception as e:
        print(f"Error adding item: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/v1/agent/vision", response_model=AgentMessageResponse)
async def agent_vision(file: UploadFile = File(...)):
    print(f"Received vision request: {file.filename}")
    try:
        content = await file.read()
        response_text = await agent.process_vision(content)
        return AgentMessageResponse(
            response=response_text,
            tool_calls=[]
        )
    except Exception as e:
        print(f"Error processing vision: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/v1/agent/reflect")
async def agent_reflect():
    print("Triggering Reflector...")
    try:
        new_persona = await agent.run_reflector()
        return {"status": "success", "new_persona": new_persona}
    except Exception as e:
        print(f"Error running reflector: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/v1/agent/message", response_model=AgentMessageResponse)
async def agent_message(request: AgentMessageRequest):
    print(f"Received message: {request.message}")
    
    # Delegate to Letta Agent
    result = await agent.process_message(request.message, request.context or {})
    
    return AgentMessageResponse(
        response=result.get("response", ""),
        tool_calls=result.get("tool_calls", [])
    )

if __name__ == "__main__":
    # Running on localhost port 8000
    uvicorn.run(app, host="127.0.0.1", port=8000)
