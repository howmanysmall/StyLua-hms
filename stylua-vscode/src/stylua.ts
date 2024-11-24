import { exec, spawn } from "child_process";
import * as vscode from "vscode";

export function formatCode(
	outputChannel: vscode.LogOutputChannel,
	path: string,
	code: string,
	filePath?: string,
	cwd?: string,
	startPosition?: number,
	finishPosition?: number,
): Promise<string> {
	return new Promise((resolve, reject) => {
		const formatArguments = ["--respect-ignores"];
		if (filePath) formatArguments.push("--stdin-filepath", filePath);

		if (startPosition) formatArguments.push("--range-start", startPosition.toString());
		if (finishPosition) formatArguments.push("--range-end", finishPosition.toString());

		const styluaConfiguration = vscode.workspace.getConfiguration("stylua");

		const configurationPath = styluaConfiguration.get<string>("configPath");
		if (configurationPath && configurationPath.trim() !== "")
			formatArguments.push("--config-path", configurationPath);

		if (styluaConfiguration.get("searchParentDirectories")) formatArguments.push("--search-parent-directories");
		if (styluaConfiguration.get("verify")) formatArguments.push("--verify");
		formatArguments.push("-");

		outputChannel.debug(`${path} {args.join(" ")}`);
		const child = spawn(`${path}`, formatArguments, { cwd });

		let output = "";

		child.stdout.on("data", (data) => (output += data.toString()));
		child.stdout.on("close", () => resolve(output));
		child.stderr.on("data", (data) => reject(data.toString()));

		child.on("err", () => reject("Failed to start StyLua"));

		// Write our code to stdin
		child.stdin.write(code);
		child.stdin.end();
	});
}

export function executeStylua(path: string, formatArguments?: Array<string>, cwd?: string): Promise<string> {
	return new Promise((resolve, reject) => {
		exec(`"${path}" ${formatArguments?.join(" ") ?? ""}`, { cwd }, (error, stdout) => {
			if (error) reject(error);
			resolve(stdout);
		});
	});
}
