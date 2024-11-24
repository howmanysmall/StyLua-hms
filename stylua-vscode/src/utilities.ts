// Based off https://github.com/Kampfkarren/selene/blob/master/selene-vscode/src/util.ts
// Licensed under https://github.com/Kampfkarren/selene/blob/master/LICENSE.md

import * as os from "os";
import * as vscode from "vscode";

export function getDownloadOutputFilename(): string {
	switch (os.platform()) {
		case "win32": {
			return "stylua.exe";
		}

		case "linux":
		case "darwin": {
			return "stylua";
		}

		default: {
			const exception = new Error("platform not supported");
			exception.name = "BadPlatformError";
			Error.captureStackTrace(exception, getDownloadOutputFilename);
			throw exception;
		}
	}
}

export function getAssetFilenamePatternForPlatform(platform: string, architecture: string): RegExp {
	let platformPattern: string;
	switch (platform) {
		case "win32": {
			platformPattern = "(windows|win64)";
			break;
		}

		case "linux": {
			platformPattern = "linux";
			break;
		}

		case "darwin": {
			platformPattern = "macos";
			break;
		}

		default: {
			const exception = new Error("platform not supported");
			exception.name = "BadPlatformError";
			Error.captureStackTrace(exception, getAssetFilenamePatternForPlatform);
			throw exception;
		}
	}

	let architecturePattern: string;
	switch (architecture) {
		case "arm64": {
			architecturePattern = "aarch64";
			break;
		}

		case "x64": {
			architecturePattern = "x86_64";
			break;
		}

		default: {
			architecturePattern = "";
		}
	}

	return new RegExp(`${String.raw`stylua(-[\dw\-\.]+)?-` + platformPattern}(-${architecturePattern})?.zip`);
}

export function getAssetFilenamePattern(): RegExp {
	return getAssetFilenamePatternForPlatform(os.platform(), process.arch);
}

export function getDesiredVersion(): string {
	const styluaConfiguration = vscode.workspace.getConfiguration("stylua");
	const targetVersion = styluaConfiguration.get<string>("targetReleaseVersion", "").trim();

	// TODO: Backwards compatibility to support deprecated setting `stylua.releaseVersion`
	return targetVersion.length === 0 ? styluaConfiguration.get<string>("releaseVersion", "latest") : targetVersion;
}

function returnTrue(): boolean {
	return true;
}
function returnFalse(): boolean {
	return false;
}

export function fileExists(path: string | vscode.Uri): Thenable<boolean> {
	const uri = path instanceof vscode.Uri ? path : vscode.Uri.file(path);
	return vscode.workspace.fs.stat(uri).then(returnTrue, returnFalse);
}
