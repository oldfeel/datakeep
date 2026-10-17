#!/usr/bin/env python3
"""构建生物名录 SQLite。

默认：写入联调用的代表性样本（数百种），不下载全库。
全库：见 --from-dwca（Catalogue of Life / GBIF DwC-A Taxon.tsv）。

用法:
  python3 scripts/build_taxa_db.py
  python3 scripts/build_taxa_db.py --out seed/taxa.sqlite
  python3 scripts/build_taxa_db.py --from-dwca /path/to/Taxon.tsv --out data/taxa.sqlite
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

RANKS = ("kingdom", "phylum", "class", "order", "family", "genus", "species")

# 代表性分类树：界→…→种（学名, 中文名）
# 仅用于示例联调；全库请用 --from-dwca
SAMPLE_TREE: dict = {
    "Animalia|动物界": {
        "Chordata|脊索动物门": {
            "Mammalia|哺乳纲": {
                "Carnivora|食肉目": {
                    "Felidae|猫科": {
                        "Felis|猫属": [
                            ("Felis catus", "家猫"),
                            ("Felis silvestris", "野猫"),
                            ("Felis chaus", "丛林猫"),
                            ("Felis margarita", "沙猫"),
                            ("Felis nigripes", "黑足猫"),
                        ],
                        "Panthera|豹属": [
                            ("Panthera leo", "狮"),
                            ("Panthera tigris", "虎"),
                            ("Panthera pardus", "豹"),
                            ("Panthera onca", "美洲豹"),
                            ("Panthera uncia", "雪豹"),
                        ],
                        "Lynx|猞猁属": [
                            ("Lynx lynx", "猞猁"),
                            ("Lynx rufus", "短尾猫"),
                            ("Lynx canadensis", "加拿大猞猁"),
                            ("Lynx pardinus", "伊比利亚猞猁"),
                        ],
                        "Acinonyx|猎豹属": [
                            ("Acinonyx jubatus", "猎豹"),
                        ],
                    },
                    "Canidae|犬科": {
                        "Canis|犬属": [
                            ("Canis lupus", "灰狼"),
                            ("Canis familiaris", "家犬"),
                            ("Canis latrans", "郊狼"),
                            ("Canis aureus", "金豺"),
                        ],
                        "Vulpes|狐属": [
                            ("Vulpes vulpes", "赤狐"),
                            ("Vulpes lagopus", "北极狐"),
                            ("Vulpes zerda", "耳廓狐"),
                        ],
                    },
                    "Ursidae|熊科": {
                        "Ursus|熊属": [
                            ("Ursus arctos", "棕熊"),
                            ("Ursus americanus", "美洲黑熊"),
                            ("Ursus maritimus", "北极熊"),
                        ],
                        "Ailuropoda|大熊猫属": [
                            ("Ailuropoda melanoleuca", "大熊猫"),
                        ],
                    },
                },
                "Primates|灵长目": {
                    "Hominidae|人科": {
                        "Homo|人属": [
                            ("Homo sapiens", "智人"),
                        ],
                        "Pan|黑猩猩属": [
                            ("Pan troglodytes", "黑猩猩"),
                            ("Pan paniscus", "倭黑猩猩"),
                        ],
                        "Gorilla|大猩猩属": [
                            ("Gorilla gorilla", "西部大猩猩"),
                            ("Gorilla beringei", "东部大猩猩"),
                        ],
                    },
                },
                "Rodentia|啮齿目": {
                    "Muridae|鼠科": {
                        "Mus|小鼠属": [
                            ("Mus musculus", "小家鼠"),
                        ],
                        "Rattus|大鼠属": [
                            ("Rattus norvegicus", "褐家鼠"),
                            ("Rattus rattus", "黑家鼠"),
                        ],
                    },
                },
            },
            "Aves|鸟纲": {
                "Passeriformes|雀形目": {
                    "Corvidae|鸦科": {
                        "Corvus|鸦属": [
                            ("Corvus corax", "渡鸦"),
                            ("Corvus corone", "小嘴乌鸦"),
                            ("Corvus frugilegus", "秃鼻乌鸦"),
                        ],
                        "Pica|喜鹊属": [
                            ("Pica pica", "喜鹊"),
                        ],
                    },
                    "Paridae|山雀科": {
                        "Parus|山雀属": [
                            ("Parus major", "大山雀"),
                        ],
                    },
                },
                "Anseriformes|雁形目": {
                    "Anatidae|鸭科": {
                        "Anas|鸭属": [
                            ("Anas platyrhynchos", "绿头鸭"),
                        ],
                        "Cygnus|天鹅属": [
                            ("Cygnus cygnus", "大天鹅"),
                            ("Cygnus olor", "疣鼻天鹅"),
                        ],
                    },
                },
            },
            "Actinopterygii|辐鳍鱼纲": {
                "Cypriniformes|鲤形目": {
                    "Cyprinidae|鲤科": {
                        "Cyprinus|鲤属": [
                            ("Cyprinus carpio", "鲤"),
                        ],
                        "Carassius|鲫属": [
                            ("Carassius auratus", "鲫"),
                        ],
                    },
                },
            },
        },
        "Arthropoda|节肢动物门": {
            "Insecta|昆虫纲": {
                "Lepidoptera|鳞翅目": {
                    "Nymphalidae|蛱蝶科": {
                        "Danaus|斑蝶属": [
                            ("Danaus plexippus", "君主斑蝶"),
                        ],
                    },
                },
                "Hymenoptera|膜翅目": {
                    "Apidae|蜜蜂科": {
                        "Apis|蜜蜂属": [
                            ("Apis mellifera", "西方蜜蜂"),
                            ("Apis cerana", "东方蜜蜂"),
                        ],
                    },
                },
            },
        },
    },
    "Plantae|植物界": {
        "Tracheophyta|维管植物门": {
            "Magnoliopsida|木兰纲": {
                "Rosales|蔷薇目": {
                    "Rosaceae|蔷薇科": {
                        "Rosa|蔷薇属": [
                            ("Rosa chinensis", "月季"),
                            ("Rosa rugosa", "玫瑰"),
                        ],
                        "Malus|苹果属": [
                            ("Malus domestica", "苹果"),
                            ("Malus sieversii", "新疆野苹果"),
                        ],
                    },
                },
                "Poales|禾本目": {
                    "Poaceae|禾本科": {
                        "Oryza|稻属": [
                            ("Oryza sativa", "水稻"),
                        ],
                        "Triticum|小麦属": [
                            ("Triticum aestivum", "普通小麦"),
                        ],
                        "Zea|玉米属": [
                            ("Zea mays", "玉米"),
                        ],
                    },
                },
            },
        },
    },
    "Fungi|真菌界": {
        "Basidiomycota|担子菌门": {
            "Agaricomycetes|伞菌纲": {
                "Agaricales|伞菌目": {
                    "Agaricaceae|伞菌科": {
                        "Agaricus|蘑菇属": [
                            ("Agaricus bisporus", "双孢蘑菇"),
                        ],
                    },
                },
            },
        },
    },
}


SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS taxa (
  id INTEGER PRIMARY KEY,
  parent_id INTEGER,
  rank TEXT NOT NULL,
  scientific_name TEXT NOT NULL,
  common_name TEXT,
  depth INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_taxa_parent ON taxa(parent_id);
CREATE INDEX IF NOT EXISTS idx_taxa_rank ON taxa(rank);
CREATE INDEX IF NOT EXISTS idx_taxa_sci ON taxa(scientific_name);
CREATE INDEX IF NOT EXISTS idx_taxa_common ON taxa(common_name);
CREATE VIRTUAL TABLE IF NOT EXISTS taxa_fts USING fts5(
  scientific_name, common_name, content='taxa', content_rowid='id'
);
"""


