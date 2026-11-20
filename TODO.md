# List of DraconicKit (by package)

## Core DraconicKit

- [ ] Documentation generator for API reference does not support Abstract types.

- [ ] Form Data
- [ ] Custom error pages in HandlerTools#error
- [ ] Http Responses and Requests do not support compression.

- [ ] Add builder for production

- [ ] `Executor.setTimeout` and `Executor.setInterval`

- [ ] (reintroduce) Support for TypeScript
- [ ] Generate TypeScript type declarations for Haxe files (like SSE and the `@:expose` metadata.)
- [ ] Generate TypeScript type declarations for component props

- [ ] Declarations such as `inline function locked<R>(fn:() -> R):R` are incorrectly generated as fields in the externs generator for Haxe, even though it's a function. the result is that it will not contain type parameters.
- [ ] Default type parameter declarations are ignored. RequestEvent<T = Dynamic> will generate as RequestEvent<T>. (This is likely unfixable without a custom metadata specifying default type params)

- [ ] HMR

- [ ] `draconickit init` has a poor failure mode.
- [ ] `draconickit help` has a problem where it is not properly unicode aware, and may be dealigned in certain terminals.

## Esper

## ShinkuJS

- [ ] HMR APIs
