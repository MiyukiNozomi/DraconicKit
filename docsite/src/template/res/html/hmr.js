(function () {
  var current = null;
  function poll() {
    fetch("/api/reload", { cache: "no-store" })
      .then(function (r) {
        return r.json();
      })
      .then(function (data) {
        if (current === null) {
          current = data.version;
        } else if (data.version !== current) {
          location.reload();
          return;
        }
        setTimeout(poll, 500);
      })
      .catch(function () {
        setTimeout(poll, 1000);
      });
  }
  poll();
})();
