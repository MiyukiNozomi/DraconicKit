# Routing

DraconicKit is heavily based on SvelteKit. This means DraconicKit has a filesystem-based router. The resolved `target` of incoming HTTP requests is defined by directories containing a route file in your project.

- `src/routes` is your root route (aka, route `/`).
- `src/routes/tailcare` creates a route `/tailcare`.
- `src/routes/jobs/dragons` creates a route `/jobs/dragons`.

## Parameterized Routes

The above examples showed static routes, which only match if the request target exactly matches the pathname defined relative to `src/routes`. However, DraconicKit also features parameterized routes, which act similarly to regex capture groups... without regex.

The parameters of a route will always be available in the request handler's `RequestEvent.params`.

These routes can be defined by a word surrounded by `_` (like this: `_username_`). Here are some examples:

- `src/routes/users/_username_` creates a dynamic route `/users/<any>`. It will only match targets like:

```
/users/miyuki
/users/suisei
```

But not `/users/halflife3/whereabouts`.

- `src/routes/users/_username_/posts/_id_` creates a dynamic route `/users/<any>/posts/<any>`. Like the above, it will only match targets such as:

```
/users/miyuki/posts/4
/users/suisei/posts/9
/users/shinku/posts/94
```

But not `/users/shinku/posts/95/banana`.

<builder:import src="/res/html/components/warning.html">

<p><builder:markdown>Parameterized routes **do not perform validation** of route parameters. A route like `/users/dr.doofenshmirtz/posts/hackinator` will, in fact, match this route.

Be a good dragon and always validate user input! Never trust anything that comes from a client. **The less exposed, the merrier!** </builder:markdown></p>
</builder:import>

## Variadic Routes

The parameterized routes above only affect the directory slots they occupy, making their depth static. Variadic routes do not have this limitation. Prefixing a normal parameter name with `__` (so `_pathname_` becomes `___pathname_`) makes the route variadic.

- `src/routes/download/___pathname_` creates a route `/download/<any>` that accepts any path starting with `/download/`.

It will accept all the routes below:

```
/download/banana.txt
/download/resumes/shinku-cv.pdf
/download/hacktools/based/hoic.exe
/download/whatever

...and so on
```

### Why so many underscores?

Originally, DraconicKit had support for the same route syntax as SvelteKit, however, this feature was dropped. The problem is that Haxe can’t import arbitrary files like Node can, which broke LSP support.

## Overlapping Routes

Let's say you have `/users/settings` and `/users/_username_`, these are overlapping, but a request targeting `/users/settings` will be resolved to the handler of `/users/settings` and not to the handler of `/users/_username_`.

Static routes are given priority over dynamic routes.

## Path traversal

DraconicKit's router normalizes all request targets. A request targeting `/download/../../../etc/passwd` will be normalized to `/etc/passwd` (even if the target contains percent-encoded characters, like `/download/..%2f..%2fetc%2fpasswd`). In the example above, this will not match anything. This normalization is done **before** the route is even looked for.

However, route normalization is not a substitute for validating filesystem paths. If your handler uses a captured parameter to access files, resolve the resulting path against an intended base directory and verify that it remains within that directory before accessing the file.

**Platform note**: DraconicKit does not support Windows. Its URL implementation does not normalize backslash-based traversal sequences such as `..\`, so these sequences may appear in captured route parameters.

## Route Files

In the first paragraph, I had mentioned that a route is a directory containing a route file, but there are different route file types, and combinations!

## +page.svelte

This is simply a svelte component that defines a page in your app. Here's an example:

<builder:import src="/res/html/components/codeblock-with-path.html" set-title="src/routes/+page.svelte">

```
<h1>Hello and welcome to my personal website!</h1>
<p>I am using Svelte and Haxe!</p>
<a href="/about">About this place</a>
```

</builder:import>

Placing the above file in your project's root route will render it as a page!

**Here's how it should look like when you navigate to that route:**

<img class="screenshot" src="/res/screenshots/sveltePageExample.webp" title="Screenshot of a basic svelte page.">

## Server.hx

Like pages, routes can also be defined using a file named `Server.hx`, which functions similarly to an API route or endpoint. This file gives you control over the HTTP response.

In a similar fashion to SvelteKit, all public functions with the name of a HTTP method will become a route for that specific method. The example bellow showcases a `GET`-only route:

**Be aware you cannot have both a `+page.svelte` file and a `Server.hx` in the same route directory.**

<builder:import src="/res/html/components/codeblock-with-path.html" set-title="src/routes/api/hello/Server.hx">

```
package routes.api.hello;

import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;

