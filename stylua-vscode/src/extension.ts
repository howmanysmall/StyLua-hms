import { ResolveMode, StyluaDownloader, type StyluaInfo } from "./download";
import { GitHub, type GitHubRelease } from "./github";
import { StyluaType } from "./meta/stylua-type";
import { formatCode } from "./stylua";
import { getDesiredVersion } from "./utilities";
import * as semver from "semver";
import * as vscode from "vscode";

const documentSelector = ["lua", "luau"];

/**
 * Convert a Position within a Document to a byte offset.
 * Required as `document.offsetAt(position)` returns a char offset, causing inconsistencies when sending over to StyLua
 * @param document The document to retrieve the byte offset in
 * @param position The position to retrieve the byte offset for
 */
function byteOffset(document: vscode.TextDocument, position: vscode.Position): number {
	// Retrieve all the text from the start of the document to the position provided
	const textRange = new vscode.Range(document.positionAt(0), position);
	const text = document.getText(textRange);

	// Retrieve the byte length of the text range in a buffer
	return Buffer.byteLength(text);
}

class StatusInfo implements vscode.Disposable {
	public statusItem: vscode.LanguageStatusItem;
	public styluaInfo: StyluaInfo | undefined = undefined;

	public constructor() {
		this.statusItem = vscode.languages.createLanguageStatusItem("stylua", documentSelector);
		this.statusItem.name = "StyLua";
		this.statusItem.command = {
			command: "stylua.showOutputChannel",
			title: "Show Output",
		};

		this.updateReady();
	}

	public setStyluaInfo(styluaInfo?: StyluaInfo): void {
		this.styluaInfo = styluaInfo;
		this.updateReady();
	}

	public getStyluaText(): string {
		if (this.styluaInfo?.version)
			return this.styluaInfo.resolveMode === ResolveMode.Bundled
				? `StyLua (bundled ${this.styluaInfo.version})`
				: `StyLua (${this.styluaInfo.version})`;

		return "StyLua";
	}

	public updateReady(): void {
		this.statusItem.text = `$(check) ${this.getStyluaText()}`;
		this.statusItem.detail = "Ready";
		this.statusItem.severity = vscode.LanguageStatusSeverity.Information;
	}

	public updateFormatSuccess(): void {
		this.statusItem.text = `$(check) ${this.getStyluaText()}`;
		this.statusItem.detail = "File formatted successfully";
		this.statusItem.severity = vscode.LanguageStatusSeverity.Information;
	}

	public updateFormatFailure(): void {
		this.statusItem.text = `${this.getStyluaText()}`;
		this.statusItem.detail = "Failed to format file";
		this.statusItem.severity = vscode.LanguageStatusSeverity.Error;
	}

	public dispose(): void {
		this.statusItem.dispose();
	}
}

function sortReleases(releaseA: GitHubRelease, releaseB: GitHubRelease): number {
	return semver.rcompare(releaseA.tagName, releaseB.tagName);
}

const REACT_KEYWORDS_SET = new Set([
	"createElement",
	"createBinding",
	"createContext",
	"createFragment",
	"joinBindings",
	"forwardRef",
	"createMutableSource",
	"createRef",
	"useBinding",
	"useCallback",
	"useContext",
	"useDebugValue",
	"useEffect",
	"useImperativeHandle",
	"useLayoutEffect",
	"useMemo",
	"useMutableSource",
	"useReducer",
	"useRef",
	"useState",
	"PureComponent",
	"oneChild",
	"isValidElement",
]);
const baseReactFileRegExp = new RegExp([...REACT_KEYWORDS_SET].join("|"));

function isStringArray(value: unknown): value is ReadonlyArray<string> {
	if (!Array.isArray(value)) return false;
	for (const element of value) if (typeof element !== "string") return false;
	return true;
}

function getReactFileRegExp(): RegExp {
	const reactKeywords = vscode.workspace.getConfiguration("stylua").get<Array<unknown> | null>("reactKeywords");
	return reactKeywords && isStringArray(reactKeywords)
		? new RegExp([...new Set([...REACT_KEYWORDS_SET, ...reactKeywords])].join("|"))
		: baseReactFileRegExp;
}

