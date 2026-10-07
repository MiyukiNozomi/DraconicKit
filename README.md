# DraconicKit - A SvelteKit inspired.. SvelteKit replacement!

This is NOT a drop-in replacement, DraconicKit is a SvelteKit inspired framework for backends. The problem it's trying to solve is the
inconvenience of having one project for the backend, and a separate svelte project to communicate with the backend, and this type of setup leads to a bunch of disgusting problems:

- Synchronization of types between frontend and backend;
- Loss of Server Side Rendering;
- Stuff like page restrictions first require a browser interaction;
- Having weird bugs/CORS issues appear from forwarding or from having the API In a separate web server.

DraconicKit gives you the convinience of a SvelteKit project, but without JavaScript being in the backend. with the benefict of giving you multiple runtimes to target, be it compiling your project into native code, or having it run on top of the JVM (Thanks to Haxe).

Also, be aware of a few limitations.

## TODO list

[ ] HMR
[X] Routing
[ ] Documentation
