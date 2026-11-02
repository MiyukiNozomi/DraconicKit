# Documentation Site

This is a weird way to write documentation, I know, but i value hand written docs over code-generated ones.

The way this works is that there is a templates directory with.. well.. XHTML page templates, and a builder script to "build" said markdown files into a page github pages can read.

## What? did you just say.. XHTML?

If you don't know XHTML, it's basically XML with HTML tags. it's stricter (which also doubles as VERY easy to parse and transform).

This documentation is not written with DraconicKit itself as DraconicKit is intended for dynamic websites and not static ones.

Also, features 0 runtime javascript! and generates it's own haxe API reference.

## Using this

This is a weird little sub-project, to use it:

### Install dependencies:

```
haxelib fixrepo
haxelib install hxjava
haxelib install markdown
haxelib install hscript
```

### Building and Running

For the development server:

```
haxe build.hxml && java -jar bin/DocBuilder.jar
```

To build a static site simply pass `build` to the DocBuilder.jar file. (if you're going to do a PR, PLEASE! try to build it with the command bellow first!)

```
java -jar bin/DocBuilder.jar build
```

### Builder Syntax

TODO! but you can check the xhtml files inside of src/ to see examples
