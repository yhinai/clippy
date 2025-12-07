from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn
import os
import asyncio
from letta_agent import agent
from lancedb_store import store

app = FastAPI(title="Clippy Sidecar")

class AgentMessageRequest(BaseModel):
    message: str
    context: dict | None = None

class AgentMessageResponse(BaseModel):
    response: str
    tool_calls: list | None = None

@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "Clippy Sidecar", "letta": "initialized", "lancedb": "connected"}

@app.post("/v1/agent/message", response_model=AgentMessageResponse)
async def agent_message(request: AgentMessageRequest):
    print(f"Received message: {request.message}")
    
    # Delegate to Letta Agent
    response_text = await agent.process_message(request.message, request.context or {})
    
    return AgentMessageResponse(
        response=response_text,
        tool_calls=[]
    )

if __name__ == "__main__":
    # Running on localhost port 8000
    uvicorn.run(app, host="127.0.0.1", port=8000)
