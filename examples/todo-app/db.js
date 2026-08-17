/**
 * DataKeep 应用 SQLite 封装（sql.js + /__datakeep/data/ 落盘）
 * 需先加载 vendor/sql-wasm.js
 */
(function (global) {
  'use strict';

  var SQL = null;
  var db = null;
  var fileName = 'app.db';
  var saveTimer = null;

  function dataUrl(name) {
    var parts = String(name || '')
      .split('/')
      .filter(Boolean)
      .map(encodeURIComponent);
    return '/__datakeep/data/' + parts.join('/');
  }

  function loadSqlJs() {
    if (typeof initSqlJs !== 'function') {
      return Promise.reject(
        new Error(
          '未加载 sql-wasm.js（文件缺失，或系统 WebView/Chrome 过旧无法解析脚本；请升级 Android System WebView）',
        ),
      );
    }
    return initSqlJs({
      locateFile: function (file) {
        return 'vendor/' + file;
      },
    }).then(function (sql) {
      SQL = sql;
      return sql;
    });
  }

  function openDatabase(name, migrateFn) {
    fileName = name || 'app.db';
    return loadSqlJs().then(function () {
      return fetch(dataUrl(fileName), { cache: 'no-store' }).then(function (res) {
        if (res.ok) {
          return res.arrayBuffer().then(function (buf) {
            db = new SQL.Database(new Uint8Array(buf));
          });
        }
        if (res.status === 404) {
          db = new SQL.Database();
          return;
        }
        throw new Error('读取数据库失败: HTTP ' + res.status);
      });
    }).then(function () {
      if (typeof migrateFn === 'function') {
        migrateFn(db);
      }
      return db;
    });
  }

  /** 从字节打开临时库（不替换当前 db） */
  function openFromBytes(buf, migrateFn) {
    return loadSqlJs().then(function () {
      var temp = new SQL.Database(new Uint8Array(buf));
      if (typeof migrateFn === 'function') {
        try {
          migrateFn(temp);
        } catch (_) {}
      }
      return temp;
    });
  }

  function persist() {
    if (!db) return Promise.resolve();
    if (global.__DATAKEEP_READONLY) {
      return Promise.reject(new Error('对端只读，无法保存'));
    }
    var data = db.export();
    return fetch(dataUrl(fileName), {
      method: 'PUT',
      headers: { 'Content-Type': 'application/octet-stream' },
      body: data,
    }).then(function (res) {
      if (!res.ok) throw new Error('保存失败: HTTP ' + res.status);
      return ackDataRevision();
    });
  }

  function schedulePersist(ms) {
    if (global.__DATAKEEP_READONLY) {
      if (global.DataKeepDb && typeof global.DataKeepDb.onPersistError === 'function') {
        global.DataKeepDb.onPersistError(new Error('对端只读，无法保存'));
      }
      return;
    }
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(function () {
      saveTimer = null;
      persist().catch(function (e) {
        console.error(e);
        if (global.DataKeepDb && typeof global.DataKeepDb.onPersistError === 'function') {
          global.DataKeepDb.onPersistError(e);
        }
      });
    }, ms == null ? 200 : ms);
  }

  function fetchRevision() {
    return fetch('/__datakeep/revision', { cache: 'no-store' }).then(function (res) {
      if (!res.ok) throw new Error('revision HTTP ' + res.status);
      return res.json();
    });
  }

  var _watchLastDataRev = null;
  var _watchLastAppRev = null;
  var _watchSuppressUntil = 0;
  var _watchTimer = null;
  var _watchBusy = false;

  /** 本机刚写入后调用，避免立刻被自动刷新覆盖未落盘编辑 */
  function ackDataRevision() {
    _watchSuppressUntil = Date.now() + 2500;
    return fetchRevision()
      .then(function (j) {
        _watchLastDataRev = j.dataRev;
        if (j.appRev != null) _watchLastAppRev = j.appRev;
        return j;
      })
      .catch(function () {
        return null;
      });
  }

  /**
   * 监听变更（轮询 revision + 宿主 datakeep:data-changed）。
   * onChange 在 dataRev 外部变化时调用；appRev 变化时 location.reload()。
   */
  function watchData(onChange, intervalMs) {
    function handleRev(j) {
      if (!j) return;
      if (_watchLastAppRev == null) {
        _watchLastAppRev = j.appRev;
      } else if (j.appRev !== _watchLastAppRev) {
        _watchLastAppRev = j.appRev;
        location.reload();
        return;
      }
      var rev = j.dataRev;
      if (_watchLastDataRev == null) {
        _watchLastDataRev = rev;
        return;
      }
      if (rev === _watchLastDataRev) return;
      if (Date.now() < _watchSuppressUntil) {
        _watchLastDataRev = rev;
        return;
      }
      _watchLastDataRev = rev;
      if (typeof onChange === 'function') onChange(j);
    }

    function tick() {
      if (_watchBusy) return;
      _watchBusy = true;
      fetchRevision()
        .then(handleRev)
        .catch(function () {})
        .then(function () {
          _watchBusy = false;
        });
    }

    function onHostEvent() {
      tick();
    }

    tick();
    _watchTimer = setInterval(tick, intervalMs == null ? 2000 : intervalMs);
    window.addEventListener('datakeep:data-changed', onHostEvent);

    return function stop() {
      if (_watchTimer) clearInterval(_watchTimer);
      _watchTimer = null;
      window.removeEventListener('datakeep:data-changed', onHostEvent);
    };
  }

  function listFiles(prefix) {
    var base = String(prefix || '').replace(/^\/+|\/+$/g, '');
    var url = base ? dataUrl(base) + '/' : '/__datakeep/data/';
    return fetch(url, { cache: 'no-store' }).then(function (res) {
      if (res.status === 404) return [];
      if (!res.ok) throw new Error('列目录失败: HTTP ' + res.status);
      return res.json().then(function (j) {
        return (j && j.files) || [];
      });
    });
  }

  function readBytes(relPath) {
    return fetch(dataUrl(relPath), { cache: 'no-store' }).then(function (res) {
      if (res.status === 404) return null;
      if (!res.ok) throw new Error('读取失败: HTTP ' + res.status);
      return res.arrayBuffer();
    });
  }

  function removeFile(relPath) {
    return fetch(dataUrl(relPath), { method: 'DELETE' }).then(function (res) {
      if (res.status === 404) return;
      if (!res.ok) throw new Error('删除失败: HTTP ' + res.status);
    });
  }

  function getDb() {
    return db;
  }

  function getSql() {
    return SQL;
  }

  global.DataKeepDb = {
    open: openDatabase,
    openFromBytes: openFromBytes,
    persist: persist,
    schedulePersist: schedulePersist,
    listFiles: listFiles,
    readBytes: readBytes,
    removeFile: removeFile,
    fetchRevision: fetchRevision,
    ackDataRevision: ackDataRevision,
    watchData: watchData,
    getDb: getDb,
    getSql: getSql,
    onPersistError: null,
  };
})(window);
