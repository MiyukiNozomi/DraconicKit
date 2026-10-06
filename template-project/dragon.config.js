/**
 * @returns {import("./.shinku/generated/draconic.config").DraconicConfig}
 */
export default function getServerConfig() {
  return {
    builder: {},
    server: {
      host: "0.0.0.0",
      port: 6173,
      static_dir: "static/",
    },
  };
}
