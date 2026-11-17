T.pending("rejected promise is caught by handler");
Promise.reject(new Error("handled")).catch(function (e) {
  T.check("rejected promise is caught by handler", e.message === "handled");
});

// Informational only: no handler attached. Your host may or may not see this.
// If your host has a hook for unhandled rejections, wire it up and compare.
Promise.reject(new Error("unhandled probe"));
T.note(
  "unhandled rejection",
  "no handler attached; check whether the host is notified",
);
