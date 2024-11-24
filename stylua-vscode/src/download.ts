import type { GitHub, GitHubRelease } from "./github";
import { StyluaType } from "./meta/stylua-type";
import { executeStylua } from "./stylua";
import { fileExists, getAssetFilenamePattern, getDesiredVersion, getDownloadOutputFilename } from "./utilities";
import { createWriteStream } from "fs";
import fetch from "node-fetch";
import * as semver from "semver";
import * as unzip from "unzipper";
import * as vscode from "vscode";
import which = require("which");

export enum ResolveMode {
	Bundled = "bundled",
	Configuration = "configuration",
	Path = "PATH",
}

export interface StyluaInfo {
	readonly paths: readonly [standard: string, react: string];
	readonly resolveMode: ResolveMode;
	version?: string | undefined;
}

async function getStyluaVersion(path: string, cwd?: string) {
	try {
		const versionValue = await executeStylua(path, ["--version"], cwd);
		const currentVersion = versionValue?.trim();
		return currentVersion.slice("stylua ".length);
	} catch {
		return;
	}
}

export class StyluaDownloader implements vscode.Disposable {
	public readonly statusBarUpdateItem = vscode.window.createStatusBarItem(
		"stylua.installUpdate",
		vscode.StatusBarAlignment.Right,
	);

	public constructor(
		private readonly storageDirectory: vscode.Uri,
		private readonly github: GitHub,
		private readonly outputChannel: vscode.LogOutputChannel,
	) {}

	public async findStylua(cwd?: string): Promise<StyluaInfo> {
		// 1) If `stylua.styluaPath` has been specified, use that directly

		const styluaConfiguration = vscode.workspace.getConfiguration("stylua");
		const settingPath = styluaConfiguration.get<null | string>("styluaPath");
		const reactSettingPath = styluaConfiguration.get<null | string>("styluaRoactPath");

		if (settingPath) {
			if (reactSettingPath) {
				this.outputChannel.info(
					`Both Stylua paths explicitly configured: ${settingPath} & ${reactSettingPath}`,
				);

				return {
					paths: [settingPath, reactSettingPath],
					resolveMode: ResolveMode.Configuration,
				};
			}

			this.outputChannel.info(`Stylua path explicitly configured: ${settingPath}`);
			return {
				paths: [settingPath, settingPath],
				resolveMode: ResolveMode.Configuration,
			};
		}

		// 2) Find a `stylua` binary available on PATH
		// TODO: Support new stylua hms stuff
		if (styluaConfiguration.get<boolean>("searchBinaryInPATH")) {
			this.outputChannel.info("Searching for stylua on PATH");
			const resolvedPath = await which("stylua", { nothrow: true });
			if (resolvedPath) {
				this.outputChannel.info(`Stylua found on PATH: ${resolvedPath}`);
				if (await getStyluaVersion(resolvedPath, cwd))
					return { paths: [resolvedPath, resolvedPath], resolveMode: ResolveMode.Path };

				this.outputChannel.error("Stylua binary found on PATH failed to execute");
			}
		}

		// 3) Fallback to bundled stylua version
		this.outputChannel.info("Falling back to bundled StyLua version");
		const downloadPath = vscode.Uri.joinPath(this.storageDirectory, getDownloadOutputFilename());
		return { paths: [downloadPath.fsPath, downloadPath.fsPath], resolveMode: ResolveMode.Bundled };
	}

