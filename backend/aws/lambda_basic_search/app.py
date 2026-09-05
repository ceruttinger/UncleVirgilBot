"""Basic AWS Lambda retrieval endpoint for UncleVirgilBot.

This first backend does not call an AI model. It receives a question, ranks memoir
chunks by lexical overlap, and returns top source passages. Add model synthesis
later behind the backend so API keys are never exposed in the Quarto site.
"""

import json
import os
import re
from typing import Any, Dict, List

import boto3

s3 = boto3.client("s3")

BUCKET = os.environ.get("CORPUS_BUCKET", "")
KEY = os.environ.get("SEARCH_INDEX_KEY", "data/public/search_index.json")

_CACHE: List[Dict[str, Any]] | None = None


def tokenize(text: str) -> List[str]:
    return [t for t in re.sub(r"[^a-z0-9\s]", " ", text.lower()).split() if len(t) > 2]


def load_index() -> List[Dict[str, Any]]:
    global _CACHE
    if _CACHE is not None:
        return _CACHE
    if not BUCKET:
        raise RuntimeError("CORPUS_BUCKET environment variable is required")
    obj = s3.get_object(Bucket=BUCKET, Key=KEY)
    _CACHE = json.loads(obj["Body"].read().decode("utf-8"))
    return _CACHE


def score_chunk(chunk: Dict[str, Any], query_tokens: List[str]) -> int:
    haystack = f"{chunk.get('chapter_title', '')} {chunk.get('text', '')}".lower()
    score = 0
    for token in query_tokens:
        score += haystack.count(token)
        if token in str(chunk.get("chapter_title", "")).lower():
            score += 5
    return score


def response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "OPTIONS,POST",
        },
        "body": json.dumps(body),
    }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return response(200, {"ok": True})

    try:
        payload = json.loads(event.get("body") or "{}")
        question = payload.get("question", "")
        if not question.strip():
            return response(400, {"error": "question is required"})

        index = load_index()
        q_tokens = tokenize(question)
        ranked = []
        for chunk in index:
            score = score_chunk(chunk, q_tokens)
            if score > 0:
                ranked.append({**chunk, "score": score})
        ranked.sort(key=lambda x: x["score"], reverse=True)
        sources = ranked[:5]

        if sources:
            chapter_refs = "; ".join(
                sorted({f"Chapter {s['chapter']}: {s['chapter_title']}" for s in sources})
            )
            answer = (
                f"I found relevant source passages in {chapter_refs}. "
                "This backend is retrieval-only for now; add model synthesis next."
            )
        else:
            answer = "I could not find strong matching passages in the memoir index."

        return response(200, {"answer": answer, "sources": sources})
    except Exception as exc:
        return response(500, {"error": str(exc)})
