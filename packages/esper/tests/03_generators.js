T.pending("generator send/receive");
function* g() {
  var x = yield 1;
  yield x + 1;
  return "end";
}
var it = g();
var a = it.next();
var b = it.next(41);
var c = it.next();
T.check(
  "generator send/receive",
  a.value === 1 && b.value === 42 && c.value === "end" && c.done === true,
);

T.pending("generator throw into");
function* h() {
  try {
    yield 1;
  } catch (e) {
    yield "caught:" + e;
  }
}
var it2 = h();
it2.next();
var r = it2.throw("boom");
T.check("generator throw into", r.value === "caught:boom");
