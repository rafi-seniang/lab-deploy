# lab-deploy

How [rafilab.com](https://rafilab.com) runs: one small VPS, Docker Compose, and a Cloudflare Tunnel. No port is
open to the internet except SSH.

```
visitor ── HTTPS ──► Cloudflare ── tunnel ──► cloudflared ──► edge (Caddy)
                                                              ├─ /                 lab-web         the Lab (portfolio, /dispatch, /gatekeeper, /lens)
                                                              ├─ /dispatch/api/    dispatch-api    Dispatch (Jev default + Gemini Decision 1)
                                                              ├─ /gatekeeper/api/  gatekeeper-api  Gatekeeper (Jev guard, one upstream model)
                                                              ├─ /lens/api/        lens-api        Lens (Gemini Embedding 2 + Typesense)
                                                              ├─ /tiketa/          tiketa-web      cinema booking site
                                                              ├─ /tiketa/api/      tiketa-api      booking API, MCP at /tiketa/api/mcp/
                                                              └─ /tiketa/agent/    tiketa-agent    LangGraph chat agent
                                              postgres (tiketa, tiketa_agent)   redis (DB 0..4)   lens-typesense (27.1)
```

| Repository | What runs from it |
|---|---|
| [ai-engineering-lab](https://github.com/rafi-seniang/ai-engineering-lab) | `lab-web` |
| [dispatch-system1-router](https://github.com/rafi-seniang/dispatch-system1-router) | `dispatch-api` |
| [gatekeeper-llm-gateway](https://github.com/rafi-seniang/gatekeeper-llm-gateway) | `gatekeeper-api` |
| [lens-multimodal-search](https://github.com/rafi-seniang/lens-multimodal-search) | `lens-api` |
| [tiketa-app](https://github.com/rafi-seniang/tiketa-app) | `tiketa-api`, `tiketa-web` |
| [tiketa-booking-agent](https://github.com/rafi-seniang/tiketa-booking-agent) | `tiketa-agent` |

## Choices

| Choice | Why |
|---|---|
| One host name with paths | The sites share an origin, so the guest cookie and the browser's requests need no cross-site rules |
| Cloudflare Tunnel, no published ports | TLS and the certificate are Cloudflare's. The host accepts no web traffic directly, and Docker's published ports would go around the firewall |
| Images built on the host from pinned commits | No registry and no registry credentials. `refs.env` says exactly which commit of each application runs. A registry and a deploy button can come later |
| Secrets only in `.env` on the host | This repository is public and holds none. `GATEKEEPER_TRUSTED_KEY` there is the key the Tiketa agent sends to Gatekeeper |
| Tiketa's chat goes through Gatekeeper | The agent asks `gatekeeper-api` over the internal network to check each message, with the scope `tiketa` kept in Gatekeeper (`NAMED_SCOPES` in `compose.yml`) |
| Cloudflare lets MCP clients through | A Configuration Rule turns Browser Integrity Check off for `/tiketa/api/mcp`. Without it Python clients get error 1010 |
| The chat agent's model key belongs to this host alone | It can be revoked without touching anything else, and its prepaid balance is the spending cap. The agent also stops at 1,000,000 model tokens a day |

## Files

    compose.yml            every service
    Caddyfile              the paths
    refs.env               the commit of each application
    deploy.sh              fetch, build, migrate, start, check
    backup.sh              nightly dump of every database, seven kept, on the host
    cron/lab               the week's showtimes every Monday 00:05 WIB, and the backup
    server/setup.sh        first setup of the host: updates, SSH keys only, firewall, swap, Docker
    server/install-cron.sh installs cron/lab
    initdb/                creates the second database on first start

## First setup

    sudo bash server/setup.sh                 # once, on a fresh Ubuntu 24.04
    git clone https://github.com/rafi-seniang/lab-deploy.git /srv/lab/deploy && cd /srv/lab/deploy
    cp .env.example .env && chmod 600 .env    # fill it in
    # copy the pre-indexed Lens archive (index.json, vectors.npy, *.jpg, uploads/) to data/lens/
    mkdir -p data/lens && chown -R 10001:10001 data/lens
    ./deploy.sh
    sudo bash server/install-cron.sh

In the Cloudflare dashboard the tunnel needs one public hostname: `rafilab.com` to `http://edge:80`.

## Deploy a new version

Change a commit in `refs.env`, push, then on the host:

    cd /srv/lab/deploy && git pull && ./deploy.sh

`deploy.sh` stops at the first failed step and ends with requests through the edge to every service.

## Not here yet

- Backups stay on the host (`postgres` dumps via `backup.sh`), while `data/lens/uploads/` lives only in `./data/lens`.
- No uptime check from outside.
- Ledger and Footfall are marked In Maintenance on the Lab: Ledger is being redesigned around Jev decision gates, and Footfall needs video stream processing.
- Deploys are run by hand over SSH. A GitHub Actions button is planned.
