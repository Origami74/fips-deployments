# fips-deployments

Deployment repository for public FIPS nodes. Contains the Docker image definition and GitHub Actions workflow for building and deploying [fips](https://github.com/fips-network/fips) to remote servers.

## Repository structure

```
fips-deployments/
├── .github/
│   └── workflows/
│       └── deploy.yml        # Build + deploy workflow
├── docker/
│   ├── Dockerfile            # Minimal Debian image with fips binaries
│   └── entrypoint.sh         # Container entrypoint
├── .act.secrets              # Local secrets template (gitignored)
├── .gitignore
└── README.md
```

## How it works

Two variants of fips are built and deployed **side by side on the same hosts**, one per source branch:

| Variant | fips branch | Container | UDP | TCP | TUN | Aux services |
|---|---|---|---|---|---|---|
| `master` | `master` | `fips-node` | 2121 | 443 | `fips0` | dnsmasq + daemon DNS + iperf3 + http.server |
| `next` | `next` | `fips-node-next` | 2122 | 444 | `fips1` | none (fips only, daemon DNS off) |

Both containers run with `--network host`, so the `next` instance offsets every public port by **+1** and skips the auxiliary services that would otherwise collide on the shared host network namespace (`:53`, daemon DNS `:5354`, iperf3 `:5201`, http.server `:8000`). The two instances **reuse the same per-host `nsec`**; `next` defaults its Nostr discovery namespace to `fips-overlay-v1-next` (vs `master`'s `fips-overlay-v1`), so the two protocol versions stay on separate overlays despite sharing an identity.

1. **Resolve & plan** — resolves both `master` and `next` to commit SHAs and consults a per-variant marker cache. Each branch deploys independently: a scheduled run rebuilds a variant only when *that* branch's SHA changed (master changing does not redeploy next, and vice versa); `push`/`workflow_dispatch` force both.
2. **Build** — for each active variant, checks out `fips` at the resolved SHA, builds with `cargo build --release` (the CI runner is Linux x86_64), and packages it into a Docker image tagged `fips-node:<variant>`.
3. **Deploy** — for each (host × active variant) pair, generates a config (`max_peers: 512`, the node's `nsec` from secrets, Nostr advertising on, and the variant's ports/TUN/DNS settings), copies the image and config over SSH, and starts the container.

## Triggering a deployment

### GitHub Actions (production)

Go to **Actions → Deploy FIPS Nodes → Run workflow**, then select:
- **environment** — `production` or `staging`

A manual run always builds and deploys **both** variants (`master` and `next`) from the current tip of their respective fips branches, bypassing the marker cache.

### Local testing with [act](https://github.com/nektos/act)

1. Copy and fill in the secrets template:
   ```bash
   cp .act.secrets.example .act.secrets   # or edit .act.secrets directly
   ```

2. Run the workflow locally:
   ```bash
   act workflow_dispatch \
     -W .github/workflows/deploy.yml \
     --secret-file .act.secrets \
     -i environment=production
   ```

## Adding a new server

Hosts are deployed to dynamically — every active variant (`master` and `next`) is deployed to every host in the list, so you only add the host once.

1. **Add the host id** to the `HOSTS=( … )` array in the "Plan build & deploy matrices" step of [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml):
   ```bash
   HOSTS=(FIPS_PROD_US_1 FIPS_PROD_US_2 FIPS_PROD_EU_1)
   ```

2. **Add a `case` branch** in the "Resolve target" step (maps the host id to its `host`/`user`/`nsec`), and expose its vars/secret in that step's `env:` block (`HOST_3` / `USER_3` / `NSEC_3`).

3. **Add secrets/vars** to the GitHub environment (Settings → Environments → production):
   - `DEPLOY_HOST_FIPS_PROD_EU_1` (var)
   - `DEPLOY_USER_FIPS_PROD_EU_1` (var)
   - `NSEC_FIPS_PROD_EU_1` (secret) — shared by both the `master` and `next` containers on the host

4. **Add entries** to your local `.act.secrets` for testing.

To seed bootstrap peers for a specific host/variant, add a branch to the "Resolve peers" step keyed on `<host>/<variant>` (e.g. `FIPS_PROD_EU_1/next`).

## Peer configuration

Peers are specified per server in the matrix as a comma-separated list of `npub|ip|port` entries (UDP transport is assumed):

```yaml
peers: "npub1abc...|1.2.3.4|2121,npub1def...|5.6.7.8|2121"
```

This generates the following section in `fips.yaml`:

```yaml
peers:
  - npub: "npub1abc..."
    addresses:
      - transport: udp
        addr: "1.2.3.4:2121"
  - npub: "npub1def..."
    addresses:
      - transport: udp
        addr: "5.6.7.8:2121"
```

## Required secrets

| Secret | Scope | Description |
|---|---|---|
| `SSH_PRIVATE_KEY` | shared | SSH private key for all servers |
| `DEPLOY_USER_FIPS_PROD_US_1` | per-server | SSH login user |
| `DEPLOY_HOST_FIPS_PROD_US_1` | per-server | Hostname or IP |
| `NSEC_FIPS_PROD_US_1` | per-server | 64-char hex node private key (shared by the `master` and `next` containers) |
| `DEPLOY_USER_FIPS_PROD_US_2` | per-server | SSH login user |
| `DEPLOY_HOST_FIPS_PROD_US_2` | per-server | Hostname or IP |
| `NSEC_FIPS_PROD_US_2` | per-server | 64-char hex node private key (shared by the `master` and `next` containers) |

Generate a node keypair with:
```bash
python3 deploy/gen-keys.py <mesh-name> <node-name>
```
(from the [fips](https://github.com/fips-network/fips) repository)