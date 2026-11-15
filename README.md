# lab-deploy

How [rafilab.com](https://rafilab.com) runs: one small VPS, Docker Compose, and a Cloudflare Tunnel. No port is
open to the internet except SSH.

```
visitor ── HTTPS ──► Cloudflare ── tunnel ──► cloudflared ──► edge (Caddy)
                                                              ├─ /                 lab-web       the Lab (portfolio)
                                                              ├─ /tiketa/          tiketa-web    cinema booking site
                                                              ├─ /tiketa/api/      tiketa-api    booking API, MCP at /tiketa/api/mcp/
                                                              └─ /tiketa/agent/    tiketa-agent  LangGraph chat agent
                                              postgres (tiketa, tiketa_agent)   redis
```

| Repository | What runs from it |
|---|---|
| [ai-engineering-lab](https://github.com/rafi-seniang/ai-engineering-lab) | `lab-web` |
| [tiketa-app](https://github.com/rafi-seniang/tiketa-app) | `tiketa-api`, `tiketa-web` |
| [tiketa-booking-agent](https://github.com/rafi-seniang/tiketa-booking-agent) | `tiketa-agent` |

## Choices

| Choice | Why |
|---|---|
| One host name with paths | The sites share an origin, so the guest cookie and the browser's requests need no cross-site rules |
| Cloudflare Tunnel, no published ports | TLS and the certificate are Cloudflare's. The host accepts no web traffic directly, and Docker's published ports would go around the firewall |
| Images built on the host from pinned commits | No registry and no registry credentials. `refs.env` says exactly which commit of each application runs. A registry and a deploy button can come later |
| Secrets only in `.env` on the host | This repository is public and holds none |
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
    ./deploy.sh
    sudo bash server/install-cron.sh

In the Cloudflare dashboard the tunnel needs one public hostname: `rafilab.com` to `http://edge:80`.

## Deploy a new version

Change a commit in `refs.env`, push, then on the host:

    cd /srv/lab/deploy && git pull && ./deploy.sh

`deploy.sh` stops at the first failed step and ends with requests through the edge to every service.

## Not here yet

- Backups stay on the host. A copy elsewhere is not set up.
- No uptime check from outside.
- The other Lab services (Gatekeeper, Lens, Dispatch, Ledger) are not deployed: they have no guest sessions or
  spending caps yet, and two of them need a GPU.
- Deploys are run by hand over SSH. A GitHub Actions button is planned.