	public async ensureStyluaExists(
		cwd?: string,
		styluaType: StyluaType = StyluaType.Standard,
	): Promise<StyluaInfo | undefined> {
		const stylua = await this.findStylua(cwd);

		switch (stylua.resolveMode) {
			case ResolveMode.Bundled: {
				const [standard, react] = stylua.paths;
				const path = styluaType === StyluaType.Standard ? standard : react;

				if (!(await fileExists(path))) {
					await vscode.workspace.fs.createDirectory(this.storageDirectory);
					await this.downloadStyluaVisual(getDesiredVersion());
				}

				stylua.version = await getStyluaVersion(styluaType === StyluaType.Standard ? standard : react, cwd);

				// Check bundled version matches requested version
				const desiredVersion = getDesiredVersion();
				if (stylua.version && desiredVersion !== "latest") {
					const desiredVersionSemver = semver.coerce(desiredVersion);
					const styluaVersionSemver = semver.parse(stylua.version);
					if (
						desiredVersionSemver &&
						styluaVersionSemver &&
						semver.neq(desiredVersionSemver, styluaVersionSemver)
					)
						this.openIncorrectVersionPrompt(stylua.version, desiredVersion);
				}

				// Check for latest version
				if (vscode.workspace.getConfiguration("stylua").get("disableVersionCheck"))
					this.statusBarUpdateItem.hide();
				else {
					try {
						const latestRelease = await this.github.getRelease("latest");
						if (
							stylua.version ===
							(latestRelease.tagName.startsWith("v")
								? latestRelease.tagName.slice(1)
								: latestRelease.tagName)
						)
							this.statusBarUpdateItem.hide();
						else this.showUpdateAvailable(latestRelease);
					} catch (error) {
						vscode.window.showWarningMessage(
							`Error checking the selected StyLua version, falling back to the currently installed version:\n${error}`,
						);

						if (!this.github.authenticated) {
							const option = await vscode.window.showInformationMessage(
								"Authenticating with GitHub can fix rate limits.",
								"Authenticate with GitHub",
							);

							switch (option) {
								case "Authenticate with GitHub": {
									if (await this.github.authenticate()) return this.ensureStyluaExists(cwd);
								}
							}
						}
					}
				}

				break;
			}

			case ResolveMode.Configuration: {
				const [standard, react] = stylua.paths;
				const path = styluaType === StyluaType.Standard ? standard : react;

				if (!(await fileExists(path))) {
					vscode.window.showErrorMessage(`The path given for StyLua (${path}) does not exist`);
					return undefined;
				}

				stylua.version = await getStyluaVersion(styluaType === StyluaType.Standard ? standard : react, cwd);
				break;
			}

			case ResolveMode.Path: {
				stylua.version = await getStyluaVersion(stylua.paths[styluaType === StyluaType.Standard ? 0 : 1], cwd);
				break;
			}

			// No default
		}

		return stylua;
	}

	public downloadStyluaVisual(version: string): Thenable<void> {
		return vscode.window.withProgress(
			{
				cancellable: false,
				location: vscode.ProgressLocation.Notification,
				title: `Downloading StyLua (${version})`,
			},
			() => this.downloadStylua(version),
		);
	}

	public dispose(): void {
		this.statusBarUpdateItem.dispose();
	}

	public async getStyluaPath(): Promise<[string | undefined, string | undefined] | undefined> {
		const styluaConfiguration = vscode.workspace.getConfiguration("stylua");
		const settingPath = styluaConfiguration.get<null | string>("styluaPath");
		const reactSettingPath = styluaConfiguration.get<null | string>("styluaRoactPath");

		if (settingPath) return reactSettingPath ? [settingPath, reactSettingPath] : [settingPath, settingPath];

		const downloadPath = vscode.Uri.joinPath(this.storageDirectory, getDownloadOutputFilename());
		if (await fileExists(downloadPath)) return [downloadPath.fsPath, downloadPath.fsPath];

		return undefined;
	}

	private async downloadStylua(version: string): Promise<void> {
		const release = await this.github.getRelease(version);
		const assetFilename = getAssetFilenamePattern();
		const outputFilename = getDownloadOutputFilename();

		for (const asset of release.assets) {
			if (assetFilename.test(asset.name)) {
				const file = createWriteStream(vscode.Uri.joinPath(this.storageDirectory, outputFilename).fsPath, {
					mode: 0o755,
				});

				return new Promise((resolve, reject) =>
					fetch(asset.downloadUrl, { headers: { "User-Agent": "stylua-vscode" } })
						.then((response) => response.body.pipe(unzip.Parse()))
						.then((stream) => {
							stream.on("entry", (entry: unzip.Entry) => {
								if (entry.path !== outputFilename) {
									entry.autodrain();
									return;
								}

								entry.pipe(file).on("finish", resolve).on("error", reject);
							});
						}),
				);
			}
		}
	}

	private showUpdateAvailable(githubRelease: GitHubRelease): void {
		this.statusBarUpdateItem.name = "StyLua Update";
		this.statusBarUpdateItem.text = `StyLua update available (${githubRelease.tagName}) $(cloud-download)`;
		this.statusBarUpdateItem.tooltip = "Click to update StyLua";
		this.statusBarUpdateItem.command = {
			arguments: [githubRelease],
			command: "stylua.installUpdate",
			title: "Update StyLua",
		};
		this.statusBarUpdateItem.backgroundColor = new vscode.ThemeColor("statusBarItem.warningBackground");
		this.statusBarUpdateItem.show();
	}

	private openIncorrectVersionPrompt(currentVersion: string, requestedVersion: string): void {
		vscode.window
			.showInformationMessage(
				`The currently installed version of StyLua (${currentVersion}) does not match the requested version (${requestedVersion})`,
				"Install",
			)
			.then((option) => {
				switch (option) {
					case "Install": {
						vscode.commands.executeCommand("stylua.reinstall");
						break;
					}
				}
			});
	}
}
