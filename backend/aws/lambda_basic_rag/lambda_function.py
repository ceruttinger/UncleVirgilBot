"""Minimal AWS Lambda retrieval + model orchestration stub for UncleVirgilBot.

Environment variables:
  CORPUS_BUCKET          S3 bucket containing search_index.json
  SEARCH_INDEX_KEY       S3 key, default: data/public/search_index.json
  MODEL_PROVIDER         "none", "openai", or "bedrock"; default: none
  OPENAI_API_KEY         Required only for MODEL_PROVIDER=openai
  OPENAI_MODEL           Example: gpt-5.5-mini or your preferred available model
  BEDROCK_MODEL_ID       Required only for MODEL_PROVIDER=bedrock

This handler intentionally starts with simple lexical retrieval. Once the app UX
is validated, swap retrieve_passages() for Bedrock Knowledge Bases, OpenSearch,
or pgvector retrieval.
"""

from __future__ import annotations

import json
import os
import re
from functools import lru_cache
from typing import Any, Dict, Iterable, List

import boto3

s3 = boto3.client("s3")

STOPWORDS = {
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "how", "i", "in",
    "is", "it", "of", "on", "or", "that", "the", "this", "to", "was", "were", "what", "when",
    "where", "who", "why", "with", "about", "tell", "me", "did", "does", "do"
}


def response(status: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": os.getenv("CORS_ALLOW_ORIGIN", "*"),
            "Access-Control-Allow-Headers": "content-type",
            "Access-Control-Allow-Methods": "OPTIONS,POST",
        },
        "body": json.dumps(body),
    }


def tokenize(text: str) -> List[str]:
    return [w for w in re.findall(r"[a-zA-Z][a-zA-Z']+", text.lower()) if w not in STOPWORDS and len(w) > 2]


@lru_cache(maxsize=1)
def load_index() -> List[Dict[str, Any]]:
    bucket = os.environ["CORPUS_BUCKET"]
    key = os.getenv("SEARCH_INDEX_KEY", "data/public/search_index.json")
    obj = s3.get_object(Bucket=bucket, Key=key)
    return json.loads(obj["Body"].read().decode("utf-8"))


def retrieve_passages(question: str, limit: int = 5) -> List[Dict[str, Any]]:
    terms = tokenize(question)
    if not terms:
        return []
    index = load_index()
    scored = []
    for row in index:
        haystack = (row.get("search_text") or row.get("text") or "").lower()
        score = sum(haystack.count(term) for term in terms)
        # Small boost for chapter title/location matches.
        meta = f"{row.get('chapter_title','')} {row.get('primary_locations','')}".lower()
        score += 2 * sum(term in meta for term in terms)
        if score > 0:
            out = dict(row)
            out["score"] = score
            scored.append(out)
    scored.sort(key=lambda x: x["score"], reverse=True)
    return scored[:limit]


def make_retrieval_only_answer(question: str, passages: List[Dict[str, Any]]) -> str:
    if not passages:
        return "I could not find a strong matching passage in the current search index. Try a more specific name, place, chapter, or event."
    bullets = []
    for p in passages[:3]:
        bullets.append(f"- {p.get('source_label', p.get('id'))}: {p.get('excerpt','')}")
    return "I found these likely source passages:\n" + "\n".join(bullets)


def call_openai(question: str, passages: List[Dict[str, Any]]) -> str:
    # Keep dependency-free for now. Add the official OpenAI Python SDK during deployment if desired.
    # For production, use the Responses API, set store=false when appropriate, and pass retrieved passages as context.
    raise NotImplementedError("OpenAI call is intentionally stubbed. Use retrieval-only mode until model credentials are configured.")


def call_bedrock(question: str, passages: List[Dict[str, Any]]) -> str:
    # For production AWS-native RAG, prefer Bedrock Knowledge Bases RetrieveAndGenerate.
    # This stub is where direct InvokeModel/Converse logic would go if using custom retrieval.
    raise NotImplementedError("Bedrock call is intentionally stubbed. Use retrieval-only mode until model credentials are configured.")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return response(204, {})

    try:
        body = event.get("body") or "{}"
        if event.get("isBase64Encoded"):
            return response(400, {"error": "Base64 request bodies are not supported."})
        payload = json.loads(body) if isinstance(body, str) else body
        question = (payload.get("question") or payload.get("q") or "").strip()
        if not question:
            return response(400, {"error": "Missing question."})

        passages = retrieve_passages(question, limit=int(payload.get("limit", 5)))
        provider = os.getenv("MODEL_PROVIDER", "none").lower()

        if provider == "openai":
            answer = call_openai(question, passages)
        elif provider == "bedrock":
            answer = call_bedrock(question, passages)
        else:
            answer = make_retrieval_only_answer(question, passages)

        citations = [
            {
                "id": p.get("id"),
                "source_label": p.get("source_label"),
                "chapter": p.get("chapter"),
                "chapter_title": p.get("chapter_title"),
                "excerpt": p.get("excerpt"),
                "score": p.get("score"),
            }
            for p in passages
        ]
        return response(200, {"answer": answer, "citations": citations})
    except Exception as exc:  # noqa: BLE001 - Lambda should return JSON errors, not HTML tracebacks.
        return response(500, {"error": str(exc)})
