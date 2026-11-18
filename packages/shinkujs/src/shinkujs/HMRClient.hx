package shinkujs;

import js.Browser;
import js.html.EventSource;

class HMRClient {
	private var sse:EventSource;

	public function new() {
		sse = new EventSource("/@draconickit/hmr");

		sse.onerror = () -> {
			Shinku.error("Connection with HMR channel has been lost!");
		};

		sse.addEventListener("invalidate-all", (event) -> {
			Shinku.debug("invalidate-all received from server:", event.data);
			Browser.window.location.reload();
		});
	}
}
