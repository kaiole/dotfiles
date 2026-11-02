import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { registerWebTools } from "./src/tools";

export default function (pi: ExtensionAPI) {
	registerWebTools(pi);
}
