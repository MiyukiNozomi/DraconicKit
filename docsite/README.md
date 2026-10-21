# Documentation Site

This is a weird way to write documentation, I know, but i value hand written docs over code-generated ones.

The way this works is that there is a templates directory with.. well.. HTML page templates, and a builder script to "build" said markdown files into a page github pages can read.

## Using this

This is a weird little sub-project, to use it:

### Install dependencies:

```
yarn install
# this is so it will generate bindings to the node-html-parser library
yarn dts2hx --all --modular --esm

# haxe dependencies
haxelib fixrepo
haxelib install hxnodejs
haxelib install markdown
haxelib install hscript
```

(you dont have to use yarn, you can just `npm install` and `npx dts2hx node-html-parser` if you want.)

### Building and Running

For the development server:

```
haxe build.hxml && node .
```
