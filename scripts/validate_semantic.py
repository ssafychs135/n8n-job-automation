#!/usr/bin/env python3
# 검증: 같은 질문에 대해 키워드검색(ILIKE) vs 의미검색(pgvector) 비교.
# 키워드가 놓친 관련 공고를 의미검색이 잡는지 입증.
import json, urllib.request, os
import psycopg2

def _env(key):
    p = os.path.join(os.path.dirname(__file__), "..", ".env")
    try:
        for line in open(p):
            if line.startswith(key + "="):
                return line.split("=", 1)[1].strip()
    except FileNotFoundError:
        pass
    return os.environ.get(key, "")

PG = dict(host="localhost", port=5432, dbname="jobs", user="n8n", password=_env("POSTGRES_PASSWORD"))

def embed(text):
    req = urllib.request.Request("http://localhost:1234/v1/embeddings",
        data=json.dumps({"model": "text-embedding-kure-v1", "input": text}).encode(),
        headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=60))["data"][0]["embedding"]

QUERIES = ["프롬프트 엔지니어링", "LLM 서비스 개발", "쿠버네티스 인프라 운영",
           "추천 시스템", "데이터 파이프라인 구축", "MLOps 엔지니어"]

conn = psycopg2.connect(**PG); cur = conn.cursor()

def keyword_hits(q):
    # 관대한 키워드검색: 각 토큰을 title/summary에서 OR ILIKE
    toks = [t for t in q.split() if len(t) >= 2]
    if not toks: return set()
    cond = " OR ".join(["(title ILIKE %s OR summary ILIKE %s)"] * len(toks))
    params = []
    for t in toks: params += [f"%{t}%", f"%{t}%"]
    cur.execute(f"SELECT id FROM jobs WHERE status='done' AND ({cond})", params)
    return {r[0] for r in cur.fetchall()}

for q in QUERIES:
    kw = keyword_hits(q)
    vec = "[" + ",".join(map(repr, embed(q))) + "]"
    cur.execute(
        "SELECT id, company, title, round((1-(embedding <=> %s::vector))::numeric,3) AS score "
        "FROM jobs WHERE status='done' AND embedding IS NOT NULL "
        "ORDER BY embedding <=> %s::vector LIMIT 5", (vec, vec))
    top = cur.fetchall()
    print("=" * 70)
    print(f"질문: '{q}'")
    print(f"  키워드검색(관대) 매칭: {len(kw)}건")
    print(f"  의미검색 Top5:")
    for _id, company, title, score in top:
        mark = "🔑키워드에도O" if _id in kw else "✨의미검색만"
        t = (title or "")[:40]
        print(f"    [{score}] {company} — {t}  {mark}")
conn.close()
