/* global Vue, initSqlJs */
(function () {
  'use strict';

  const DATA_URL = '/__datakeep/data/taxa.sqlite';
  const SEED_URL = './seed/taxa.sqlite';
  const META_URL = '/__datakeep/data/taxa.meta.json';

  const CHILD_LIMIT = 400;   // 单个节点最多取多少子级（树 / 导图）
  const COL_W = 228;         // 导图列宽
  const ROW_H = 52;          // 导图叶节点行高
  const NODE_H = 36;         // 节点高度

  /* ---- 大数据集性能相关常量 ---- */
  const TREE_ROW_PX = 30;        // 左树单行高度（与 app.css .tnode height 一致）
  const TREE_VIRTUAL_MIN = 260;  // 展开行数超过这个值才启用窗口化渲染
  const TREE_OVERSCAN = 8;       // 窗口上下各多渲染几行，滚动时不闪白
  const MIND_MAX_KID = 60;       // 导图里单层最多铺开多少子级（其余折叠为「还有 N 个」）
  const MIND_MAX_SIB = 60;       // 种节点同级最多展示多少条
  const LIST_PAGE = 160;         // 卡片列表每页条数（按页查询，避免一次取几十万行）
  const SIB_MAX = 60;            // 同属物种条数上限
  const INDEX_REV = 'idx1';      // 索引版本：改动索引定义时 +1 会触发一次重建

  const CHAIN_COLOR = '#3f6a59';
  const PALETTE = ['#3dba8a', '#5aa6ff', '#f0b23c', '#e0739b', '#9b8cff', '#45cfc4', '#ff8f66', '#a8d96a'];

  const RANK_ZH = {
    kingdom: '界', phylum: '门', class: '纲', order: '目',
    family: '科', genus: '属', species: '种',
  };
  const RANK_CASE =
    "CASE rank WHEN 'kingdom' THEN 0 WHEN 'phylum' THEN 1 WHEN 'class' THEN 2 " +
    "WHEN 'order' THEN 3 WHEN 'family' THEN 4 WHEN 'genus' THEN 5 " +
    "WHEN 'species' THEN 6 ELSE 7 END";
  const COLS = 'id, parent_id, rank, scientific_name, common_name, depth';

  const DEFAULT_LADDER = ['kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species'];
  const SAMPLE_ID_BASE = 900001;    // 示例节点 id 起点，避开真实库 id
  const SAMPLE_ID_SPAN = 200000;    // 示例 id 保留区间长度
  const SAMPLE_ID_MAX = SAMPLE_ID_BASE + SAMPLE_ID_SPAN - 1;
  const SAMPLE_REV = 'r2';          // 示例装载逻辑版本：+1 会触发一次全量清空重写

  function rankLabel(r) {
    return RANK_ZH[r] || r || '';
  }

  async function fetchBytes(url) {
    const res = await fetch(url, { cache: 'no-store' });
    if (!res.ok) throw new Error(String(res.status));
    return new Uint8Array(await res.arrayBuffer());
  }

  async function putBytes(url, bytes, contentType) {
    const res = await fetch(url, {
      method: 'PUT',
      headers: { 'Content-Type': contentType || 'application/octet-stream' },
      body: bytes,
    });
    if (!res.ok) throw new Error('写入失败 ' + res.status);
  }

  /** 读 meta 表（表不存在 / 键不存在都返回 ''） */
  function dbGetMeta(database, key) {
    try {
      const r = database.exec('SELECT value FROM meta WHERE key=?', [key]);
      const v = r[0] && r[0].values && r[0].values[0] && r[0].values[0][0];
      return v == null ? '' : String(v);
    } catch (_) {
      return '';
    }
  }

  function dbPutMeta(database, key, value) {
    database.run('INSERT OR REPLACE INTO meta (key, value) VALUES (?,?)', [key, String(value)]);
  }

  function dbCount(database, sql) {
    try {
      const r = database.exec(sql);
      const v = r[0] && r[0].values && r[0].values[0] && r[0].values[0][0];
      return v || 0;
    } catch (_) {
      return 0;
    }
  }

  const { createApp, ref, computed, onMounted, nextTick } = Vue;

  createApp({
    setup() {
      const title = ref('生物');
      const error = ref('');
      const loadingDb = ref(false);
      const hasDataDb = ref(false);
      const dbMeta = ref(null);
      const statusText = ref('');
      const resetArmed = ref(false);   // 「清空并重写」二次确认

      const treeOpen = ref(false);
      const treeEl = ref(null);
      const mindEl = ref(null);
      const listEl = ref(null);

      const query = ref('');
      const candidates = ref([]);
      const candidateIndex = ref(0);

      const selected = ref(null);
      const pathNodes = ref([]);
      const childrenMap = ref({});   // 'root' | id -> rows
      const expanded = ref({});      // 左侧树展开状态
      const mindExpanded = ref({});  // 导图内联展开状态

      /* ---- 视图切换：list（默认，逐级下钻的卡片列表）/ mind（思维导图） ---- */
      const viewMode = ref('list');

      /* ---- 卡片列表状态 ---- */
      const listRows = ref([]);        // 当前节点的直接子级（分页追加）
      const listTotal = ref(0);        // 当前节点直接子级总数
      const childCounts = ref({});     // 子级 id -> 下级数量
      const siblingRows = ref([]);     // 同属其它种
      const siblingTotal = ref(0);

      const mindNodes = ref([]);
      const mindLinks = ref([]);
      const mindW = ref(420);
      const mindH = ref(220);
      const zoom = ref(1);
      const selPos = ref({ x: 0, y: 0 });
      const panMoved = ref(false);

      // 左树窗口化滚动状态
      const treeScrollTop = ref(0);
      const treeViewH = ref(0);

      let db = null;
      let SQL = null;
      let searchTimer = null;
      let resetTimer = null;
      let autoFitPending = true;
      let sampleCache = null;
      let ftsReady = null;           // null=未探测，true/false=是否可用
      let speciesCache = -1;         // -1=未缓存
      let nodeCache = -1;
      let treeRaf = 0;

      const nodeH = NODE_H;
      const zoomPct = computed(() => Math.round(zoom.value * 100) + '%');

      /* ---------------- 数据库小工具 ---------------- */

      function metaGet(key) {
        if (!db) return '';
        return dbGetMeta(db, key);
      }

      /** 计数走缓存 / meta，避免每次刷新都对全表 COUNT(*) */
      function countSpecies() {
        if (speciesCache >= 0) return speciesCache;
        if (!db) return 0;
        const fromMeta = parseInt(metaGet('species_count'), 10);
        speciesCache = isFinite(fromMeta) && fromMeta > 0
          ? fromMeta
          : dbCount(db, "SELECT COUNT(*) FROM taxa WHERE rank='species'");
        return speciesCache;
      }

      function countNodes() {
        if (nodeCache >= 0) return nodeCache;
        if (!db) return 0;
        const fromMeta = parseInt(metaGet('node_count'), 10);
        nodeCache = isFinite(fromMeta) && fromMeta > 0 ? fromMeta : dbCount(db, 'SELECT COUNT(*) FROM taxa');
        return nodeCache;
      }

      function refreshMeta() {
        dbMeta.value = {
          version: metaGet('version') || '?',
          species_count: String(countSpecies()),
          source: metaGet('source') || '',
        };
      }

      function rowFrom(vals) {
        return {
          id: vals[0],
          parent_id: vals[1],
          rank: vals[2],
          scientific_name: vals[3],
          common_name: vals[4] || '',
          depth: vals[5] == null ? 0 : vals[5],
        };
      }

      function queryRows(sql, params) {
        if (!db) return [];
        const stmt = db.prepare(sql);
        try {
          if (params) stmt.bind(params);
          const out = [];
          while (stmt.step()) out.push(rowFrom(stmt.get()));
          return out;
        } finally {
          stmt.free();
        }
      }

      function hasFts() {
        if (ftsReady !== null) return ftsReady;
        ftsReady = false;
        if (db) {
          try {
            const r = db.exec("SELECT 1 FROM sqlite_master WHERE type IN ('table','view') AND name='taxa_fts' LIMIT 1");
            ftsReady = !!(r[0] && r[0].values && r[0].values.length);
          } catch (_) { /* ignore */ }
        }
        return ftsReady;
      }

      /** 懒加载子级；key 为 'root'（顶层）或节点 id */
      function loadChildren(key) {
        const cache = childrenMap.value;
        if (Object.prototype.hasOwnProperty.call(cache, key)) return cache[key];
        let rows = [];
        if (db) {
          try {
            if (key === 'root') {
              rows = queryRows(
                'SELECT ' + COLS + ' FROM taxa WHERE parent_id IS NULL ORDER BY ' + RANK_CASE + ', scientific_name LIMIT ?',
                [CHILD_LIMIT]
              );
              if (!rows.length) {
                rows = queryRows(
                  'SELECT ' + COLS + ' FROM taxa WHERE depth=0 ORDER BY ' + RANK_CASE + ', scientific_name LIMIT ?',
                  [CHILD_LIMIT]
                );
              }
            } else {
              rows = queryRows(
                'SELECT ' + COLS + ' FROM taxa WHERE parent_id=? ORDER BY ' + RANK_CASE + ', scientific_name LIMIT ?',
                [key, CHILD_LIMIT]
              );
            }
          } catch (_) {
            rows = [];
          }
        }
        // 直接在响应式对象上加键（Vue 3 代理可追踪新增键），
        // 避免旧写法 Object.assign({}, cache, …) 每次展开都整表复制
        childrenMap.value[key] = rows;
        return rows;
      }

      /* ---------------- 按页取子级（卡片列表用） ---------------- */

      /** 某个父节点下有多少直接子级（走 parent_id 索引，很快） */
      function countChildren(parentId) {
        if (!db) return 0;
        try {
          const r = parentId == null
            ? db.exec('SELECT COUNT(*) FROM taxa WHERE parent_id IS NULL')
            : db.exec('SELECT COUNT(*) FROM taxa WHERE parent_id=?', [parentId]);
          const v = r[0] && r[0].values && r[0].values[0] && r[0].values[0][0];
          return v || 0;
        } catch (_) {
          return 0;
        }
      }

      /** 分页取直接子级：LIMIT/OFFSET，只要一屏，永远不整层拉下来 */
      function fetchChildren(parentId, offset, limit) {
        if (!db) return [];
        const where = parentId == null ? 'parent_id IS NULL' : 'parent_id=?';
        const params = parentId == null ? [] : [parentId];
        let rows = [];
        try {
          rows = queryRows(
            'SELECT ' + COLS + ' FROM taxa WHERE ' + where +
            ' ORDER BY ' + RANK_CASE + ', scientific_name LIMIT ? OFFSET ?',
            params.concat([limit, offset])
          );
        } catch (_) {
          rows = [];
        }
        if (!rows.length && parentId == null && offset === 0) {
          try {
            rows = queryRows(
              'SELECT ' + COLS + ' FROM taxa WHERE depth=0 ORDER BY ' + RANK_CASE + ', scientific_name LIMIT ?',
              [limit]
            );
          } catch (_) { /* ignore */ }
        }
        return rows;
      }

      /**
       * 批量取「这些节点各自有几个子级」——一条 GROUP BY 搞定，
       * 而不是每张卡片单独 COUNT（那会是 N 次查询，数据一多就卡死）。
       */
      function grandCounts(ids) {
        const out = {};
        if (!db || !ids.length) return out;
        const CHUNK = 300;   // 避免 SQL 变量个数超限
        for (let i = 0; i < ids.length; i += CHUNK) {
          const part = ids.slice(i, i + CHUNK);
          const qs = part.map(function () { return '?'; }).join(',');
          try {
            const r = db.exec(
              'SELECT parent_id, COUNT(*) FROM taxa WHERE parent_id IN (' + qs + ') GROUP BY parent_id',
              part
            );
            const vals = (r[0] && r[0].values) || [];
            for (let j = 0; j < vals.length; j++) out[vals[j][0]] = vals[j][1];
          } catch (_) { /* ignore */ }
        }
        return out;
      }

      /* ---------------- 卡片列表 ---------------- */

      function refreshList() {
        const sel = selected.value;
        childCounts.value = {};
        siblingRows.value = [];
        siblingTotal.value = 0;
        if (!sel || !db) {
          listRows.value = [];
          listTotal.value = 0;
          return;
        }
        listTotal.value = countChildren(sel.id);
        listRows.value = fetchChildren(sel.id, 0, LIST_PAGE);
        childCounts.value = grandCounts(listRows.value.map(function (r) { return r.id; }));

        // 种：没有下级时给出同属其它种，方便横向比较
        if (sel.parent_id != null) {
          const total = countChildren(sel.parent_id);
          siblingTotal.value = Math.max(0, total - 1);
          if (siblingTotal.value > 0) {
            siblingRows.value = fetchChildren(sel.parent_id, 0, SIB_MAX + 1)
              .filter(function (r) { return r.id !== sel.id; })
              .slice(0, SIB_MAX);
          }
        }
      }

      function loadMoreList() {
        const sel = selected.value;
        if (!sel || !db) return;
        const more = fetchChildren(sel.id, listRows.value.length, LIST_PAGE);
        if (!more.length) {
          listTotal.value = listRows.value.length;
          return;
        }
        listRows.value = listRows.value.concat(more);
        const add = grandCounts(more.map(function (r) { return r.id; }));
        const merged = Object.assign({}, childCounts.value);
        for (const k in add) if (Object.prototype.hasOwnProperty.call(add, k)) merged[k] = add[k];
        childCounts.value = merged;
      }

      function pickRow(row) {
        selectTaxon({
          id: row.id,
          rank: row.rank,
          scientific_name: row.scientific_name,
          common_name: row.common_name,
        });
      }

      function goUp() {
        const path = pathNodes.value;
        if (path.length < 2) return;
        pickRow(path[path.length - 2]);
      }

      function setView(mode) {
        if (viewMode.value === mode) return;
        viewMode.value = mode;
        if (mode === 'mind') rebuildMind();
        else refreshList();
      }

      /* ---------------- 内置示例名录（sample-taxa.js） ---------------- */

      /**
       * 把 window.SAMPLE_TAXA 的嵌套数组摊平成 taxa 行，id 从 SAMPLE_ID_BASE 起连续分配。
       * 同一父级下学名相同的重复条目会被自动合并（合并到先出现的那条上），
       * 保证写库时不会出现重复节点。
       */
      function sampleRows() {
        if (sampleCache) return sampleCache;
        const bundle = typeof window !== 'undefined' ? window.SAMPLE_TAXA : null;
        const rows = [];
        if (!bundle || !Array.isArray(bundle.tree)) {
          sampleCache = rows;
          return rows;
        }
        const ladder = Array.isArray(bundle.ladder) && bundle.ladder.length ? bundle.ladder : DEFAULT_LADDER;
        let nextId = SAMPLE_ID_BASE;
        const idByKey = Object.create(null);

        const walk = (list, parentId, depth) => {
          for (let i = 0; i < list.length; i++) {
            const n = list[i];
            if (!Array.isArray(n) || !n.length) continue;
            const common = (n[0] || '').trim();
            const sci = (n[1] || '').trim() || common;
            const kids = Array.isArray(n[2]) ? n[2] : [];
            const key = (parentId == null ? 'root' : String(parentId)) + '|' + sci.toLowerCase();
            let id = idByKey[key];
            if (id == null) {
              id = nextId++;
              idByKey[key] = id;
              rows.push({
                id: id,
                parent_id: parentId,
                rank: ladder[Math.min(depth, ladder.length - 1)],
                scientific_name: sci,
                common_name: common,
                depth: depth,
              });
            }
            if (kids.length) walk(kids, id, depth + 1);
          }
        };
        walk(bundle.tree, null, 0);
        sampleCache = rows;
        return rows;
      }

      /** 示例版本 = 数据文件版本 + 装载逻辑版本，任一变化都会触发清空重写 */
      function sampleVersion() {
        const bundle = typeof window !== 'undefined' ? window.SAMPLE_TAXA : null;
        const v = (bundle && bundle.version) || 'sample';
        return v + '+' + SAMPLE_REV;
      }

      /** 记录在 meta 里的示例 id 区间（含旧版本兜底区间） */
      function sampleIdRanges(work) {
        const ranges = [];
        const lo = parseInt(dbGetMeta(work, 'sample_min_id'), 10);
        const hi = parseInt(dbGetMeta(work, 'sample_max_id'), 10);
        if (isFinite(lo) && isFinite(hi) && hi >= lo) ranges.push([lo, hi]);
        ranges.push([SAMPLE_ID_BASE, SAMPLE_ID_MAX]);
        return ranges;
      }

      /**
       * 关键索引：只有建过 parent_id 索引，展开/取同级才不会全表扫描。
       * 建一次记进 meta.index_rev，之后就零成本（导出后写回 data/ 可持久化）。
       */
      function ensureIndexes(work) {
        if (dbGetMeta(work, 'index_rev') === INDEX_REV) return false;
        try {
          work.run('CREATE INDEX IF NOT EXISTS idx_taxa_parent ON taxa(parent_id)');
        } catch (_) { /* ignore */ }
        try {
          work.run('CREATE INDEX IF NOT EXISTS idx_taxa_parent_name ON taxa(parent_id, scientific_name)');
        } catch (_) { /* ignore */ }
        dbPutMeta(work, 'index_rev', INDEX_REV);
        return true;
      }

      /**
       * 把示例名录写入基库，返回 { bytes, dirty }（不改磁盘上的 seed 文件）。
       * - meta.sample_bundle 与当前版本一致时什么都不做
       * - 版本不同 / force=true 时：先删掉上一次写入的整个示例 id 区间，再整段重写
       *   → 天然幂等，重复运行不会产生重复行
       */
      async function prepareDbBytes(base, opts) {
        const force = !!(opts && opts.force);
        const rows = sampleRows();
        if (!SQL) SQL = await initSqlJs({ locateFile: (f) => './vendor/' + f });

        const version = sampleVersion();
        const work = base ? new SQL.Database(base) : new SQL.Database();
        let rewrote = false;
        try {
          work.run(
            'CREATE TABLE IF NOT EXISTS taxa (' +
            'id INTEGER PRIMARY KEY, parent_id INTEGER, rank TEXT, ' +
            'scientific_name TEXT, common_name TEXT, depth INTEGER)'
          );
          work.run('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)');

          const upToDate = !force && rows.length && dbGetMeta(work, 'sample_bundle') === version;

          if (!upToDate) {
            // 1) 清空旧示例节点（含历史版本可能残留的区间）
            const ranges = sampleIdRanges(work);
            for (let i = 0; i < ranges.length; i++) {
              try {
                work.run('DELETE FROM taxa WHERE id BETWEEN ? AND ?', [ranges[i][0], ranges[i][1]]);
              } catch (_) { /* ignore */ }
            }

            // 2) 整段重写
            const stmt = work.prepare(
              'INSERT OR REPLACE INTO taxa (id, parent_id, rank, scientific_name, common_name, depth) ' +
              'VALUES (?,?,?,?,?,?)'
            );
            try {
              for (let i = 0; i < rows.length; i++) {
                const r = rows[i];
                stmt.run([r.id, r.parent_id, r.rank, r.scientific_name, r.common_name, r.depth]);
              }
            } finally {
              try { stmt.free(); } catch (_) { /* ignore */ }
            }

            // 3) 兜底去重：同一父级 + 同一学名只保留一条（只作用于示例区间）
            try {
              work.run(
                'DELETE FROM taxa WHERE id BETWEEN ? AND ? AND id NOT IN (' +
                'SELECT MIN(id) FROM taxa GROUP BY IFNULL(parent_id, -1), scientific_name)',
                [SAMPLE_ID_BASE, SAMPLE_ID_MAX]
              );
            } catch (_) { /* ignore */ }

            dbPutMeta(work, 'sample_bundle', version);
            dbPutMeta(work, 'sample_min_id', SAMPLE_ID_BASE);
            dbPutMeta(work, 'sample_max_id', SAMPLE_ID_MAX);

            // 只有内容变了才重建 FTS —— 全库 rebuild 是分钟级操作，绝不能每次启动都跑
            try { work.run("INSERT INTO taxa_fts(taxa_fts) VALUES('rebuild')"); } catch (_) { /* 无 FTS 表 */ }
            rewrote = true;
          }

          const indexed = ensureIndexes(work);

          if (!upToDate) {
            if (!dbGetMeta(work, 'version')) dbPutMeta(work, 'version', '0.2.0-sample');
            if (!dbGetMeta(work, 'source')) dbPutMeta(work, 'source', '内置示例名录（6 界 43 门，演示用 CC0）');
            dbPutMeta(work, 'species_count', String(dbCount(work, "SELECT COUNT(*) FROM taxa WHERE rank='species'")));
            dbPutMeta(work, 'node_count', String(dbCount(work, 'SELECT COUNT(*) FROM taxa')));
          }

          return { bytes: work.export(), dirty: rewrote || indexed };
        } finally {
          try { work.close(); } catch (_) { /* ignore */ }
        }
      }

      async function writeDataDb(bytes) {
        await putBytes(DATA_URL, bytes, 'application/octet-stream');
        const meta = {
          version: dbMeta.value ? dbMeta.value.version : '',
          source: dbMeta.value ? dbMeta.value.source : '',
          installedAt: new Date().toISOString(),
          license: 'Sample taxa for demo (CC0). Full Catalogue of Life / GBIF: see their licenses.',
        };
        await putBytes(META_URL, new TextEncoder().encode(JSON.stringify(meta, null, 2)), 'application/json');
      }

      /* ---------------- 左侧树 ---------------- */

      // 注意：这里只依赖 childrenMap / expanded，不再依赖 selected，
      // 否则每次选中都会重建整棵树的行对象，深树时非常卡。
      const treeRows = computed(() => {
        const out = [];
        const cache = childrenMap.value;
        const exp = expanded.value;

        const walk = (list, depth) => {
          for (let i = 0; i < list.length; i++) {
            const n = list[i];
            const isExp = !!exp[n.id];
            out.push({
              id: n.id,
              rank: n.rank,
              name: n.common_name || n.scientific_name || '',
              sci: n.scientific_name || '',
              common: n.common_name || '',
              depth: depth,
              expanded: isExp,
              hasKids: n.rank !== 'species',
            });
            if (isExp) walk(cache[n.id] || [], depth + 1);
          }
        };
        walk(cache.root || [], 0);
        return out;
      });

      /** 窗口化：行数很多时只渲染视口内的一段，DOM 数量恒定 */
      const treeWindow = computed(() => {
        const rows = treeRows.value;
        const total = rows.length;
        const h = treeViewH.value;
        if (!h || total <= TREE_VIRTUAL_MIN) {
          return { rows: rows, top: 0, bottom: 0 };
        }
        const start = Math.max(0, Math.floor(treeScrollTop.value / TREE_ROW_PX) - TREE_OVERSCAN);
        const count = Math.ceil(h / TREE_ROW_PX) + TREE_OVERSCAN * 2;
        const end = Math.min(total, start + count);
        return {
          rows: rows.slice(start, end),
          top: start * TREE_ROW_PX,
          bottom: Math.max(0, (total - end) * TREE_ROW_PX),
        };
      });

      function syncTreeViewport() {
        const el = treeEl.value;
        if (!el) return;
        treeViewH.value = el.clientHeight;
        treeScrollTop.value = el.scrollTop;
      }

      function onTreeScroll() {
        if (treeRaf) return;
        const el = treeEl.value;
        if (!el) return;
        treeRaf = requestAnimationFrame(() => {
          treeRaf = 0;
          const box = treeEl.value;
          if (!box) return;
          treeScrollTop.value = box.scrollTop;
          treeViewH.value = box.clientHeight;
        });
      }

      function toggleTree(row) {
        if (expanded.value[row.id]) {
          delete expanded.value[row.id];
        } else {
          loadChildren(row.id);
          expanded.value[row.id] = true;
        }
      }

      function collapseAll() {
        expanded.value = {};
        nextTick(syncTreeViewport);
      }

      function pickTree(row) {
        selectTaxon({
          id: row.id,
          rank: row.rank,
          scientific_name: row.sci,
          common_name: row.common,
        });
      }

      /** 直接按行号定位滚动，不依赖 DOM（窗口化后节点可能没渲染出来） */
      function scrollTreeTo(id) {
        const el = treeEl.value;
        if (!el) return;
        const rows = treeRows.value;
        let idx = -1;
        for (let i = 0; i < rows.length; i++) {
          if (rows[i].id === id) { idx = i; break; }
        }
        if (idx < 0) return;
        const top = idx * TREE_ROW_PX;
        const view = el.clientHeight;
        if (top < el.scrollTop || top + TREE_ROW_PX > el.scrollTop + view) {
          el.scrollTop = Math.max(0, top - view / 2 + TREE_ROW_PX);
          treeScrollTop.value = el.scrollTop;
          treeViewH.value = view;
        }
      }

      /* ---------------- 选中 ---------------- */

      function selectTaxon(taxon) {
        if (!taxon || !db) return;
        let t = taxon;
        const fresh = queryRows('SELECT ' + COLS + ' FROM taxa WHERE id=?', [taxon.id]);
        if (fresh.length) t = fresh[0];

        const chain = getAncestors(t.id);
        selected.value = t;
        pathNodes.value = chain.concat([t]);

        loadChildren('root');
        for (let i = 0; i < chain.length; i++) {
          loadChildren(chain[i].id);
          expanded.value[chain[i].id] = true;
        }
        if (t.rank !== 'species') expanded.value[t.id] = true;
        loadChildren(t.id);

        // 只刷新当前视图：列表视图不必构建导图（省掉大量布局计算）
        if (viewMode.value === 'mind') rebuildMind();
        else refreshList();

        nextTick(() => {
          scrollTreeTo(t.id);
          if (listEl.value) listEl.value.scrollTop = 0;
          if (treeOpen.value && window.innerWidth <= 780) treeOpen.value = false;
        });
      }

      /**
       * 祖先链：一条递归 CTE 查完（旧实现每层 2 次查询，深链路上来要几十次往返）。
       * 返回从根到父节点的顺序。
       */
      function getAncestors(id) {
        if (!db) return [];
        try {
          return queryRows(
            'WITH RECURSIVE up(pid, lvl) AS (' +
            '  SELECT parent_id, 1 FROM taxa WHERE id=? AND parent_id IS NOT NULL' +
            '  UNION ALL' +
            '  SELECT t.parent_id, up.lvl+1 FROM taxa t JOIN up ON t.id=up.pid' +
            '  WHERE t.parent_id IS NOT NULL AND up.lvl < 32' +
            ') ' +
            'SELECT t.id, t.parent_id, t.rank, t.scientific_name, t.common_name, t.depth ' +
            'FROM up JOIN taxa t ON t.id=up.pid ORDER BY up.lvl DESC LIMIT 40',
            [id]
          );
        } catch (_) {
          return getAncestorsFallback(id);
        }
      }

      function getAncestorsFallback(id) {
        const chain = [];
        const seen = {};
        seen[id] = true;
        let cur = id;
        for (let i = 0; i < 24; i++) {
          const rows = queryRows('SELECT ' + COLS + ' FROM taxa WHERE id=?', [cur]);
          if (!rows.length) break;
          const pid = rows[0].parent_id;
          if (pid == null || seen[pid]) break;
          seen[pid] = true;
          const p = queryRows('SELECT ' + COLS + ' FROM taxa WHERE id=?', [pid]);
          if (!p.length) break;
          chain.unshift(p[0]);
          cur = pid;
        }
        return chain;
      }

      /* ---------------- 思维导图 ---------------- */

      function blankNode(t) {
        return {
          id: t.id,
          rank: t.rank,
          name: t.common_name || t.scientific_name || '',
          sci: t.scientific_name || '',
          common: t.common_name || '',
          children: [],
          x: 0,
          y: 0,
          w: 120,
          depth: 0,
          color: '',
          kind: 'leaf',
          hasKids: false,
          expanded: false,
        };
      }

      /** 「还有 N 个…」占位节点：避免一层上千个节点把 DOM / 布局拖死 */
      function moreNode(scope, hidden) {
        return {
          id: 'more:' + scope,
          rank: '',
          name: '还有 ' + hidden + ' 个…',
          sci: '',
          common: '',
          children: [],
          x: 0,
          y: 0,
          w: 128,
          depth: 0,
          color: '',
          kind: 'more',
          hasKids: false,
          expanded: false,
        };
      }

      function bezier(p, c) {
        const x1 = p.x + p.w;
        const y1 = p.y;
        const x2 = c.x;
        const y2 = c.y;
        const dx = Math.max(20, (x2 - x1) * 0.55);
        return (
          'M' + x1 + ',' + y1 +
          'C' + (x1 + dx) + ',' + y1 + ' ' + (x2 - dx) + ',' + y2 + ' ' + x2 + ',' + y2
        );
      }

      /** 取 list 中以 index 为中心、长度 max 的窗口 */
      function windowSlice(list, index, max) {
        if (list.length <= max) return { items: list, hidden: 0 };
        const half = Math.floor((max - 1) / 2);
        let start = Math.max(0, index - half);
        if (start + max > list.length) start = list.length - max;
        return { items: list.slice(start, start + max), hidden: list.length - max };
      }

      function childNodesOf(parentId, color, scope) {
        const kids = loadChildren(parentId) || [];
        const shown = kids.length > MIND_MAX_KID ? kids.slice(0, MIND_MAX_KID) : kids;
        const out = shown.map((k, i) => {
          const kn = blankNode(k);
          kn.kind = 'leaf';
          kn.color = color || PALETTE[i % PALETTE.length];
          kn.hasKids = k.rank !== 'species';
          return kn;
        });
        if (kids.length > shown.length) out.push(moreNode(scope, kids.length - shown.length));
        return out;
      }

      function rebuildMind() {
        const sel = selected.value;
        if (!sel || !db) {
          mindNodes.value = [];
          mindLinks.value = [];
          return;
        }

        const path = pathNodes.value.slice();
        const chain = path.length && path[path.length - 1].id === sel.id
          ? path.slice(0, -1)
          : path.filter((n) => n.id !== sel.id);

        // 中心节点 + 其子级
        const selNode = blankNode(sel);
        selNode.kind = 'center';
        selNode.color = PALETTE[0];

        const mexp = mindExpanded.value;
        const allKids = loadChildren(sel.id) || [];
        selNode.hasKids = allKids.length > 0;
        selNode.children = childNodesOf(sel.id, null, sel.id).map((kn, i) => {
          // childNodesOf 已经生成子节点，这里补上「再展开一层」的内容
          const src = allKids[i];
          if (src && mexp[src.id]) {
            kn.expanded = true;
            kn.children = childNodesOf(src.id, kn.color, src.id + ':g');
          }
          return kn;
        });

        // 祖先链
        const chainNodes = chain.map((t) => {
          const n = blankNode(t);
          n.kind = 'ancestor';
          n.color = CHAIN_COLOR;
          n.hasKids = true;
          return n;
        });
        for (let i = 0; i < chainNodes.length - 1; i++) {
          chainNodes[i].children = [chainNodes[i + 1]];
        }

        let root;
        if (chainNodes.length) {
          const parentNode = chainNodes[chainNodes.length - 1];
          if (sel.rank === 'species' && sel.parent_id != null) {
            // 种：把同级（同属）物种一起铺开，当前种高亮；同级过多时只取当前种附近的一段
            const sibs = loadChildren(sel.parent_id) || [];
            let sibList = sibs;
            let hiddenSib = 0;
            if (sibs.length > MIND_MAX_SIB) {
              let idx = 0;
              for (let i = 0; i < sibs.length; i++) {
                if (sibs[i].id === sel.id) { idx = i; break; }
              }
              const w = windowSlice(sibs, idx, MIND_MAX_SIB);
              sibList = w.items;
              hiddenSib = w.hidden;
            }
            const list = sibList.map((s, i) => {
              if (s.id === sel.id) return selNode;
              const sn = blankNode(s);
              sn.kind = 'leaf';
              sn.color = PALETTE[i % PALETTE.length];
              sn.hasKids = false;
              return sn;
            });
            if (!list.some((n) => n.id === sel.id)) list.push(selNode);
            parentNode.children = list;
            if (hiddenSib) parentNode.children.push(moreNode('sib:' + sel.parent_id, hiddenSib));
          } else {
            parentNode.children = [selNode];
          }
          root = chainNodes[0];
        } else {
          root = selNode;
        }

        // 布局：横向思维导图
        const nodes = [];
        const links = [];
        let cursor = 0;

        (function place(n, d) {
          n.depth = d;
          n.x = 28 + d * COL_W;
          const len = (n.name || '').length;
          n.w = Math.min(212, Math.max(94, len * 14 + 46));
          if (!n.children.length) {
            n.y = 26 + (cursor + 0.5) * ROW_H;
            cursor += 1;
          } else {
            for (let i = 0; i < n.children.length; i++) place(n.children[i], d + 1);
            n.y = (n.children[0].y + n.children[n.children.length - 1].y) / 2;
          }
          nodes.push(n);
        })(root, 0);

        let right = 0;
        for (let i = 0; i < nodes.length; i++) {
          right = Math.max(right, nodes[i].x + nodes[i].w);
          for (let j = 0; j < nodes[i].children.length; j++) {
            const c = nodes[i].children[j];
            links.push({ id: nodes[i].id + '>' + c.id, d: bezier(nodes[i], c), color: c.color || CHAIN_COLOR });
          }
        }

        mindNodes.value = nodes;
        mindLinks.value = links;
        mindW.value = right + 48;
        mindH.value = Math.max(180, cursor * ROW_H + 52);
        selPos.value = { x: selNode.x + selNode.w / 2, y: selNode.y };

        nextTick(() => {
          if (autoFitPending) {
            autoFitPending = false;
            autoFitWidth();
          } else {
            centerOnSelected();
          }
        });
      }

      function toggleMindExpand(n) {
        if (mindExpanded.value[n.id]) {
          delete mindExpanded.value[n.id];
        } else {
          loadChildren(n.id);
          mindExpanded.value[n.id] = true;
        }
        rebuildMind();
      }

      function pickMind(n) {
        if (n.kind === 'more') return;
        if (panMoved.value) {
          panMoved.value = false;
          return;
        }
        selectTaxon({
          id: n.id,
          rank: n.rank,
          scientific_name: n.sci,
          common_name: n.common,
        });
      }

      /* ---------------- 缩放 / 平移 ---------------- */

      function centerOnSelected() {
        const el = mindEl.value;
        if (!el) return;
        const z = zoom.value;
        el.scrollLeft = Math.max(0, selPos.value.x * z - el.clientWidth * 0.34);
        el.scrollTop = Math.max(0, selPos.value.y * z - el.clientHeight * 0.5);
      }

      function setZoom(z) {
        zoom.value = Math.min(1.5, Math.max(0.4, Math.round(z * 100) / 100));
        nextTick(centerOnSelected);
      }

      function zoomIn() { setZoom(zoom.value + 0.1); }
      function zoomOut() { setZoom(zoom.value - 0.1); }

      function autoFitWidth() {
        const el = mindEl.value;
        if (!el || !mindW.value) return;
        const zx = (el.clientWidth - 56) / mindW.value;
        setZoom(Math.max(0.5, Math.min(1, zx)));
      }

      function zoomFit() {
        const el = mindEl.value;
        if (!el || !mindW.value) return;
        const zx = (el.clientWidth - 48) / mindW.value;
        const zy = (el.clientHeight - 32) / mindH.value;
        setZoom(Math.min(1.1, Math.max(0.4, Math.min(zx, zy))));
      }

      function onWheelZoom(e) {
        setZoom(zoom.value + (e.deltaY < 0 ? 0.1 : -0.1));
      }

      function startPan(e) {
        if (e.button !== 0) return;
        const el = mindEl.value;
        if (!el) return;
        const sx = e.clientX;
        const sy = e.clientY;
        const sl = el.scrollLeft;
        const st = el.scrollTop;
        let moved = false;

        const move = (ev) => {
          const dx = ev.clientX - sx;
          const dy = ev.clientY - sy;
          if (Math.abs(dx) + Math.abs(dy) > 3) moved = true;
          el.scrollLeft = sl - dx;
          el.scrollTop = st - dy;
        };
        const up = () => {
          window.removeEventListener('mousemove', move);
          window.removeEventListener('mouseup', up);
          el.classList.remove('panning');
          panMoved.value = moved;
          if (moved) {
            // click 事件在 mouseup 之后同步派发，等它走完再清标记
            setTimeout(() => { panMoved.value = false; }, 0);
          }
        };
        el.classList.add('panning');
        window.addEventListener('mousemove', move);
        window.addEventListener('mouseup', up);
      }

      /* ---------------- 搜索 ---------------- */

      function searchDb(q) {
        const term = q.trim();
        if (!term || !db) return [];
        const like = '%' + term.replace(/[%_]/g, '') + '%';
        if (hasFts()) {
          try {
            const fts = term.replace(/"/g, '').split(/\s+/).filter(Boolean)
              .map((t) => '"' + t + '"*').join(' ');
            if (fts) {
              const rows = queryRows(
                'SELECT t.id, t.parent_id, t.rank, t.scientific_name, t.common_name, t.depth ' +
                'FROM taxa_fts f JOIN taxa t ON t.id = f.rowid WHERE f MATCH ? LIMIT 40',
                [fts]
              );
              if (rows.length) return rows;
            }
          } catch (_) { ftsReady = false; /* 索引损坏则回退 LIKE */ }
        }
        try {
          return queryRows(
            'SELECT ' + COLS + ' FROM taxa WHERE scientific_name LIKE ? OR IFNULL(common_name,\'\') LIKE ? ' +
            'ORDER BY ' + RANK_CASE + ', scientific_name LIMIT 40',
            [like, like]
          );
        } catch (_) {
          return [];
        }
      }

      function runSearch() {
        const q = query.value.trim();
        if (!q) return;
        const hits = searchDb(q);
        candidates.value = hits;
        candidateIndex.value = 0;
        if (!hits.length) {
          error.value = '未找到：' + q;
          statusText.value = '无匹配';
          return;
        }
        error.value = '';
        selectTaxon(hits[0]);
        statusText.value = '命中 ' + hits.length + ' 条';
      }

      function onSearchInput() {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(() => {
          if (query.value.trim()) runSearch();
        }, 320);
      }

      function nextCandidate() {
        if (candidates.value.length < 2) return;
        candidateIndex.value = (candidateIndex.value + 1) % candidates.value.length;
        selectTaxon(candidates.value[candidateIndex.value]);
      }

      function clearSearch() {
        query.value = '';
        error.value = '';
        candidates.value = [];
        statusText.value = '';
      }

      /* ---------------- 数据装载 ---------------- */

      async function openDb(bytes) {
        if (!SQL) {
          SQL = await initSqlJs({ locateFile: (f) => './vendor/' + f });
        }
        if (db) {
          try { db.close(); } catch (_) {}
        }
        db = new SQL.Database(bytes);
        childrenMap.value = {};
        expanded.value = {};
        mindExpanded.value = {};
        selected.value = null;
        pathNodes.value = [];
        mindNodes.value = [];
        mindLinks.value = [];
        listRows.value = [];
        listTotal.value = 0;
        childCounts.value = {};
        siblingRows.value = [];
        siblingTotal.value = 0;
        ftsReady = null;
        speciesCache = -1;
        nodeCache = -1;
        refreshMeta();

        const roots = loadChildren('root');
        if (!roots.length) {
          error.value = '名录入库为空';
          return;
        }
        const first = roots[0];
        expanded.value = { [first.id]: true };
        loadChildren(first.id);
        autoFitPending = true;
        selectTaxon(first);
        nextTick(syncTreeViewport);
      }

      async function ensureDb() {
        loadingDb.value = true;
        error.value = '';
        try {
          // 1) 优先 data/taxa.sqlite；没有就退回只读 seed
          let base = null;
          let fromData = false;
          try {
            base = await fetchBytes(DATA_URL);
            fromData = true;
            hasDataDb.value = true;
          } catch (_) {
            hasDataDb.value = false;
            try { base = await fetchBytes(SEED_URL); } catch (_) { base = null; }
          }

          // 2) 内存里校正示例名录 + 确保索引存在
          const prepared = await prepareDbBytes(base);
          if (!prepared || !prepared.bytes) throw new Error('没有可用的名录数据');
          const bytes = prepared.bytes;

          await openDb(bytes);

          // 顺手把新增索引/重写结果存回 data/，下次启动不必再建
          if (fromData && prepared.dirty) {
            try { await putBytes(DATA_URL, bytes, 'application/octet-stream'); } catch (_) { /* 只读亦可 */ }
          }

          const n = countSpecies();
          const total = countNodes();
          if (fromData) {
            statusText.value = '已加载 data/taxa.sqlite · ' + n + ' 种 / ' + total + ' 节点';
          } else {
            // 3) 首次运行：把“基库 + 示例”装到 data/，下次直接读
            try {
              await writeDataDb(bytes);
              hasDataDb.value = true;
              statusText.value = '已安装示例名录到 data/ · ' + n + ' 种 / ' + total + ' 节点';
            } catch (_) {
              statusText.value = '内置示例名录（只读）· ' + n + ' 种 / ' + total + ' 节点';
            }
          }
        } catch (e) {
          error.value = '无法加载名录：' + (e.message || e);
        } finally {
          loadingDb.value = false;
        }
      }

      /** 二次确认后调用：丢弃 data/ 里的库，从 seed（或空库）清空重写示例名录 */
      function resetSampleDb() {
        if (loadingDb.value) return;
        if (!resetArmed.value) {
          resetArmed.value = true;
          statusText.value = '再点一次即清空 data/ 库并重写示例名录';
          clearTimeout(resetTimer);
          resetTimer = setTimeout(() => {
            resetArmed.value = false;
            statusText.value = '';
          }, 5000);
          return;
        }
        clearTimeout(resetTimer);
        resetArmed.value = false;
        return doResetSampleDb();
      }

      async function doResetSampleDb() {
        loadingDb.value = true;
        error.value = '';
        statusText.value = '正在清空并重写示例库…';
        try {
          let base = null;
          try { base = await fetchBytes(SEED_URL); } catch (_) { base = null; }
          const prepared = await prepareDbBytes(base, { force: true });
          if (!prepared || !prepared.bytes) throw new Error('没有可用的名录数据');
          const bytes = prepared.bytes;
          await openDb(bytes);

          const n = countSpecies();
          const total = countNodes();
          try {
            await writeDataDb(bytes);
            hasDataDb.value = true;
            statusText.value = '已清空并重写 data/ 库 · ' + n + ' 种 / ' + total + ' 节点';
          } catch (_) {
            hasDataDb.value = false;
            statusText.value = '已重建内存库（data/ 不可写）· ' + n + ' 种 / ' + total + ' 节点';
          }
        } catch (e) {
          error.value = '重建失败：' + (e.message || e);
          statusText.value = '';
        } finally {
          loadingDb.value = false;
        }
      }

      onMounted(async () => {
        await ensureDb();
        syncTreeViewport();
        window.addEventListener('resize', () => {
          if (mindEl.value && viewMode.value === 'mind' && !autoFitPending) centerOnSelected();
          syncTreeViewport();
        });
      });

      return {
        title,
        error,
        loadingDb,
        hasDataDb,
        dbMeta,
        statusText,
        resetArmed,
        treeOpen,
        treeEl,
        mindEl,
        listEl,
        query,
        candidates,
        candidateIndex,
        selected,
        pathNodes,
        treeRows,
        treeWindow,
        onTreeScroll,
        viewMode,
        setView,
        listRows,
        listTotal,
        childCounts,
        siblingRows,
        siblingTotal,
        loadMoreList,
        pickRow,
        goUp,
        mindNodes,
        mindLinks,
        mindW,
        mindH,
        zoom,
        zoomPct,
        nodeH,
        rankLabel,
        toggleTree,
        collapseAll,
        pickTree,
        pickMind,
        toggleMindExpand,
        selectTaxon,
        centerOnSelected,
        zoomIn,
        zoomOut,
        zoomFit,
        onWheelZoom,
        startPan,
        onSearchInput,
        runSearch,
        nextCandidate,
        clearSearch,
        ensureDb,
        resetSampleDb,
      };
    },
  }).mount('#app');
})();
