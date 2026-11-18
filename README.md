![Draconic Kit's Logo](packages/draconic-kit-wordmark.webp)

# DraconicKit - A SvelteKit inspired.. SvelteKit replacement!

This is NOT a drop-in replacement, DraconicKit is a SvelteKit inspired framework for backends. The problem it's trying to solve is the
inconvenience of having one project for the backend, and a separate svelte project to communicate with the backend, and this type of setup leads to a bunch of disgusting problems:

- Synchronization of types between frontend and backend;
- Loss of Server Side Rendering;
- Stuff like page restrictions first require a browser interaction;
- Having weird bugs/CORS issues appear from forwarding or from having the API In a separate web server.

DraconicKit gives you the convinience of a SvelteKit project, but without JavaScript being in the backend. with the benefict of giving you multiple runtimes to target, be it compiling your project into native code, or having it run on top of the JVM (Thanks to Haxe).

Also, be aware of a few limitations.

# How to use this?

Refer to [documentation](https://draconickit.ane.jp.net).

# How to build this?

Simply run `haxe build.hxml`, if you wish for a debug build, run `haxe build-dev.hxml`.
For the global `draconickit` command, run `haxe install.hxml` and symlink the script into a directory in your PATH environment.
(please be aware this will re-build draconickit in release mode. You can re-build it as `build-dev.hxml`)

If you're going to be working on this, run `node watch.js`, which will watch for changes on packages/ and rebuild the project.

# A few notes

If you build draconickit from `build-dev.hxml`, it will set `Configuration.CleanupAlways = true`, which will always completely remove the `.shinku` working directory every time it starts, this is done so that the hot reloader wont load old code cache built against the stale user libraries.

Another import thing is conditional compilation, normally, a draconic kit project has `dev` as it's development mode flag. However, the builder itself has it's own dev flag. being `draconicdev`. Code that is specific to the draconic builder needs to be encloused in a check against `draconicbuilder`.

## TODO list

- [ ] HMR
- [x] Server Sent Events
- [ ] Form Data
- [x] WebSockets
- [ ] Add builder for production
