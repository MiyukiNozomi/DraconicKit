async function resolved() {
  var v = await Promise.resolve(10);
  return v + 1;
}

async function nonPromise() {
  return await 5;
}

async function caught() {
  try {
    await Promise.reject(new Error("nope"));
    return "not reached";
  } catch (e) {
    return "caught " + e.message;
  }
}

async function all() {
  var vals = await Promise.all([1, Promise.resolve(2), Promise.resolve(3)]);
  return vals.join(",");
}

async function settled() {
  var res = await Promise.allSettled([
    Promise.resolve("a"),
    Promise.reject(new Error("x")),
  ]);
  return res
    .map(function (r) {
      return r.status;
    })
    .join(",");
}

T.pending("await resolved promise");
resolved().then(function (v) {
  T.check("await resolved promise", v === 11);
});

T.pending("await non-promise value");
nonPromise().then(function (v) {
  T.check("await non-promise value", v === 5);
});

T.pending("await rejected promise is catchable");
caught().then(function (v) {
  T.check("await rejected promise is catchable", v === "caught nope");
});

T.pending("Promise.all");
all().then(function (v) {
  T.check("Promise.all", v === "1,2,3");
});

T.pending("Promise.allSettled");
settled().then(function (v) {
  T.check("Promise.allSettled", v === "fulfilled,rejected");
});
