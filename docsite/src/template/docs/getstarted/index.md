# Get Started

Welcome to DraconicKit, before starting, there are a few requirements, the setup procedure, and things you should keep in mind.

## Limitations

#### (because you should be aware of this above all else)

Think of this as a TODO list, highest priority first:

- **No production build mode** - I am still polishing the development mode before finishing the production builder.

- **No TypeScript support** - Mostly because of a lack of testing, Microsoft has recently deprecated the TypeScript compiler API with their rewrite to golang, so I am a bit indecise on how TS support should be.

- **No support for WebSockets** - DraconicKit has its own HTTP server implementation, it only supports HTTP 1.1 and Chunked Transfer Encoding in both inbound and outbound messages.

- **No HMR in Svelte pages** - WebSockets would be the natural way to push reload events, and polling would clutter the Network tab... but not to worry, API endpoints are reloaded in real time when their source code is edited.

## System Requirements

To use DraconicKit, the following is required to be installed in your system:

- The [Haxe Compiler](https://haxe.org/download/). _(I recommend you to use the Haxe 5 preview, as that is the version of haxe used to built the heart of the dragon.)_
- A Java 10+ JDK. _(This is a development-only requirement, you can use any Sys + Threading capable haxe target in production.)_
- Node.js and a Node package manager. _(This is for front-end dependencies like FontAwesome, not backend dependencies.)_
- A POSIX-Compliant system _(Windows is not yet supported, but might work under WSL and definitely under Docker.)_

Ideally you should also know the [Haxe Programming Language](https://haxe.org/documentation/introduction/), but any experience with Java, C# or even ActionScript will already serve as a good starting point for haxe.

## Installing DraconicKit

Clone the respository first:

```
git clone https://github.com/MiyukiNozomi/DraconicKit
```

Then simply build:

```
cd DraconicKit
haxe build-release.hxml
```

Now, sym-link `draconickit` or add this folder to your PATH, and draconickit will be ready to be used.

## Creating a Project

Simply run `draconickit init` and a setup will start a project relative to it's current directory. To specify a directory, you can use `draconickit init [dirname]`.

## “It doesn’t work with pnpm\!”

Yes, unfortunately, pnpm isn’t supported yet, and this is a limitation I was aware of from the beginning.

The issue comes down to differences between how Node.js resolves ESM (ECMAScript Modules) imports and how browsers handle them. DraconicKit’s ESM resolver was originally designed around the more traditional `node_modules` directory structure, which makes it difficult to work with pnpm’s different approach to managing dependencies.

From what I’ve seen so far, it’s a bit more involved than simply following symlinks.

**This isn’t a problem with pnpm itself**, but rather a limitation of DraconicKit’s current resolver implementation. Supporting pnpm properly will require some additional work on my end.

(there is a workaround, just make sure to **choose pnpm when initializing the project** or by adding `node-linker=hoisted` on your `.npmrc` and reinstalling your dependencies.)

## Before jumping into coding...

### Your Project's Architecture

This section covers how to structure your code, especially if you're coming from JavaScript frameworks like SvelteKit. Read it before you write your first route!

In JS, concurrency is handled through `async`. It's a clever trick, but it isn't true multithreading: the runtime works on one thing until it hits something that needs waiting, then hops over to another promise (or async function) while it waits.

DraconicKit doesn't play that game. It isn't Promise-based. Your server runs on real, physical CPU threads (like a true madman!), and incoming HTTP requests get spread across all of them. More claws, more power.

With great power comes the main thing to watch out for: **thread safety**. The callbacks your server runs in response to requests do _not_ execute one at a time. Say you have a GET handler at `/api/hi` and 12 clients hit it at once. That callback runs 12 times in parallel, not in a neat line.

**I plan to add an option for a more event-loop-driven architecture, where connections are handled in parallel but server handling goes through a queue.** Until then, keep one question in the back of your mind whenever you write routes and server hooks:

> "What happens when six people hit this endpoint at the same time?"

If you have a good answer, you're ready to go. If not, the dragon will bite.

#### What should I do?

Lock it down. Reach for locks, concurrent maps, thread-safe lists, and thread-safe database libraries.

Using a library with global state? If neither its docs nor its code say anything about thread safety, don't just hope for the best. Either wrap it in a lock, or isolate that state so each request gets its own copy.

I'd strongly recommend reading the [Multithreading](/docs/standard/#multithreading) section of the standard library chapter. It walks through the bad and the good.

### Okay! I am ready!

Hop onto the chapter [Routing](/docs/routing/) for the fun to start.
