# coworok-apim-plugin

Microsoft 365 Copilot Cowork plugin and Azure API Management integration for the PSA OEN prototype.

## What's included

- **Cowork plugin** (`plugin/appPackage/`): app manifest, domain skill and reference material. The checked-in package is version **2.0.7**, using manifest **1.29** and an APIM-hosted remote MCP connector.
- **APIM infrastructure and policies** (`infra/`): Bicep templates, selected REST operations exposed as MCP tools, Entra caller validation and per-user OEN token handling.
- **Account-linking app** (`linking-app/`): Entra-authenticated linking page that validates a user's OEN credentials and stores them in Key Vault under their Entra object ID.
- **Publication pipeline** (`cicd/`): live MCP checks and independent APIM/plugin publication paths.
- **Historical sandbox probe** (`cowork-probe/`): diagnostic code, not the supported runtime integration.

## Integration pattern

Cowork calls the APIM-hosted MCP interface. APIM validates the caller's Entra identity, retrieves that user's linked OEN credentials through managed identity and calls OEN. The MCP tools are `list_voyages`, `get_voyage` and `get_voyage_nodes`.

The Cowork skill uses those tools for structured data questions and browser interaction for view changes, exports and UI-only operations. This is **account linking**, not native OEN single sign-on. Application passwords and backend tokens belong in the protected server-side runtime, not the plugin or prompts.

## Build the plugin package locally

From the repository root in Linux/WSL, with Python 3, Bash, `zip` and `unzip` installed:

```bash
bash plugin/zip-plugin.sh
```

The script validates the manifest, icons and skill references, then writes `plugin/dist/psa-oen-cowork-plugin-<version>.zip`. Build output is gitignored. Building the ZIP does not deploy Azure resources or publish the plugin.

## Deployment and publication notes

This is an engagement prototype, **not a turnkey deployment template**. Review the checked-in scripts and configuration before running them:

- Existing resource names, subscription IDs, absolute checkout paths and tenant-specific connector/OAuth references target the original environment. Adapt these for another environment; a clone alone does not make them portable.
- The Azure scripts can create resources, update Entra registrations or reset application credentials. Do not run them just to inspect or package the plugin.
- The scripts expect Azure CLI authentication and local runtime state under `~/.psa-oen/`. Do not commit that state or credentials.
- The pipeline uses Python `requests`, Azure CLI and Agents Toolkit (`atk`). Its Node path is specific to the original development machine.
- `cicd/pipeline.sh` checks the live MCP server and can publish through `atk install --scope Shared`. `--apim` also redeploys the APIM definition. Use only with the intended environment and approvals.
- Configure the OAuth connection for your own tenant; the manifest's reference is not a portable credential.

## Security and scope

This private repository contains the source for the internet-reachable OEN UAT integration. It does **not** provide cloud access to an internal/OT-only application and does not contain the separate browser-extension bridge implementation.

Local recon captures, session material, environment files, tokens, infrastructure backups and generated packages are excluded by `.gitignore`. Never add real user passwords or tokens to source control. Production adoption requires application-owner approval, security review, least-privilege access, credential lifecycle management and reviewed data handling.