def _split_label(label: str) -> tuple[str, str]:
    if "|" in label:
        sci, common = label.split("|", 1)
        return sci.strip(), common.strip()
    return label.strip(), ""


def insert_sample(conn: sqlite3.Connection) -> int:
    next_id = 1

    def add(parent_id: int | None, rank: str, sci: str, common: str, depth: int) -> int:
        nonlocal next_id
        tid = next_id
        next_id += 1
        conn.execute(
            "INSERT INTO taxa(id, parent_id, rank, scientific_name, common_name, depth) VALUES (?,?,?,?,?,?)",
            (tid, parent_id, rank, sci, common or None, depth),
        )
        return tid

    def walk(node: dict | list, parent_id: int | None, depth: int) -> None:
        if isinstance(node, list):
            for sci, common in node:
                add(parent_id, "species", sci, common, depth)
            return
        rank = RANKS[depth]
        for label, child in node.items():
            sci, common = _split_label(label)
            tid = add(parent_id, rank, sci, common, depth)
            walk(child, tid, depth + 1)

    walk(SAMPLE_TREE, None, 0)
    conn.execute(
        "INSERT INTO taxa_fts(rowid, scientific_name, common_name) "
        "SELECT id, scientific_name, COALESCE(common_name, '') FROM taxa"
    )
    return next_id - 1


