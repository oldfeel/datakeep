(function () {
  'use strict';

  var VIDEO_EXT = {
    mp4: 1, webm: 1, mkv: 1, mov: 1, m4v: 1, avi: 1, ogv: 1, mpeg: 1, mpg: 1,
  };

  var statusEl = document.getElementById('status');
  var navEl = document.getElementById('nav');
  var gridEl = document.getElementById('grid');
  var emptyEl = document.getElementById('empty');
  var toolbarEl = document.getElementById('toolbar');
  var sectionTitleEl = document.getElementById('sectionTitle');
  var btnBack = document.getElementById('btnBack');
  var playerEl = document.getElementById('player');
  var videoEl = document.getElementById('videoEl');
  var playerTitleEl = document.getElementById('playerTitle');
  var playerHintEl = document.getElementById('playerHint');
  var btnClosePlayer = document.getElementById('btnClosePlayer');

  /** @type {{ collections: Object.<string, string[]>, rootFiles: string[] }} */
  var library = { collections: {}, rootFiles: [] };
  /** 'all' | 'root' | collection name */
  var currentCat = 'all';
  /** null | collection name when browsing into a folder from "全部" */
  var drillCollection = null;

  function setStatus(msg, isError) {
    statusEl.textContent = msg || '';
    statusEl.className = 'status' + (isError ? ' error' : '');
  }

  function dataUrl(rel) {
    var parts = String(rel || '')
      .split('/')
      .filter(Boolean)
      .map(encodeURIComponent);
    return '/__datakeep/data/' + parts.join('/');
  }

  function listDir(prefix) {
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

  function isVideoPath(rel) {
    var name = rel.split('/').pop() || '';
    var i = name.lastIndexOf('.');
    if (i < 0) return false;
    return !!VIDEO_EXT[name.slice(i + 1).toLowerCase()];
  }

  function baseName(rel) {
    var n = rel.split('/').pop() || rel;
    var i = n.lastIndexOf('.');
    return i > 0 ? n.slice(0, i) : n;
  }

  function collectionOf(rel) {
    var parts = rel.split('/').filter(Boolean);
    if (parts.length >= 2) return parts[0];
    return null;
  }

  function scanLibrary() {
    return listDir('').then(function (files) {
      var collections = {};
      var rootFiles = [];
      var dirs = {};

      files.forEach(function (rel) {
        if (!rel || rel.indexOf('..') >= 0) return;
        // 忽略库元数据等
        if (/\.db$/i.test(rel) || /\.json$/i.test(rel)) return;
        var parts = rel.split('/').filter(Boolean);
        if (parts.length === 1) {
          if (isVideoPath(rel)) rootFiles.push(rel);
          return;
        }
        var col = parts[0];
        dirs[col] = true;
        if (isVideoPath(rel) && parts.length >= 2) {
          if (!collections[col]) collections[col] = [];
          collections[col].push(rel);
        }
      });

      // 空合集（仅有子目录名出现在路径里）也展示：若 files 只含更深路径
      Object.keys(dirs).forEach(function (col) {
        if (!collections[col]) collections[col] = [];
      });

      Object.keys(collections).forEach(function (k) {
        collections[k].sort(function (a, b) {
          return a.localeCompare(b, 'zh');
        });
      });
      rootFiles.sort(function (a, b) {
        return a.localeCompare(b, 'zh');
      });

      library = { collections: collections, rootFiles: rootFiles };
    });
  }

  function collectionNames() {
    return Object.keys(library.collections).sort(function (a, b) {
      return a.localeCompare(b, 'zh');
    });
  }

  function countIn(cat) {
    if (cat === 'all') {
      var n = library.rootFiles.length;
      collectionNames().forEach(function (c) {
        n += library.collections[c].length;
      });
      return n;
    }
    if (cat === 'root') return library.rootFiles.length;
    return (library.collections[cat] || []).length;
  }

  function renderNav() {
    navEl.innerHTML = '';
    function addBtn(id, label) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.dataset.cat = id;
      var count = countIn(id);
      btn.innerHTML =
        escapeHtml(label) +
        '<span class="count">' +
        count +
        '</span>';
      if (currentCat === id && !drillCollection) btn.className = 'active';
      if (drillCollection && id === drillCollection) btn.className = 'active';
      btn.addEventListener('click', function () {
        currentCat = id;
        drillCollection = null;
        closePlayer();
        render();
      });
      navEl.appendChild(btn);
    }

    addBtn('all', '全部');
    if (library.rootFiles.length) addBtn('root', '未分类');
    collectionNames().forEach(function (name) {
      addBtn(name, name);
    });
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function showEmpty(html) {
    emptyEl.hidden = false;
    emptyEl.innerHTML = html;
    gridEl.innerHTML = '';
  }

  function hideEmpty() {
    emptyEl.hidden = true;
    emptyEl.textContent = '';
  }

  function renderGridAsCollections() {
    toolbarEl.hidden = true;
    hideEmpty();
    gridEl.innerHTML = '';
    var names = collectionNames();
    if (!names.length && !library.rootFiles.length) {
      showEmpty(
        '还没有视频。<br/>请把文件放进本应用的 <code>data/</code> 目录，' +
          '或新建子文件夹作为合集（例如 <code>data/开源电影/</code>）。'
      );
      return;
    }

    names.forEach(function (name) {
      var files = library.collections[name] || [];
      var card = document.createElement('button');
      card.type = 'button';
      card.className = 'card';
      card.innerHTML =
        '<div class="thumb">📁</div>' +
        '<div class="meta"><div class="title">' +
        escapeHtml(name) +
        '</div><div class="sub">' +
        files.length +
        ' 个视频</div></div>';
      card.addEventListener('click', function () {
        drillCollection = name;
        currentCat = name;
        render();
      });
      gridEl.appendChild(card);
    });

    if (library.rootFiles.length) {
      var card = document.createElement('button');
      card.type = 'button';
      card.className = 'card';
      card.innerHTML =
        '<div class="thumb">📄</div>' +
        '<div class="meta"><div class="title">未分类</div><div class="sub">' +
        library.rootFiles.length +
        ' 个视频</div></div>';
      card.addEventListener('click', function () {
        drillCollection = null;
        currentCat = 'root';
        render();
      });
      gridEl.appendChild(card);
    }
  }

  function videosForView() {
    if (drillCollection) return library.collections[drillCollection] || [];
    if (currentCat === 'all') {
      // 「全部」先展示合集卡片；若点进合集才列表
      return null;
    }
    if (currentCat === 'root') return library.rootFiles;
    return library.collections[currentCat] || [];
  }

  function renderVideoCards(files) {
    hideEmpty();
    gridEl.innerHTML = '';
    if (!files.length) {
      showEmpty('此合集下暂无视频文件。');
      return;
    }
    files.forEach(function (rel) {
      var card = document.createElement('button');
      card.type = 'button';
      card.className = 'card';
      var thumb =
        '<div class="thumb"><video muted preload="metadata" src="' +
        escapeHtml(dataUrl(rel)) +
        '#t=0.5"></video></div>';
      card.innerHTML =
        thumb +
        '<div class="meta"><div class="title">' +
        escapeHtml(baseName(rel)) +
        '</div><div class="sub">' +
        escapeHtml(rel.split('.').pop().toUpperCase()) +
        '</div></div>';
      card.addEventListener('click', function () {
        openPlayer(rel);
      });
      gridEl.appendChild(card);
    });
  }

  function render() {
    renderNav();

    if (currentCat === 'all' && !drillCollection) {
      renderGridAsCollections();
      // 若没有合集只有根文件，直接列视频
      if (!collectionNames().length && library.rootFiles.length) {
        toolbarEl.hidden = false;
        sectionTitleEl.textContent = '未分类';
        btnBack.hidden = true;
        renderVideoCards(library.rootFiles);
      }
      return;
    }

    toolbarEl.hidden = false;
    btnBack.hidden = false;
    var title =
      drillCollection ||
      (currentCat === 'root' ? '未分类' : currentCat === 'all' ? '全部' : currentCat);
    sectionTitleEl.textContent = title;

    var files = videosForView();
    if (files == null) {
      renderGridAsCollections();
      return;
    }
    renderVideoCards(files);
  }

  btnBack.addEventListener('click', function () {
    drillCollection = null;
    currentCat = 'all';
    closePlayer();
    render();
  });

  function openPlayer(rel) {
    playerEl.hidden = false;
    playerTitleEl.textContent = baseName(rel);
    playerHintEl.hidden = true;
    playerHintEl.textContent = '';
    videoEl.src = dataUrl(rel);
    videoEl.load();
    var playPromise = videoEl.play();
    if (playPromise && typeof playPromise.catch === 'function') {
      playPromise.catch(function () {
        /* 自动播放可能被拦，用户可点控件 */
      });
    }
  }

  function closePlayer() {
    videoEl.pause();
    videoEl.removeAttribute('src');
    videoEl.load();
    playerEl.hidden = true;
    playerHintEl.hidden = true;
  }

  btnClosePlayer.addEventListener('click', closePlayer);

  videoEl.addEventListener('error', function () {
    playerHintEl.hidden = false;
    playerHintEl.textContent =
      '无法在应用内播放此格式。可尝试 mp4/webm，或到 DataKeep 文件浏览中用系统播放器打开。';
  });

  function refresh() {
    setStatus('扫描中…');
    return scanLibrary()
      .then(function () {
        var n = countIn('all');
        setStatus(n ? '共 ' + n + ' 个视频' : '暂无视频');
        // 当前分类若已不存在，回到全部
        if (
          currentCat !== 'all' &&
          currentCat !== 'root' &&
          !library.collections[currentCat]
        ) {
          currentCat = 'all';
          drillCollection = null;
        }
        render();
      })
      .catch(function (e) {
        console.error(e);
        setStatus(String(e.message || e), true);
      });
  }

  // revision 监听（无 sql.js）
  var lastDataRev = null;
  var lastAppRev = null;
  var watchBusy = false;

  function fetchRevision() {
    return fetch('/__datakeep/revision', { cache: 'no-store' }).then(function (res) {
      if (!res.ok) throw new Error('revision HTTP ' + res.status);
      return res.json();
    });
  }

  function onRev(j) {
    if (!j) return;
    if (lastAppRev == null) lastAppRev = j.appRev;
    else if (j.appRev !== lastAppRev) {
      lastAppRev = j.appRev;
      location.reload();
      return;
    }
    if (lastDataRev == null) {
      lastDataRev = j.dataRev;
      return;
    }
    if (j.dataRev === lastDataRev) return;
    lastDataRev = j.dataRev;
    refresh();
  }

  function tickRev() {
    if (watchBusy) return;
    watchBusy = true;
    fetchRevision()
      .then(onRev)
      .catch(function () {})
      .then(function () {
        watchBusy = false;
      });
  }

  window.addEventListener('datakeep:data-changed', tickRev);
  setInterval(tickRev, 2000);

  refresh().then(tickRev);
})();
