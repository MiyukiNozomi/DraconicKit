# Hi! miyuki here.

## This module was **vibecoded**!

And yeah, I hate to say and do this, but you have to understand that ive spent 6 days of my life non-stop trying to fight NodeJS's idiotic ecosystem.
Please. if you have the sanity, the time, and the will power, I encourage you to reimplement this properly.

This code was written by claude. not me.

## The purpose, the why, and how:

Svelte doesnt generate vanilla-JS out of the box, instead, it actually generates ESM (ECMA Script Modules) with NodeJS style imports.
The browser's imports are different from the imports you would write on a NodeJS project.

For example, the following will be resolved in the exact same way by both:

```js
import foo from "./bar.js";
import foo from "/bar.js";
import foo from "../bar.js";
```

Now the follwing, is NodeJS/any other non-browser runtime specific:

```js
import hell from "dantes-inferno";
import hell from "@dante/inferno";
import redstone from "#minecraft";
```

The firsst two resolve to the innermost node_modules the resolver can find, with the exception that the @ thingy on the start makes the package name be "@dante/inferno" and not just "@dante", the last one is a private, defined in package.json "import map" to a file.

and up until here it is simple, but complexity quickly becomes unberable. let's go over the "main" and "exports" of a package.json:

When you have only a "main" on your package.json, just importing your package with something like `import foo from "bar"` will read from your main.
_one thing i noticed is that it handles "bar/" differently than "bar". absolute heresy._

When you have a `exports`, it ignores `main` (at least that's what I understood) and looks for the subpath of your import in exports.

Here's what that "subpath" looks like on different conditions:

```js
import hell from "dantes-inferno"; // subpath "."
import hell from "@dante/inferno"; // subpath "."
import hell from "@dante/inferno/demons"; // subpath "./demons"
```

And then you would think that, because `exports` in the package.json is usually a map, you can just get exports[subpath\], but nope! this heretic is a son of a bitch that introduces a system of conditions, fallbacks and a bunch of other crap! And to add insult to injury? it's recursive!

All of these are valid package.json exports definitions:

```json
{
  "exports": {
    // a subpath of '.' will refer to main.js
    ".": "./main.js",
    // a subpath of './banana' will refer to ./banana.js
    "./banana": "./banana.js",

    // this crap is conditional
    "./torturemaschinen": {
      // if on a browser..
      "browser": "./browser-torture.js",
      "development": "./dependency-hell-creator.js",
      // if none of the above match
      "default": "./torture-everyone.js"
    },

    // this one will try multiple files for './missiles' until it finds one that exists / is valid
    "./missiles": [
      "./aim-120c.js",
      "./aim-120-amraam.js",
      "./aim-9x-sidewinder.js",
      "./aim-9m-sidewinder.js",
      "./aim-424-lraam-malice.js"
    ]
  }
}
```

Also, `exports` itself can be any of those values, it can be an array of fallbacks, it can be a conditions object, and you can **event nest that crap**:

```json
{
  "exports": {
    "browser": {
      // a subpath of '.' will refer to main.js
      ".": "./icbm-implementation.js",
      // this one will try multiple files for './missiles' until it finds one that exists / is valid
      "./missiles": [
        "./aim-120c.js",
        "./aim-120-amraam.js",
        "./aim-9x-sidewinder.js",
        "./aim-9m-sidewinder.js",
        "./aim-424-lraam-malice.js"
      ]
    },
    "node": {
      ".": "./node-icbm-implementation.js",
      "./missiles": [
        "./node-aim-120c.js",
        "./node-aim-120-amraam.js",
        "./node-aim-9x-sidewinder.js",
        "./node-aim-9m-sidewinder.js",
        "./node-aim-424-lraam-malice.js"
      ]
    }
  }
}
```

And yes, remember that #importmap thing? you can use the same exports conditions, fallbacks and paths for #import.

You can also have for some reason wildcards like:

```json
{
  "exports": {
    // if you import "foo/tortures/chinese-water-drops", it will resolve into ./torture-impls/chinese-water-drops.js
    "./tortures/*": "./torture-impls/*.js"
  }
}
```

Also to add insult to injury, you cant just solve the dependencies of a dependency by your root node_modules because some evil person on NodeJS decided it should nest node_modules one inside of the other.

So svelte/compiler can depend on acorn, and NPM/Yarn/PNPM can decide to put acorn on node_modules/svelte/node_modules/acorn.

And that, ladies and gentlemen, is why the entirety of the ES Module resolver is vibecoded.

### The Irony

I actually started working on DraconicKit because of this complexity, Haxe, is beautifully simple, easy to use, imune to the dependency hell of JS, and at the end of the day? I ended up having to fight JS's bugs anyway, at least it's written in Haxe. The code Claude wrote isn't awful to read, but the fact i resorted to this will forever haunt me until someone or me rewrite this.

I am glad if DraconicKit was at least able to make a developer not suffer through the footguns of JS like Ive been for the past years.