def import_dwca(conn: sqlite3.Connection, tsv_path: Path, limit: int | None) -> int:
    """从 DwC-A Taxon.tsv 导入（需含 taxonID, parentNameUsageID, taxonRank, scientificName）。

    中文名若无 vernacular 列则留空。全库可达数百万行，耗时与体积较大。
    """
    import csv

    # 先读入再建 parent 映射（两遍：登记 id，再写行）
    rows: list[tuple] = []
    with tsv_path.open("r", encoding="utf-8", errors="replace", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for i, row in enumerate(reader):
            if limit is not None and i >= limit:
                break
            tid = (row.get("taxonID") or row.get("id") or "").strip()
            if not tid:
                continue
            parent = (row.get("parentNameUsageID") or row.get("parent_id") or "").strip() or None
            rank = (row.get("taxonRank") or row.get("rank") or "species").strip().lower()
            sci = (row.get("scientificName") or row.get("scientific_name") or "").strip()
            if not sci:
                continue
            common = (row.get("vernacularName") or row.get("common_name") or "").strip() or None
            rows.append((tid, parent, rank, sci, common))

    # 用字符串 id → 整数映射
    id_map: dict[str, int] = {}
    for i, (tid, *_rest) in enumerate(rows, start=1):
        id_map[tid] = i

    for tid, parent, rank, sci, common in rows:
        pid = id_map.get(parent) if parent else None
        depth = RANKS.index(rank) if rank in RANKS else 6
        conn.execute(
            "INSERT INTO taxa(id, parent_id, rank, scientific_name, common_name, depth) VALUES (?,?,?,?,?,?)",
            (id_map[tid], pid, rank, sci, common, depth),
        )

    conn.execute(
        "INSERT INTO taxa_fts(rowid, scientific_name, common_name) "
        "SELECT id, scientific_name, COALESCE(common_name, '') FROM taxa"
    )
    return len(rows)


def build(out: Path, from_dwca: Path | None, limit: int | None, version: str) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    conn = sqlite3.connect(str(out))
    try:
        conn.executescript(SCHEMA)
        if from_dwca:
            n = import_dwca(conn, from_dwca, limit)
            source = f"dwca:{from_dwca.name}"
        else:
            n = insert_sample(conn)
            source = "sample"
        conn.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('version', ?)", (version,))
        conn.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('source', ?)", (source,))
        conn.execute(
            "INSERT OR REPLACE INTO meta(key, value) VALUES ('license', ?)",
            ("Sample: CC0 for demo taxa. Full COL/GBIF: see respective licenses.",),
        )
        conn.execute(
            "INSERT OR REPLACE INTO meta(key, value) VALUES ('species_count', ?)",
            (str(conn.execute("SELECT COUNT(*) FROM taxa WHERE rank='species'").fetchone()[0]),),
        )
        conn.commit()
        print(f"Wrote {out} ({n} taxa rows, source={source})")
    finally:
        conn.close()


def main() -> int:
    ap = argparse.ArgumentParser(description="Build taxa.sqlite for bio-app")
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", type=Path, default=root / "seed" / "taxa.sqlite")
    ap.add_argument("--from-dwca", type=Path, default=None, help="DwC-A Taxon.tsv path")
    ap.add_argument("--limit", type=int, default=None, help="Max rows when importing DwC-A")
    ap.add_argument("--version", default="0.1.0-sample")
    args = ap.parse_args()
    build(args.out, args.from_dwca, args.limit, args.version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
