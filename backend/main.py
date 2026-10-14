import os
from typing import Literal

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

app = FastAPI(
    title="Ronghor AI API",
    description="Backend for Ronghor AI",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
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
    return {"app": "Ronghor AI API", "status": "ok"}


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.post("/chat", response_model=ChatResponse)
async def chat(body: ChatRequest):
    api_key = os.getenv("GEMINI_API_KEY")

    if not api_key:
        raise HTTPException(
            status_code=503,
            detail="Gemini API key is not configured on the server.",
        )

    model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

    contents = []

    for item in body.history:
        contents.append({
            "role": "model" if item.role == "assistant" else "user",
            "parts": [{"text": item.content}],
        })

    contents.append({
        "role": "user",
        "parts": [{"text": body.message}],
    })

    payload = {
        "systemInstruction": {
            "parts": [{
                "text": (
                    "You are Ronghor AI, a helpful, friendly AI assistant. "
                    "Give accurate, clear answers. Be honest about uncertainty. "
                    "Never claim you performed actions you did not perform."
                )
            }]
        },
        "contents": contents,
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 2048,
        },
    }

    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent"
    )

    try:
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                url,
                params={"key": api_key},
                json=payload,
            )

        if response.status_code != 200:
            # Do not send the API key or provider response to the app.
            raise HTTPException(
                status_code=502,
                detail=f"Gemini request failed with status {response.status_code}.",
            )

        data = response.json()
        parts = (
            data.get("candidates", [{}])[0]
            .get("content", {})
            .get("parts", [])
        )
        answer = "\n".join(
            part["text"] for part in parts if "text" in part
        ).strip()

        if not answer:
            raise HTTPException(
                status_code=502,
                detail="Gemini returned no text. Please try again.",
            )

        return ChatResponse(answer=answer)

    except httpx.TimeoutException as exc:
        raise HTTPException(
            status_code=504,
            detail="The AI service took too long to respond.",
        ) from exc
    except httpx.RequestError as exc:
        raise HTTPException(
            status_code=502,
            detail="Could not reach the AI service.",
        ) from exc
