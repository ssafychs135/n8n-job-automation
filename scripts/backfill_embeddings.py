#!/usr/bin/env python3
# 기존 done 공고(embedding IS NULL)를 KURE-v1로 일괄 임베딩하는 일회성 백필.
# 상시 임베딩은 n8n 05-embedder 워크플로우가 담당. 이 스크립트는 대량 초기 적재용.
import json, urllib.request, sys
import psycopg2

PG = dict(host="localhost", port=5432, dbname="jobs", user="n8n", password="change_me_local_pw")
LM_URL = "http://localhost:1234/v1/embeddings"
MODEL = "text-embedding-kure-v1"
BATCH = 16

def embed(texts):
    req = urllib.request.Request(
        LM_URL,
        data=json.dumps({"model": MODEL, "input": texts}).encode(),
        headers={"Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=120))
    return [d["embedding"] for d in r["data"]]

def main():
    conn = psycopg2.connect(**PG); conn.autocommit = False
    cur = conn.cursor()
    cur.execute("SELECT id, title, summary, tech_stacks FROM jobs "
                "WHERE status='done' AND embedding IS NULL ORDER BY id")
    rows = cur.fetchall()
    total = len(rows)
    print(f"백필 대상: {total}건")
    done = 0
    for i in range(0, total, BATCH):
        chunk = rows[i:i+BATCH]
        texts = []
        for _id, title, summary, stacks in chunk:
            st = ", ".join([s for s in (stacks or []) if s])
            texts.append("\n".join([p for p in (title, summary, st) if p]))
        embs = embed(texts)
        for (_id, *_), emb in zip(chunk, embs):
            if len(emb) != 1024:
                print(f"  ⚠️ id={_id} dim={len(emb)} 스킵"); continue
            cur.execute("UPDATE jobs SET embedding=%s::vector, updated_at=now() WHERE id=%s",
                        ("[" + ",".join(map(repr, emb)) + "]", _id))
        conn.commit()
        done += len(chunk)
        print(f"  {done}/{total}")
    cur.execute("SELECT count(*) FROM jobs WHERE status='done' AND embedding IS NULL")
    print("남은 미임베딩:", cur.fetchone()[0])
    conn.close()

if __name__ == "__main__":
    main()
