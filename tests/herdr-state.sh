#!/usr/bin/env bash
# Real Pi Herdr extension with a fake pane socket. No Pi process, network or Herdr daemon is needed.
#
# Contract
#   - A silent Herdr socket does not hold up session_start, so initial state can publish immediately.
#   - A Pi launched by an agent shell tool inherits PI_SESSION_ID and must not replace the pane's root session.
#   - A root Pi still reports its session.
set -euo pipefail

cd "$(dirname "$0")/.."
fail() {
    echo "herdr-state: $1" >&2
    exit 1
}
[ ! -e .git ] || fail "run through test:offline, not in a real checkout"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat >"$work/probe.ts" <<'EOF'
import net from "node:net";

const [extension, scenario, socketPath] = process.argv.slice(2);
const sockets = new Set<net.Socket>();
let reports = 0;
const server = net.createServer((socket) => {
    sockets.add(socket);
    socket.on("data", () => {
        reports += 1;
        // Keep the socket open without answering: the extension must not wait for this response.
    });
    socket.on("close", () => sockets.delete(socket));
});
await new Promise<void>((resolve) => server.listen(socketPath, resolve));

const finish = async (error?: string) => {
    for (const socket of sockets) socket.destroy();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    if (error) {
        console.error(error);
        process.exit(1);
    }
    process.exit(0);
};

process.env.HERDR_ENV = "1";
process.env.HERDR_SOCKET_PATH = socketPath;
process.env.HERDR_PANE_ID = "pane-test";
if (scenario === "nested") process.env.PI_SESSION_ID = "parent-session";

const { default: register } = await import(`${extension}?scenario=${scenario}`);
const handlers = new Map<string, (...args: any[]) => any>();
register({
    on: (name: string, handler: (...args: any[]) => any) => handlers.set(name, handler),
    events: { on: () => undefined },
});
const sessionStart = handlers.get("session_start");
if (scenario === "nested" && !sessionStart) {
    await finish();
}
if (!sessionStart) {
    await finish("session_start was not registered");
}
const ctx = {
    mode: "tui",
    isIdle: () => false,
    sessionManager: {
        getSessionFile: () => "/tmp/pi-session.jsonl",
        getSessionId: () => "session-test",
    },
};
const outcome = await Promise.race([
    Promise.resolve(sessionStart({ reason: "startup" }, ctx)).then(() => "returned"),
    new Promise<string>((resolve) => setTimeout(() => resolve("blocked"), 250)),
]);
if (outcome !== "returned") {
    await finish(`${scenario} session_start waited for a silent Herdr socket`);
}
await new Promise((resolve) => setTimeout(resolve, 100));
if (scenario === "nested" && reports !== 0) {
    await finish("a tool-spawned nested Pi reported over its parent pane session");
}
if (scenario === "root" && reports === 0) {
    await finish("the root Pi did not report its session");
}
await finish();
EOF

bun_bins=("$HOME"/.local/share/mise/installs/bun/*/bin/bun)
[ -x "${bun_bins[0]}" ] || fail "the agent image has no Bun binary"
bun=${bun_bins[0]}
"$bun" "$work/probe.ts" "$PWD/home/.config/pi/agent/extensions/herdr-agent-state.ts" root "$work/root.sock"
"$bun" "$work/probe.ts" "$PWD/home/.config/pi/agent/extensions/herdr-agent-state.ts" nested "$work/nested.sock"
echo "herdr-state: ok"