export async function activate(extensionContext: vscode.ExtensionContext) {
	console.log("stylua activated");

	const outputChannel = vscode.window.createOutputChannel("StyLua", { log: true });
	outputChannel.info("StyLua activated");

	const statusItem = new StatusInfo();
	const github = new GitHub();
	extensionContext.subscriptions.push(github);

	const styluaDownloader = new StyluaDownloader(extensionContext.globalStorageUri, github, outputChannel);

	const cwdForVersionDetection = vscode.workspace.workspaceFolders?.[0].uri.fsPath;

	let styluaBinaryPath = await styluaDownloader.ensureStyluaExists(cwdForVersionDetection);
	await styluaDownloader.ensureStyluaExists(undefined, StyluaType.React);
	statusItem.setStyluaInfo(styluaBinaryPath);

	extensionContext.subscriptions.push(
		vscode.commands.registerCommand("stylua.reinstall", async () => {
			await styluaDownloader.downloadStyluaVisual(getDesiredVersion());
			styluaBinaryPath = await styluaDownloader.ensureStyluaExists(cwdForVersionDetection);
			await styluaDownloader.ensureStyluaExists(undefined, StyluaType.React);
			statusItem.setStyluaInfo(styluaBinaryPath);
		}),

		vscode.commands.registerCommand("stylua.authenticate", async () => await github.authenticate()),
		vscode.commands.registerCommand("stylua.showOutputChannel", async () => outputChannel.show()),
		vscode.commands.registerCommand("stylua.selectVersion", async () => {
			const allReleases = await github.getAllReleases();
			const versions = allReleases.sort(sortReleases);

			if (versions.length === 0) return;
			const latestVersion = versions[0];

			const selectedVersion = await vscode.window.showQuickPick(
				versions
					.sort(sortReleases)
					.map((githubRelease) =>
						githubRelease.tagName === latestVersion.tagName
							? { label: `${githubRelease.tagName} (latest)` }
							: { label: githubRelease.tagName },
					),
				{
					placeHolder: "Select the version of StyLua to install",
				},
			);

			if (selectedVersion) {
				const updateConfigurationValue = selectedVersion.label.includes("latest")
					? "latest"
					: selectedVersion.label;

				await styluaDownloader.downloadStyluaVisual(updateConfigurationValue);
				vscode.workspace
					.getConfiguration("stylua")
					.update("targetReleaseVersion", updateConfigurationValue, vscode.ConfigurationTarget.Workspace);
			}
		}),

		vscode.commands.registerCommand("stylua.installUpdate", async (githubRelease: GitHubRelease) => {
			const result = await vscode.window.showInformationMessage(
				`Are you sure you want to update StyLua to ${githubRelease.tagName}?`,
				{ modal: true },
				"Update",
				"Release Notes",
				"Do not show again",
			);
			const styluaConfiguration = vscode.workspace.getConfiguration("stylua");

			switch (result) {
				case "Update": {
					await styluaDownloader.downloadStyluaVisual(githubRelease.tagName);
					styluaConfiguration.update("targetReleaseVersion", "latest");
					break;
				}

				case "Release Notes": {
					vscode.env.openExternal(vscode.Uri.parse(githubRelease.htmlUrl));
					break;
				}

				case "Do not show again": {
					styluaConfiguration.update("disableVersionCheck", true);
					break;
				}
			}
		}),

		vscode.workspace.onDidChangeConfiguration(async (change) => {
			if (change.affectsConfiguration("stylua")) {
				styluaBinaryPath = await styluaDownloader.ensureStyluaExists(cwdForVersionDetection);
				statusItem.setStyluaInfo(styluaBinaryPath);
			}
		}),
	);

	const disposable = vscode.languages.registerDocumentRangeFormattingEditProvider(documentSelector, {
		async provideDocumentRangeFormattingEdits(document: vscode.TextDocument, range: vscode.Range) {
			if (!styluaBinaryPath) {
				vscode.window.showErrorMessage("StyLua not found. Could not format file", "Install").then((option) => {
					if (option === "Install") vscode.commands.executeCommand("stylua.reinstall");
				});
				return [];
			}

			const currentWorkspace = vscode.workspace.getWorkspaceFolder(document.uri);
			const cwd = currentWorkspace?.uri?.fsPath;

			const text = document.getText();
			try {
				const reactFileRegExp = getReactFileRegExp();

				const formattedText = await formatCode(
					outputChannel,
					reactFileRegExp.test(text) ? styluaBinaryPath.paths[1] : styluaBinaryPath.paths[0],
					text,
					document.uri.scheme === "file" ? document.uri.fsPath : undefined,
					cwd,
					byteOffset(document, range.start),
					byteOffset(document, range.end),
				);

				// Replace the whole document with our new formatted version
				const lastLineNumber = document.lineCount - 1;
				const fullDocumentRange = new vscode.Range(
					0,
					0,
					lastLineNumber,
					document.lineAt(lastLineNumber).text.length,
				);

				const format = vscode.TextEdit.replace(fullDocumentRange, formattedText);
				statusItem.updateFormatSuccess();
				return [format];
			} catch (error) {
				statusItem.updateFormatFailure();
				outputChannel.error(error as string);
				return [];
			}
		},
	});

	extensionContext.subscriptions.push(
		disposable,
		statusItem,
		vscode.window.onDidChangeActiveTextEditor(() => statusItem.updateReady()),
	);
}

// this method is called when your extension is deactivated
export function deactivate() {}
