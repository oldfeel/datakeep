(function () {
  var el = document.getElementById('time');
  function tick() {
    el.textContent = '本地时间：' + new Date().toLocaleString('zh-CN');
  }
  tick();
  setInterval(tick, 1000);
})();
