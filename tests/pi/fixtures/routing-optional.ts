export default function (pi) {
  pi.registerMcpServer("optional", { url: `${process.env.SPIKE_GATEWAY}/mcp` });
}
