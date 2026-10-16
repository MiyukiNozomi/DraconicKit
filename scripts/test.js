/**
 *
 * Expected input: any
 */

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => {
  raw += c;
});
process.stdin.on("end", async () => {
  try {
    const args = JSON.parse(raw);
    console.log(
      JSON.stringify({
        message: "Hi, this is the data you gave me: ",
        args,
      }),
    );
    process.exit(0);
  } catch (e) {
    console.error("Invalid JSON: ", e);
    process.exit(1);
  }
});
