import fetch, { Headers } from "node-fetch";
import {
	type AuthenticationSession,
	type AuthenticationSessionsChangeEvent,
	type Disposable,
	authentication,
	window,
} from "vscode";

const RELEASES_URL = "https://api.github.com/repos/JohnnyMorganz/StyLua/releases";
const RELEASES_URL_LATEST = `${RELEASES_URL}/latest`;
const SCOPES = new Array<string>();

export interface GitHubRelease {
	readonly assets: ReadonlyArray<{
		readonly downloadUrl: string;
		readonly name: string;
	}>;
	readonly htmlUrl: string;
	readonly tagName: string;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function fetchJson(url: string, token: string | undefined = undefined): Promise<any> {
	const headers = new Headers();
	if (token) headers.set("Authorization", `token ${token}`);

	const response = await fetch(url, { headers });
	return response.json();
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function releaseFromJson(json: any): GitHubRelease {
	if (typeof json !== "object")
		return {
			assets: [],
			htmlUrl: "",
			tagName: "",
		};

	return {
		assets: Array.isArray(json.assets)
			? // eslint-disable-next-line @typescript-eslint/no-explicit-any
				json.assets.map((asset: any) => ({
					downloadUrl: typeof asset.browser_download_url === "string" ? asset.browser_download_url : "",
					name: typeof asset.name === "string" ? asset.name : "",
				}))
			: [],
		htmlUrl: typeof json.html_url === "string" ? json.html_url : "",
		tagName: typeof json.tag_name === "string" ? json.tag_name : "",
	};
}

class Credential {
	public constructor() {
		this.set();
	}

	public get authenticated(): boolean {
		return !!this._session;
	}

	public get token(): string | undefined {
		return this._token;
	}

	public get session(): string | undefined {
		return this._session;
	}

	public set(session?: AuthenticationSession | undefined) {
		if (session) {
			this._session = session.id;
			this._token = session.accessToken;
		} else {
			this._session = undefined;
			this._token = undefined;
		}
	}

	private _session?: string = undefined;
	private _token?: string = undefined;
}

export class GitHub implements Disposable {
	public constructor() {
		this.disposables.push(
			authentication.onDidChangeSessions((event: AuthenticationSessionsChangeEvent) => {
				if (event.provider.id === "github") {
					this.credential.set();
					this.authenticate(false);
				}
			}),
		);
	}

	public dispose(): void {
		for (const disposable of this.disposables) disposable.dispose();
	}

	public get authenticated(): boolean {
		return this.credential.authenticated;
	}

	public async authenticate(create = true): Promise<boolean> {
		try {
			const token = await authentication.getSession("github", SCOPES, { createIfNone: create });
			this.credential.set(token);
		} catch (error) {
			if (error instanceof Error && error.message === "User did not consent to login.") {
				this.credential.set();
				return false;
			}
			window.showErrorMessage(`Failed to authenticate with GitHub: ${error}`);
		}

		return this.credential.authenticated;
	}

	public async getAllReleases(): Promise<Array<GitHubRelease>> {
		const json = await fetchJson(RELEASES_URL, this.credential.token);
		return Array.isArray(json) ? json.map((element) => releaseFromJson(element)) : [];
	}

	public async getRelease(version: string): Promise<GitHubRelease> {
		if (version === "latest") {
			const json = await fetchJson(RELEASES_URL_LATEST, this.credential.token);
			return releaseFromJson(json);
		}

		version = version.startsWith("v") ? version : `v${version}`;
		const releases = await this.getAllReleases();
		for (const release of releases) if (release.tagName.startsWith(version)) return release;

		const exception = new Error(`No release version matches ${version}.`);
		exception.name = "NoReleaseFoundError";
		Error.captureStackTrace(exception, this.getRelease);
		throw exception;
	}

	private readonly disposables = new Array<Disposable>();
	private readonly credential = new Credential();
}