class ServerHandler extends AbstractHandler {
	public function GET(event:RequestEvent) {
		text("Hello, Moonlit Crimson Dragon!");
	}
}
```

</builder:import>

## Http Responses

In SvelteKit, route handlers return a `Response` object. In DraconicKit, you quite literally throw responses instead. If you wrap your route handler in a `try-catch` block, make sure to cast (you can use Std.downcast, which returns null if the cast is not possible) the caught exception to DraconicKit's `HttpResponse` type and rethrow it.

## Response helpers

These helpers allow you to return specific types of data without explicitly specifying the status code or content type. Their second parameter allows you to specify a custom status code, along with custom headers.

- `json` is a helper intended for returning `application/json` responses.
- `text` is a helper intended for returning `text/plain` responses.
- `error` is a helper intended for returning errors. It is still a work in progress and currently returns the error to the client as text/plain. In the future, it will render a Svelte page defined in your project. (You should not use it for API endpoints)

You can also manually throw a new instance of HttpResponse for things like streams and buffers. But you DO NOT have to `throw` the helpers themselves.

### Reading route's parameters

Route parameters are always available through the `RequestEvent` parameter, here's an example:

<builder:import src="/res/html/components/codeblock-with-path.html" set-title="src/routes/users/_username_/posts/_id_">

```
package routes.users._username_.posts._id_;

import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;

class ServerHandler extends AbstractHandler {
	public function GET(event:RequestEvent) {
		text("These are your route parameters: " + event.params.toString());
	}
}

```

</builder:import>

## ServerPage.hx

This type of route file can only be used alongside a `+page.svelte` file in the same directory.

It allows you to intercept the request pipeline immediately before the page is sent to the client. For example, if you want to send data from your server to your page, such as a catalog of products, you can use a `ServerPage.hx` to provide that data.

Here's what your `/catalog` route could look like:

**Notice how we return the data to be sent as props rather than throwing it as an exception.**

<builder:import src="/res/html/components/codeblock-with-path.html" set-title="src/routes/catalog/ServerPage.hx">

```
package routes.catalog;

import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler.AbstractServerPage;

class ServerPage extends AbstractServerPage {
	public function pageServerLoad(event:RequestEvent<Dynamic>) {
		final catalog = /* fetch this from a database, file, or anything you wish.*/ {
			products: [
				{name: "Refreshing Glacier", price: 5400},
				{name: "Tofu Steak", price: 15400},
				{name: "Salty Tornado", price: 7400},
				{name: "Seaside White", price: 10400}
			]catalog
		};
		return catalog;
	}
}
```

</builder:import>
<builder:import src="/res/html/components/codeblock-with-path.html" set-title="src/routes/catalog/+page.svelte">

```
<script>
  let props = $props();
</script>

<div class="header">
  <h1 style="margin: 0; font-size: 32px;">🛒 24hour online catalog</h1>
  <p style=" margin-bottom: 0;">Welcome! Best prices on hetherau!</p>
</div>

<div class="catalog">
  <h2 style="color: #000099; border-bottom: 2px solid #000099;">Our Products</h2>

  {#each props.products as product}
    <div class="item">
      <h3 style="margin: 0; color: #000099;">{product.name}</h3>
      <p class="price">{product.price} fons</p>
      <p><a href="#nope">[ Buy Now ]</a></p>
    </div>
  {/each}
</div>

<div class="footer">
  <p>Copyright &copy; 2006 24hour Online Catalog</p>
  <p>Hosted on DraconicKit!</p>
</div>

<style>
  * { font-family: "Times New Roman", serif; }
  .header {
    background: #000099;
    color: white;
    padding: 15px;
    border: 3px outset #6666cc;
  }
  .catalog {
    background: white;
    margin: 20px auto;
    padding: 10px;
    border: 2px solid #666666;
    max-width: 700px;
  }
  .item {
    background: #eeeeee;
    border: 1px solid #999999;
    margin: 10px 0;
    padding: 10px;
  }
  .price {
    color: #cc0000;
    font-size: 20px;
    font-weight: bold;
    background: #ffff99;
    display: inline-block;
    padding: 3px;
  }
  a {
    color: #0000ee;
    text-decoration: underline;
    font-weight: bold;
  }
  a:visited {
    color: #551a8b;
  }
  .footer {
    text-align: center;
    font-size: 12px;
    color: #555555;
  }
</style>

```

</builder:import>

Now, if you open `/catalog`, you'll find a rather nostalgic page rendered using server-provided props!

<img class="screenshot" src="/res/screenshots/serverPageExample.webp" title="Screenshot of the rendered page with ServerPage.hx">

#### "What if I want to cancel the page load and return an error?"

You can throw an `HttpResponse` inside `ServerPage.hx` to immediately cancel the loading of it's page file. Like this:

<builder:import src="/res/html/components/codeblock-with-path.html" set-title="src/routes/catalog/ServerPage.hx">

```
package routes.catalog;

import haxe.Json;
import sys.io.File;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler.AbstractServerPage;

class ServerPage extends AbstractServerPage {
	public function pageServerLoad(event:RequestEvent<Dynamic>) {
		var catalog = {};
		try {
			catalog = Json.parse(File.getContent("catalog.json"));
		} catch (e) {
			trace(e);
			error(500, "Catalog file is missing on the server!");
		}
		return catalog;
	}
}


```

</builder:import>
