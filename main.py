import os
from typing import Literal

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from openai import OpenAI, OpenAIError
from pydantic import BaseModel, Field

load_dotenv()

app = FastAPI(
    title="Ronghor AI API",
    description="Backend for the Ronghor AI Android starter app",
    version="0.1.0",
)

origins = os.getenv("APP_ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in origins],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

class HistoryItem(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=12000)

class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=12000)
    web_search: bool = False
    history: list[HistoryItem] = Field(default_factory=list, max_length=12)

class ChatResponse(BaseModel):
    answer: str

@app.get("/")
def root():
    return {
        "app": "Ronghor AI API",
        "status": "ok",
        "note": "Configure OPENAI_API_KEY on the server before using /chat.",
    }

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.post("/chat", response_model=ChatResponse)
def chat(body: ChatRequest):
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(
            status_code=503,
            detail="The backend administrator has not configured OPENAI_API_KEY.",
        )

    model = os.getenv("OPENAI_MODEL", "gpt-6-astra")
    client = OpenAI(api_key=api_key)

    conversation = []
    for item in body.history:
        conversation.append({"role": item.role, "content": item.content})
    conversation.append({"role": "user", "content": body.message})

    kwargs = {
        "model": model,
        "instructions": (
            "You are Ronghor AI, a helpful, careful, friendly AI assistant. "
            "Answer clearly, be honest about uncertainty, and do not claim to "
            "have performed actions you have not performed. When web search is "
            "used, distinguish sourced facts from uncertainty."
        ),
        "input": conversation,
    }
    if body.web_search:
        kwargs["tools"] = [{"type": "web_search"}]

    try:
        response = client.responses.create(**kwargs)
        answer = response.output_text or "I couldn't produce a text response. Please try again."
        return ChatResponse(answer=answer)
    except OpenAIError as exc:
        # Do not expose secrets or internal stack traces to the mobile app.
        raise HTTPException(
            status_code=502,
            detail=f"AI provider request failed ({type(exc).__name__}). Check server logs and model access.",
        ) from exc
