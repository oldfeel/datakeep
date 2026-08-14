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
  var _watchLastDataRev = null;
  var _watchLastAppRev = null;
  var _watchSuppressUntil = 0;
  var _watchTimer = null;
  var _watchBusy = false;

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

  function fetchRevision() {
    return fetch('/__datakeep/revision', { cache: 'no-store' }).then(function (res) {
      if (!res.ok) throw new Error('revision HTTP ' + res.status);
      return res.json();
    });
  }

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

  function persist() {
    if (!db) return Promise.resolve();
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

  function getDb() {
    return db;
  }

  global.DataKeepDb = {
    open: openDatabase,
    persist: persist,
    schedulePersist: schedulePersist,
    fetchRevision: fetchRevision,
    ackDataRevision: ackDataRevision,
    watchData: watchData,
    getDb: getDb,
    onPersistError: null,
  };
})(window);
