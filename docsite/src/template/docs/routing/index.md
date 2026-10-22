# Routing

DraconicKit is heavily based on SvelteKit. This means DraconicKit has a filesystem-based router. The resolved `target` of incoming HTTP requests is defined by directories containing a route file in your project.

- `src/routes` is your root route (aka, route `/`).
- `src/routes/tailcare` creates a route `/tailcare`.
- `src/routes/jobs/dragons` creates a route `/jobs/dragons`.

## Parameterized Routes

The above examples showed static routes, which only match if the request target exactly matches the pathname defined relative to `src/routes`. However, DraconicKit also features parameterized routes, which act similarly to regex capture groups... without regex.

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

The parameterized routes above only affect the directory slots they occupy, making their depth static. Variadic routes do not have this limitation. Prefixing a normal parameter name with `__` so (`_pathname_` becomes `___pathname_`) makes the route variadic.

- `src/routes/download/___pathname_` creates a route `/download/<any>` that accepts any path starting with `/download`.

It will accept all the routes below:

```
/download/banana.txt
/download/resumes/shinku-cv.pdf
/download/hacktools/based/hoic.exe
/download/whatever

...and so on
```

### Why so many underscores?

Originally, DraconicKit had support for the same route syntax as SvelteKit, however, this feature was dropped. The problem is that Haxe does not allow impots for raw files like NodeJS. The original way DraconicKit worked caused problems with LSPs.

## Duplicate Routes

Let's say you have `/users/settings` and `/users/_username_`, these are duplicates, but a request targetting `/users/settings` will be resolved to the handler of `/users/settings` and not to the handler of `/users/_username_`.

Static routes are given priority over dynamic routes.

## Path traversal

DraconicKit's router normalizes all request targets. A request targeting `/download/../../../etc/passwd` will be normalized to `/etc/passwd` (even if the target contains percent-encoded characters, like `/download/..%2f..%2fetc%2fpasswd`). In the example above, this will not match anything. this normalization is done **before** the route is even looked for.

However, route normalization is not a substitute for validating filesystem paths. If your handler uses a captured parameter to access files, resolve the resulting path against an intended base directory and verify that it remains within that directory before accessing the file.

**Platform note**: DraconicKit does not support Windows. Its URL implementation does not normalize backslash-based traversal sequences such as `..\`, so these sequences may appear in captured route parameters.

## Route Files

In the first paragraph, I had mentioned that a route is a directory containing a route file, but there are man

## +page.svelte

A +page.svelte defines a page of your app, here is an example:

<builder:import src="/res/html/components/codeblock-with-path.html" set-title="src/routes/+page.svelte">
&lt;h1&gt;Hello and welcome to my personal website!&lt;/h1&gt;
&lt;p&gt;I am using Svelte, and Haxe!&lt;/p&gt;
&lt;a href="/about"&gt;About this place&lt;/a&gt;
</builder:import>

Opening the root of your project, with the above file will render it as a page!
