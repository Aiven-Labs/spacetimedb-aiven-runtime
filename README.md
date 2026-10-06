# SpacetimeDB on Aiven's application runtime

A template for running a [SpacetimeDB](https://spacetimedb.com) server, with your module
already published, as a single container on an Aiven application service.

You put a TypeScript module in `module/`, point an Aiven application service at this repo,
and get a `wss://` endpoint your clients can connect to. It was extracted from a real
deployment (a server-authoritative browser game) and carries the lessons from it.

```
your repo ──build──► image (SpacetimeDB + your module)
                          │  on start: spacetime start → publish module → optional setup calls
                          ▼
              https://<uuid>-3000.<region>.aiven.app   (clients connect with wss://)
```

## Quick start

```bash
# 1. Try it locally
docker build -t my-spacetimedb .
docker run --rm -p 3000:3000 -e DB_NAME=demo my-spacetimedb
scripts/check.sh http://127.0.0.1:3000 demo          # ping + database published

# 2. Replace module/ with your own (npm install && spacetime build -p module to check it compiles)
```

### Deploy on Aiven

An Aiven application service builds from a git repository, so push this to GitHub first.

**Console:** *Services → Create service → Application*, choose the repo and branch, then set
the container port to `3000` (it must match `PORT`). Add the environment variables below.

**With the Aiven MCP / API:** create an application from the repo with `containerfile_path:
Dockerfile`, `port: 3000`, and `environment_variables` as below.

When the build finishes, the service's public URL is under its connection info. Clients use
the same host with `wss://`:

```ts
DbConnection.builder().withUri('wss://<uuid>-3000.<region>.aiven.app').withDatabaseName('demo')…
```

Check it: `scripts/check.sh https://<uuid>-3000.<region>.aiven.app demo`

## Configuration

| Variable | Default | What it does |
|---|---|---|
| `DB_NAME` | `app` | The database name clients connect to |
| `PORT` | `3000` | Listen port. Must equal the port configured on the Aiven service |
| `POST_PUBLISH_CALLS` | – | Reducers to call once published, one per line (`reducer arg1 arg2`). Runs as the owner. Use this to hand the module its configuration and secrets |
| `PUBLISH_DELETE_DATA` | `0` | `1` wipes the database on every start. Handy while the schema is changing |
| `SPACETIME_VERSION` (build arg) | `v2.10.2` | Image tag. Server and CLI come from the same tag, so they always match |

Rust or C# modules: build the `.wasm` outside (`spacetime build`) and place it at
`module/module.wasm`. The image uses it instead of compiling TypeScript.

## Things that will bite you

**1. Storage is ephemeral unless you attach a volume.** The application runtime's
create call has no volume option. Without a mounted `/data`, restarting or redeploying the
service gives you a fresh, empty database. Treat SpacetimeDB as *live state* (lobbies,
matches, presence) and keep anything that must survive somewhere durable. The
reference deployment does this by having the module POST finished results to a service
backed by Postgres. Pattern: write rows to a private scheduled "outbox" table and deliver
them from a scheduled procedure that retries with backoff.

**2. Module HTTP calls cannot reach private addresses.** `ctx.http.fetch` refuses
private and special-purpose ranges (`refusing to connect to private or special-purpose
addresses`). To call another Aiven service it must be the **public** URL, not a VPC or
internal host. You can't test such calls against another container on your local Docker
network for the same reason.

**3. Updating environment variables replaces the whole list.** Via the API, sending
`environment_variables` replaces everything. Secrets are redacted on read, so you
can't send them back. Add new variables in the Console, or send the complete list yourself.
Changing source settings alone (branch, repo) does not touch them.

**4. Private repos need the VCS integration.** If the first build fails with
`authentication required: Repository not found`, the service was created without its VCS
integration. Attach `vcs_integration_id` and `remote_repository_id` (copy them from an
existing service in the same project) and redeploy.

**5. Hostnames are UUID-based.** `https://<uuid>-3000.<region>.aiven.app` changes if the
service is recreated, so keep it in one config place that clients read.

**6. Reducer names are snake_case outside your code.** `export const setGreeting` is
called as `set_greeting` from the CLI, HTTP API and `POST_PUBLISH_CALLS`.

**7. Secrets in the module.** Don't bake them into `module/`. Add an owner-only reducer
(the example's `setGreeting` shows how: `init` records the publisher, the reducer checks
`ctx.sender`) and pass values with `POST_PUBLISH_CALLS`. Public table rows are readable
by any client that can subscribe; leave `public: true` off anything private.

**8. Public by default.** The service is reachable from the internet. Anything a client
shouldn't do must be refused inside your reducers: clients can only call reducers, and
what a reducer allows is your security boundary. For scheduled reducers, check
`ctx.sender.equals(ctx.databaseIdentity)` so only the scheduler can run them.

## Reading private data

Private tables are visible to the database owner, which here is the identity the
container's CLI generated and stored under `/data/home`. To inspect them, run the CLI
inside the container (there is no remote way in by design):

```bash
docker exec <container> spacetime sql <DB_NAME> "SELECT * FROM settings" --server http://127.0.0.1:3000
```

On Aiven, use the service's shell/exec if your plan offers one, or expose an owner-checked
reducer or an export path in your module.

## Layout

```
Dockerfile        build module → runtime image (server + module)
entrypoint.sh     start, publish, post-publish calls
module/           your TypeScript module (an example is included)
scripts/check.sh  post-deploy health check
```

## Cost

One application service on the default plan (0.5 vCPU, 1 GB) is cheap to run for demos and
small games. Size up with player count; a scheduled reducer ticking at 20 Hz per active
game was fine for a handful of concurrent players on that plan.
