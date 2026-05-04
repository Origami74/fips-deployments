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

1. **Build** — checks out the `fips` source repo at the requested ref, builds the binary with `cargo build --release` (the CI runner is Linux x86_64), and packages it into a Docker image using `docker/Dockerfile`.
2. **Deploy** — for each server in the matrix, generates a `fips.yaml` config (with the node's `nsec` from secrets and any configured peers), copies the image and config to the server over SSH, and starts the container.

The container exposes:
- `UDP 2121` — FIPS mesh transport
- `TCP 443` — FIPS public TCP transport

## Triggering a deployment

### GitHub Actions (production)

Go to **Actions → Deploy FIPS Nodes → Run workflow**, then select:
- **fips_ref** — the tag, branch, or commit SHA to build (e.g. `v0.3.0` or `main`)
- **environment** — `production` or `staging`

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
     -i fips_ref=main \
     -i environment=production
   ```

## Adding a new server

1. **Add a matrix entry** in [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) under `jobs.deploy.strategy.matrix.include`:
   ```yaml
   - name: FIPS_PROD_EU_1
     host_secret: DEPLOY_HOST_FIPS_PROD_EU_1
     user_secret: DEPLOY_USER_FIPS_PROD_EU_1
     nsec_secret: NSEC_FIPS_PROD_EU_1
     peers: ""   # optional: "npub1...|1.2.3.4|2121,npub1...|5.6.7.8|2121"
   ```

2. **Add a `case` branch** in each of the three "Resolve" steps (`Resolve host`, `Resolve user`, `Resolve nsec`) in the same workflow file.

3. **Add secrets** to the GitHub repository (Settings → Secrets → Actions):
   - `DEPLOY_HOST_FIPS_PROD_EU_1`
   - `DEPLOY_USER_FIPS_PROD_EU_1`
   - `NSEC_FIPS_PROD_EU_1`

4. **Add entries** to your local `.act.secrets` for testing.

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
| `NSEC_FIPS_PROD_US_1` | per-server | 64-char hex node private key |
| `DEPLOY_USER_FIPS_PROD_US_2` | per-server | SSH login user |
| `DEPLOY_HOST_FIPS_PROD_US_2` | per-server | Hostname or IP |
| `NSEC_FIPS_PROD_US_2` | per-server | 64-char hex node private key |

Generate a node keypair with:
```bash
python3 deploy/gen-keys.py <mesh-name> <node-name>
```
(from the [fips](https://github.com/fips-network/fips) repository)