(function () {
  'use strict';

  var statusEl = document.getElementById('status');
  var form = document.getElementById('form');
  var listEl = document.getElementById('list');

  function setStatus(msg, isError) {
    statusEl.textContent = msg || '';
    statusEl.className = 'status' + (isError ? ' error' : '');
  }

  function money(n) {
    return '¥' + Number(n).toFixed(2);
  }

  function today() {
    var d = new Date();
    var m = String(d.getMonth() + 1).padStart(2, '0');
    var day = String(d.getDate()).padStart(2, '0');
    return d.getFullYear() + '-' + m + '-' + day;
  }

  function migrate(db) {
    db.run(
      'CREATE TABLE IF NOT EXISTS entries (' +
        'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
        'amount REAL NOT NULL,' +
        'kind TEXT NOT NULL,' +
        'note TEXT,' +
        'day TEXT NOT NULL,' +
        'created_at TEXT NOT NULL' +
      ')'
    );
  }

  function refresh() {
    var db = DataKeepDb.getDb();
    var income = 0;
    var expense = 0;
    var rows = [];
    var stmt = db.prepare(
      'SELECT id, amount, kind, note, day FROM entries ORDER BY day DESC, id DESC'
    );
    while (stmt.step()) {
      var r = stmt.getAsObject();
      rows.push(r);
      if (r.kind === 'income') income += r.amount;
      else expense += r.amount;
    }
    stmt.free();

    document.getElementById('sum-in').textContent = money(income);
    document.getElementById('sum-out').textContent = money(expense);
    document.getElementById('sum-bal').textContent = money(income - expense);

    listEl.innerHTML = '';
    if (!rows.length) {
      listEl.innerHTML = '<li class="empty">暂无记录</li>';
      return;
    }
    rows.forEach(function (r) {
      var li = document.createElement('li');
      var left = document.createElement('div');
      var title = document.createElement('div');
      title.textContent = (r.note || (r.kind === 'income' ? '收入' : '支出'));
      var meta = document.createElement('div');
      meta.className = 'meta';
      meta.textContent = r.day + ' · ' + (r.kind === 'income' ? '收入' : '支出');
      left.appendChild(title);
      left.appendChild(meta);

      var right = document.createElement('div');
      right.style.textAlign = 'right';
      var amt = document.createElement('div');
      amt.className = 'amt ' + r.kind;
      amt.textContent = (r.kind === 'income' ? '+' : '-') + money(r.amount).slice(1);
      var del = document.createElement('button');
      del.type = 'button';
      del.className = 'del';
      del.textContent = '删除';
      del.addEventListener('click', function () {
        db.run('DELETE FROM entries WHERE id = ?', [r.id]);
        DataKeepDb.schedulePersist();
        refresh();
      });
      right.appendChild(amt);
      right.appendChild(del);

      li.appendChild(left);
      li.appendChild(right);
      listEl.appendChild(li);
    });
  }

  form.day.value = today();

  DataKeepDb.onPersistError = function (e) {
    setStatus('保存失败：' + (e && e.message ? e.message : e), true);
  };

  DataKeepDb.open('ledger.db', migrate)
    .then(function () {
      setStatus('已就绪');
      refresh();
      DataKeepDb.watchData(function () {
        DataKeepDb.open('ledger.db', migrate)
          .then(function () {
            refresh();
            setStatus('已自动更新数据');
          })
          .catch(function (e) {
            console.warn(e);
          });
      });
    })
    .catch(function (e) {
      setStatus('初始化失败：' + (e && e.message ? e.message : e) + '（需在 DataKeep 应用内打开）', true);
    });

  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    var db = DataKeepDb.getDb();
    if (!db) return;
    var kind = form.kind.value;
    var amount = parseFloat(form.amount.value);
    var day = form.day.value;
    var note = (form.note.value || '').trim();
    if (!(amount > 0) || !day) return;
    db.run(
      'INSERT INTO entries (amount, kind, note, day, created_at) VALUES (?, ?, ?, ?, ?)',
      [amount, kind, note, day, new Date().toISOString()]
    );
    DataKeepDb.schedulePersist();
    form.amount.value = '';
    form.note.value = '';
    form.day.value = today();
    refresh();
    setStatus('已保存');
  });
})();
