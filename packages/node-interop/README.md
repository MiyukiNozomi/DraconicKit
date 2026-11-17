# This is a replacement of the old 'scripts' directory.

This is a long lived daemon of sorts that communicates with the main DraconicKit builder process through Standard io.

And yes, this part of the project is basically a hack.
There's no such thing as a good JS engine for the JVM, and DraconicKit right now needs a lot more than just build Svelte.
So this serves as a way to diverge our focus back into core features so later a proper JS engine can be used.
