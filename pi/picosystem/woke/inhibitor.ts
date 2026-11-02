import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";

/** The pipe closes even on SIGKILL. No persistent daemon or PID polling needed. */
export const HOLDER = 'printf "ready\\n"; read -r _woke; exit 0';

export class IdleInhibitor {
	private child?: ChildProcessWithoutNullStreams;
	private pending?: Promise<void>;
	active = false;

	private readonly onFailure: (message: string) => void;

	constructor(onFailure: (message: string) => void) {
		this.onFailure = onFailure;
	}

	acquire(): Promise<void> {
		if (this.pending) return this.pending;
		if (this.child) return Promise.resolve();
		const child = spawn("systemd-inhibit", [
			"--what=idle", "--mode=block", "--who=woke", "--no-ask-password",
			"--why=pi is working", "--", "/bin/sh", "-c", HOLDER,
		], { stdio: ["pipe", "pipe", "pipe"] });
		this.child = child;
		let stderr = "";
		child.stderr.on("data", (data: Buffer) => { stderr = (stderr + data.toString()).slice(-4096); });
		// A failed spawn or early exit can close stdin before release().
		child.stdin.on("error", () => {});
		this.pending = new Promise<void>((resolve) => {
			let ready = false;
			let reported = false;
			const finish = () => {
				clearTimeout(timer);
				if (this.child === child) this.pending = undefined;
				resolve();
			};
			const fail = (message: string) => {
				if (this.child === child && !reported) {
					reported = true;
					this.onFailure(message);
				}
			};
			const timer = setTimeout(() => {
				fail("Timed out acquiring the idle inhibitor");
				finish();
				if (this.child === child) this.release();
				child.kill();
			}, 5000);
			child.stdout.once("data", () => {
				ready = true; // Only the command run AFTER lock acquisition writes stdout.
				if (this.child === child) this.active = true;
				finish();
			});
			child.on("error", (error) => { fail(error.message); finish(); });
			child.once("close", (code, signal) => {
				fail(stderr.trim() || `Idle inhibitor ${ready ? "stopped unexpectedly" : "failed"} (${signal ?? code})`);
				finish();
				if (this.child === child) {
					this.child = undefined;
					this.active = false;
				}
			});
		});
		return this.pending;
	}

	release(): void {
		const child = this.child;
		this.child = undefined;
		this.pending = undefined;
		this.active = false;
		// EOF makes the shell exit, then systemd-inhibit closes its lock FD.
		child?.stdin.destroy();
	}
}
