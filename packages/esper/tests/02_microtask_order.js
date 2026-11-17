var log = [];

T.pending("microtask runs after sync code");
Promise.resolve().then(function () {
  log.push("micro");
});
log.push("sync");
Promise.resolve().then(function () {
  T.check("microtask runs after sync code", log.join(",") === "sync,micro");
});

// Two chains should interleave in spec order: a1, b1, a2, b2.
var seq = [];
T.pending("chains interleave in spec order");
Promise.resolve()
  .then(function () {
    seq.push("a1");
  })
  .then(function () {
    seq.push("a2");
  });
Promise.resolve()
  .then(function () {
    seq.push("b1");
  })
  .then(function () {
    seq.push("b2");
  })
  .then(function () {
    T.check("chains interleave in spec order", seq.join(",") === "a1,b1,a2,b2");
  });
