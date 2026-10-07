/**
 *
 * Welcome to DragonKit!
 *
 * This is your project's config file.
 * You can also alter Svelte's Compiler options here.
 * It is not typescript (sorry) because that would create a build time dependency on it. but it's fine as long as the latter @returns isnt removed.
 *
 * Please  do not return an object that doesnt matches DraconicConfig!
 * If by any reason the auto completion isn't giving suggestions even with an empty object,
 * consider running the 'build' task of the builder. It will generate the draconic.config.d.ts file this file depends on.
 *
 * Happy coding! and may your Haxe backend adventures be full of joy.
 *
 * @returns {import("./.shinku/generated/draconic.config").DraconicConfig}
 */
export default function getServerConfig() {
  return {
    builder: {},
    server: {
      host: "0.0.0.0",
      port: 8173,
      static_dir: "static/",
    },
  };
}
