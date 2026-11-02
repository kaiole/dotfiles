import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const SESSIONIZER = join(homedir(), ".local/bin/tmux-sessionizer");

export default function (pi: ExtensionAPI) {
  pi.registerShortcut("ctrl+f", {
    description: "Open tmux sessionizer",
    handler: async (ctx) => {
      if (!process.env.TMUX) {
        ctx.ui.notify("tmux-sessionizer: not inside tmux", "error");
        return;
      }

      try {
        spawn(SESSIONIZER, [], {
          detached: true,
          stdio: "ignore",
          env: process.env,
        }).unref();
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(`tmux-sessionizer failed: ${message}`, "error");
      }
    },
  });
}
