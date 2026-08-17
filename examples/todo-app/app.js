(function () {
  'use strict';

  var statusEl = document.getElementById('status');
  var form = document.getElementById('form');
  var listEl = document.getElementById('list');
  var filter = 'all';
  var DB_NAME = 'todo.db';

  function setStatus(msg, isError) {
    statusEl.textContent = msg || '';
    statusEl.className = 'status' + (isError ? ' error' : '');
  }

  function uuid() {
    if (globalThis.crypto && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      var r = (Math.random() * 16) | 0;
      var v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  function nowIso() {
    return new Date().toISOString();
  }

  function migrate(db) {
    db.run(
      'CREATE TABLE IF NOT EXISTS tasks (' +
        'id TEXT PRIMARY KEY,' +
        'title TEXT NOT NULL,' +
        'done INTEGER NOT NULL DEFAULT 0,' +
        'created_at TEXT NOT NULL,' +
        'updated_at TEXT NOT NULL,' +
        'deleted INTEGER NOT NULL DEFAULT 0' +
      ')'
    );
    // 旧版 INTEGER 自增表 → 迁到 UUID
    try {
      var info = db.exec('PRAGMA table_info(tasks)');
      if (info && info[0] && info[0].values) {
        var idCol = null;
        info[0].values.forEach(function (row) {
          if (row[1] === 'id') idCol = row;
        });
        // type 在 PRAGMA 第3列(index 2)
        if (idCol && String(idCol[2]).toUpperCase().indexOf('INT') >= 0) {
          upgradeLegacySchema(db);
        }
      }
    } catch (_) {}
  }

  function upgradeLegacySchema(db) {
    var rows = [];
    try {
      var stmt = db.prepare('SELECT id, title, done, created_at FROM tasks');
      while (stmt.step()) rows.push(stmt.getAsObject());
      stmt.free();
    } catch (_) {
      return;
    }
    db.run('DROP TABLE IF EXISTS tasks');
    db.run(
      'CREATE TABLE tasks (' +
        'id TEXT PRIMARY KEY,' +
        'title TEXT NOT NULL,' +
        'done INTEGER NOT NULL DEFAULT 0,' +
        'created_at TEXT NOT NULL,' +
        'updated_at TEXT NOT NULL,' +
        'deleted INTEGER NOT NULL DEFAULT 0' +
      ')'
    );
    rows.forEach(function (r) {
      var created = r.created_at || nowIso();
      db.run(
        'INSERT INTO tasks (id, title, done, created_at, updated_at, deleted) VALUES (?,?,?,?,?,0)',
        [uuid(), r.title || '', r.done ? 1 : 0, created, created]
      );
    });
  }

  function pickNewer(a, b) {
    if (!a) return b;
    if (!b) return a;
    if (a.updated_at > b.updated_at) return a;
    if (b.updated_at > a.updated_at) return b;
    if (a.deleted !== b.deleted) return a.deleted ? a : b;
    return a;
  }

  function readTasksFromDb(sqlite) {
    var map = {};
    try {
      var stmt = sqlite.prepare(
        'SELECT id, title, done, created_at, updated_at, deleted FROM tasks'
      );
      while (stmt.step()) {
        var r = stmt.getAsObject();
        if (!r.id) continue;
        // 兼容缺列的旧冲突库
        r.updated_at = r.updated_at || r.created_at || nowIso();
        r.deleted = r.deleted ? 1 : 0;
        r.done = r.done ? 1 : 0;
        map[r.id] = pickNewer(map[r.id], r);
      }
      stmt.free();
    } catch (e) {
      // 可能是旧 schema，试只读基础列
      try {
        var stmt2 = sqlite.prepare('SELECT id, title, done, created_at FROM tasks');
        while (stmt2.step()) {
          var r2 = stmt2.getAsObject();
          var created = r2.created_at || nowIso();
          var row = {
            id: String(r2.id),
            title: r2.title || '',
            done: r2.done ? 1 : 0,
            created_at: created,
            updated_at: created,
            deleted: 0,
          };
          // 旧自增 id：换成 UUID，避免与另一端数字 id 撞车语义混乱
          if (/^\d+$/.test(row.id)) {
            row.id = uuid();
          }
          map[row.id] = pickNewer(map[row.id], row);
        }
        stmt2.free();
      } catch (e2) {
        console.warn('读取库失败', e2);
      }
    }
    return map;
  }

  function isConflictDbName(name) {
    // todo.sync-conflict-YYYYMMDD-HHMMSS-XXXXX.db
    return (
      name.indexOf(DB_NAME.replace(/\.db$/, '')) === 0 &&
      name.indexOf('.sync-conflict-') >= 0 &&
      /\.db$/i.test(name)
    );
  }

  /**
   * 合并主库 + Syncthing 冲突副本（*.sync-conflict-*.db），
   * 按 id 取较新 updated_at，写回主库并删除冲突文件。
   */
  function mergeConflictDatabases() {
    return DataKeepDb.listFiles('').then(function (files) {
      var conflicts = files.filter(function (f) {
        return f.indexOf('/') < 0 && isConflictDbName(f);
      });
      if (!conflicts.length) return { merged: 0, conflicts: 0 };

      var merged = readTasksFromDb(DataKeepDb.getDb());
      var chain = Promise.resolve();

      conflicts.forEach(function (rel) {
        chain = chain.then(function () {
          return DataKeepDb.readBytes(rel).then(function (buf) {
            if (!buf) return;
            return DataKeepDb.openFromBytes(buf, migrate).then(function (temp) {
              var other = readTasksFromDb(temp);
              Object.keys(other).forEach(function (id) {
                merged[id] = pickNewer(merged[id], other[id]);
              });
              temp.close();
            });
          });
        });
      });

      return chain.then(function () {
        var db = DataKeepDb.getDb();
        db.run('DELETE FROM tasks');
        Object.keys(merged).forEach(function (id) {
          var r = merged[id];
          db.run(
            'INSERT INTO tasks (id, title, done, created_at, updated_at, deleted) VALUES (?,?,?,?,?,?)',
            [
              r.id,
              r.title,
              r.done ? 1 : 0,
              r.created_at,
              r.updated_at,
              r.deleted ? 1 : 0,
            ]
          );
        });
        return DataKeepDb.persist().then(function () {
          return Promise.all(
            conflicts.map(function (rel) {
              return DataKeepDb.removeFile(rel).catch(function () {});
            })
          ).then(function () {
            return { merged: Object.keys(merged).length, conflicts: conflicts.length };
          });
        });
      });
    });
  }

  function refresh() {
    var db = DataKeepDb.getDb();
    var sql =
      'SELECT id, title, done, created_at, updated_at FROM tasks WHERE deleted = 0';
    if (filter === 'open') sql += ' AND done = 0';
    else if (filter === 'done') sql += ' AND done = 1';
    sql += ' ORDER BY done ASC, updated_at DESC';

    var rows = [];
    var stmt = db.prepare(sql);
    while (stmt.step()) {
      rows.push(stmt.getAsObject());
    }
    stmt.free();

    listEl.innerHTML = '';
    if (!rows.length) {
      var empty = document.createElement('li');
      empty.className = 'empty';
      empty.textContent = '暂无任务';
      listEl.appendChild(empty);
      return;
    }
    rows.forEach(function (r) {
      var li = document.createElement('li');
      var label = document.createElement('label');
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = !!r.done;
      cb.addEventListener('change', function () {
        db.run('UPDATE tasks SET done = ?, updated_at = ? WHERE id = ?', [
          cb.checked ? 1 : 0,
          nowIso(),
          r.id,
        ]);
        DataKeepDb.schedulePersist();
        refresh();
        if (window.__DATAKEEP_READONLY) {
          setStatus('对端只读，修改不会保存到手机', true);
        } else {
          setStatus('已保存');
        }
      });
      var title = document.createElement('span');
      title.className = 'title' + (r.done ? ' done' : '');
      title.textContent = r.title;
      label.appendChild(cb);
      label.appendChild(title);

      var del = document.createElement('button');
      del.type = 'button';
      del.className = 'del';
      del.textContent = '删除';
      del.addEventListener('click', function () {
        db.run('UPDATE tasks SET deleted = 1, updated_at = ? WHERE id = ?', [
          nowIso(),
          r.id,
        ]);
        DataKeepDb.schedulePersist();
        refresh();
        if (window.__DATAKEEP_READONLY) {
          setStatus('对端只读，修改不会保存到手机', true);
        } else {
          setStatus('已删除');
        }
      });

      li.appendChild(label);
      li.appendChild(del);
      listEl.appendChild(li);
    });
  }

  document.getElementById('filters').addEventListener('click', function (ev) {
    var btn = ev.target.closest('button[data-filter]');
    if (!btn) return;
    filter = btn.getAttribute('data-filter');
    Array.prototype.forEach.call(
      document.querySelectorAll('#filters button'),
      function (b) {
        b.classList.toggle('active', b === btn);
      }
    );
    refresh();
  });

  function reloadFromDisk(reason) {
    return DataKeepDb.open(DB_NAME, migrate)
      .then(function () {
        return mergeConflictDatabases();
      })
      .then(function (info) {
        refresh();
        if (info && info.conflicts) {
          setStatus('已合并 ' + info.conflicts + ' 个冲突库');
        } else {
          setStatus(reason || '已自动更新数据');
        }
      });
  }

  DataKeepDb.onPersistError = function (e) {
    setStatus('保存失败：' + (e && e.message ? e.message : e), true);
  };

  DataKeepDb.open(DB_NAME, migrate)
    .then(function () {
      return mergeConflictDatabases();
    })
    .then(function (info) {
      if (info && info.conflicts) {
        setStatus('已合并 ' + info.conflicts + ' 个冲突库，共 ' + info.merged + ' 条');
      } else {
        setStatus('已就绪');
      }
      refresh();
      DataKeepDb.watchData(function () {
        reloadFromDisk('已同步更新').catch(function (e) {
          console.warn(e);
        });
      });
    })
    .catch(function (e) {
      setStatus(
        '初始化失败：' + (e && e.message ? e.message : e) + '（需在 DataKeep 应用内打开）',
        true
      );
    });

  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    var db = DataKeepDb.getDb();
    if (!db) return;
    var title = (form.title.value || '').trim();
    if (!title) return;
    var t = nowIso();
    db.run(
      'INSERT INTO tasks (id, title, done, created_at, updated_at, deleted) VALUES (?,?,0,?,?,0)',
      [uuid(), title, t, t]
    );
    DataKeepDb.schedulePersist();
    form.title.value = '';
    refresh();
    if (window.__DATAKEEP_READONLY) {
      setStatus('对端只读，修改不会保存到手机', true);
    } else {
      setStatus('已保存');
    }
  });

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState !== 'visible') return;
    reloadFromDisk('已刷新').catch(function (e) {
      console.warn(e);
    });
  });
})();
