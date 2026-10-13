// Treat all javascript on your project as "client side", and Haxe as "server" side.
// Put client stuff here, or in another JS file. these are ES modules by the way.

export function getSomethingFromHere(): { message: string } {
  console.log("Hello?");

  return { message: "Hello from TypeScript!" };
}
