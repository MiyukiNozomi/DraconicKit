T.pending("promise then runs after drain");
Promise.resolve(1).then(function (v) {
  T.check("promise then runs after drain", v === 1);
});
