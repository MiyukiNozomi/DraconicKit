T.pending("environment: Promise exists");
T.check("environment: Promise exists", typeof Promise === "function");

T.pending("environment: generators exist");
T.check(
  "environment: generators exist",
  typeof function* () {}.constructor === "function",
);

T.pending("environment: async function parses");

try {
  eval("(async function () {})");
  T.check("environment: async function parses", true);
} catch (e) {
  T.check("environment: async function parses", false);
}
