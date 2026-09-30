# Sawda Mim , uniqname: sawdam, UMID: 95969742
# Planner: a readiness-aware, graph-based planner in Jac

**EECS 449, Assignment 1.** A personal planner that knows *what blocks what* and *how much you can actually do today*. It has four parts built in Jac that share one backend:

| Part | Where | What it's for |
|---|---|---|
| **Server** | `main.jac`, `services/` | All planning logic, as graph walkers served over REST, plus persistent storage |
| **Web** | `routes/` (`/`, `/today`, `/projects`) | Plan the week: drag tasks between days, edit dependencies, track goals |
| **Mobile** | `routes/Mobile*` (`/m`), Capacitor build | On the go: check off today, quick add, see what's next and your readiness |
| **CLI** | `cli/plan.jac`, `./plan` | Fast capture and a daily plan without leaving the terminal |

| Web: week board | Web: today | Mobile: today |
|---|---|---|
| ![Week board](docs/web-week.png) | ![Today](docs/web-today.png) | ![Mobile](docs/mobile-today.png) |

## What makes it stand out

- **It plans your day for you, sized to how you actually feel.** `PlanDay` reads your readiness score (Oura, or mock data) and sets the day's capacity: about 6h on a strong day, 5h on a normal day, 3h on a low one. It lists what's overdue and what's due, fills the rest with the best unblocked tasks, and pushes deep-focus work later when you're tired. If you've overbooked, it says so and names the task to move ("Over by 40 min, consider moving *Build the web week board* to tomorrow").
- **Tasks know what they're waiting on.** "Record the demo video" can't start until "Build the web board" and "Polish mobile screens" are done. Blocked tasks are marked everywhere, *Next up* only shows what you can start right now, and a graph walk refuses links that would create a loop.
- **The data model is a real graph, not a table.** Tasks → Projects → Goals are typed edges, so a goal's progress rolls up two hops. The logic is written as Jac walkers that traverse that graph.
- **All four parts are one app.** Every client calls the same walkers. Add a task in the terminal, it's on the web board and your phone right away. Check it off on your phone, and `./plan today` shows it done. There's no sign-in: everything shares one plan.
- **Each client is built for how you'd use it.** Web is for planning (a drag-and-drop week, a full editor, goals). Mobile is for doing (big tap targets, one-tap quick add, bottom tabs; phones get it automatically, and it builds as a native iOS/Android app). The CLI is for speed (`./plan add Groceries -o today -e low`, `./plan done 2`).
- **Real-life inputs.** Canvas assignments become tasks, with the course as the project. Oura sleep and readiness drive the plan. Both work with realistic mock data out of the box, and syncing twice never creates duplicates.
- **Reliable.** Data persists across restarts. There are 7 walker tests (`jac test`), plus browser tests of the whole web + mobile + CLI flow during development. Clear error messages come back from the server, and there's a one-command `./start.sh`.

## 2-minute tour (for graders)

```bash
./start.sh                  # terminal 1: setup (first time) + server. Wait for "Server ready".
./plan demo                 # terminal 2: loads a realistic week (you can also click "Load demo week" on the web)
```

1. **Terminal:** `./plan today`. You'll see today's plan with readiness, overdue items and the load vs. capacity, plus the *move this* hint if the day is overbooked. Then run `./plan next` (only unblocked tasks) and `./plan week`.
2. **Web, http://localhost:8000:** the **Week** board. Drag a card to another day. Click *Record the demo video* to see the two tasks it waits on. Tick *Build the web week board* done, and the video task's blocker list shrinks.
3. **Today** tab: the readiness card and load meter. If there are suggestions, *Add all to today* schedules them.
4. **Projects & goals:** two goals with progress rolling up from their projects' tasks.
5. **Phone:** open `http://<your-laptop-ip>:8000` on the same Wi-Fi (the address is printed by `./start.sh`), or click *Mobile view* on the web. Tick a task, add one with **+**, then run `./plan today` in the terminal to see both changes.

`./plan demo` only replaces its own demo tasks, so it's safe to re-run for a fresh week.

## The idea

Your plan is a **graph**, not a flat list:

```
root ──► Task ──PartOf──► Project ──Supports──► Goal
           │
           └──DependsOn──► Task      (blocked until that task is done)

root ──► HealthSnapshot              (one per day: Oura readiness/sleep, or mock data)
```

Walkers traverse that graph to answer planning questions:

- **`NextActions`**: which tasks can I start right now? These are open tasks with no unfinished `DependsOn` targets, ranked.
- **`PlanDay`**: builds today's plan. Overdue tasks come first, then tasks scheduled or due today. It then fills the rest of the day's capacity with suggestions. Capacity depends on your **readiness score**: about 6h on a strong day, 5h on a normal day and 3h on a low day. On low days, high-energy tasks get pushed later.
- **`ReachesTask`**: a depth-first walk along `DependsOn` edges. `LinkDependency` uses it to reject links that would create a cycle.
- **Progress rollups**: a goal's progress is counted two hops away (Goal ← Project ← Task).

There is no login: every endpoint is a public walker (`walker:pub`), so all clients read and write one shared plan on the server. Everything persists across server restarts (in `.jac/data/`).

| Web: task editor with "waits on" | Web: projects & goals | Mobile: upcoming |
|---|---|---|
| ![Editor](docs/web-editor.png) | ![Projects](docs/web-projects.png) | ![Upcoming](docs/mobile-upcoming.png) |

## Run it

You need **Python 3.12+** and **Bun or Node.js** (to build the web app). On a Mac: `brew install python@3.12 node`.

**1. Start everything with one command** (keep this terminal open while you use the app):

```bash
./start.sh
```

The first run creates a `.venv`, installs Jac (`pip install jaseci`) and the web app's packages, which takes a few minutes. After that it starts in seconds. Wait until it prints **Server ready**, then open the link it shows.

<details><summary>Doing it by hand instead</summary>

```bash
python3.12 -m venv .venv && source .venv/bin/activate
pip install jaseci              # jaclang + jac-scale (server) + jac-client (web/mobile)
jac install                     # web client packages (first time only)
jac start main.jac              # web app + API on http://localhost:8000 (API docs at /docs)
```
</details>

### If http://localhost:8000 doesn't load

- **The server has to be running on your computer.** The link only works while `./start.sh` (or `jac start main.jac`) is running in a terminal. Closing that terminal stops the app.
- **Wait for "Server ready".** The first start builds the web app, and the page won't load until that's done.
- **Port already in use?** `./start.sh` tells you. Run `PORT=8080 ./start.sh` and open http://localhost:8080 instead. For the CLI, also run `./plan server http://localhost:8080`.
- **`./plan status`** shows whether the CLI can reach the server.

**2. Use the web app:** open http://localhost:8000. There's no sign-in, so you go straight to your week.

- **Week** (`/`): a Mon–Sun board plus a *Someday* column. Drag tasks between days, click a card to edit it (dates, priority, energy, project, tags, and what it *waits on*), and tick the circle to finish it.
- **Today** (`/today`): overdue tasks, today's tasks, and suggestions sized to your readiness. *Add all to today* schedules the suggestions.
- **Projects & goals** (`/projects`): create goals, link projects to them, and watch progress roll up.

**3. Use the mobile app:** on a phone, open `http://<your-laptop-ip>:8000` (same Wi-Fi) and you'll land on the mobile UI at `/m`. It has four tabs: **Today** (tap to finish, *Plan my day*), **Upcoming** (next 7 days), **Add** (quick add with one-tap chips), and **Me** (7-day readiness, sync, desktop view). Phones get this view automatically; on a laptop use *Mobile view* in the top bar.

To build it as a **native app** (Capacitor, same code):

```bash
# 1. In jac.toml, set [plugins.client.api] base_url to an address your phone can reach,
#    e.g. "http://192.168.1.25:8000" (your laptop's LAN IP) or a deployed server URL.
jac setup mobile --platform ios          # or android (one time; needs Xcode / Android Studio)
jac build --client mobile --platform ios # or: jac start main.jac --client mobile --dev
```

The native shell opens straight into the mobile UI. The server allows cross-origin requests, so the app can call it from the device.

**4. Use the CLI** (in another terminal, from this folder):

```bash
./plan status                           # is the server up?
./plan demo                             # load a realistic demo week (or: ./plan sync all for just Canvas + Oura)

./plan add Write server walkers -p "EECS 449" -d fri -P 1 -e high -t 120
./plan add Build CLI -p "EECS 449" -t 60
./plan add Groceries -o today -e low --tags errand

./plan ls                               # numbers each task: 1, 2, 3 ...
./plan dep 3 2                          # task 3 now waits on task 2

./plan today                            # overdue / today / suggested, sized to your readiness
./plan today --commit                   # schedule the suggestions onto today
./plan done 2                           # numbers refer to the last list printed
./plan next                             # what's unblocked right now
./plan week                             # 7-day view
./plan projects EECS 449 --goal "Finish semester strong"
./plan goals
./plan help                             # all commands
```

Dates accept `today`, `tomorrow`, `mon`..`sun`, `+3`, or `2026-10-01`. To make `plan` work from anywhere, symlink the wrapper onto your PATH: `ln -s "$PWD/plan" /usr/local/bin/plan`.

The CLI remembers its server URL and your last list's numbering in `~/.planner/cli.json`. Point it at another server with `./plan server http://host:port` (or the `PLANNER_SERVER` env var).

## Integrations (optional)

Both integrations work with **mock data** out of the box, so the app is fully usable without any accounts. To use real data, set these before starting the server:

| Variable | Where to get it |
|---|---|
| `CANVAS_ICS_URL` | Canvas → Calendar → **Calendar Feed** (a private link; don't commit it) |
| `OURA_ACCESS_TOKEN` | An OAuth2 access token for the Oura API v2 |

Canvas assignments become tasks, with the course as their project. Oura data becomes daily `HealthSnapshot` nodes that `PlanDay` reads. Re-syncing updates existing items instead of duplicating them.

> The real Oura API path is written against the v2 endpoints (`daily_readiness`, `daily_sleep`, `sleep`, `daily_activity`) but hasn't been tested with a live account yet.

## Tests

```bash
jac test          # walker tests: CRUD, dependencies, cycles, capacity, idempotent sync, demo data
```

Tests run on a local test root and clear it first. They never touch real user data.

## API

Every endpoint is `POST /walker/<Name>` with a JSON body (no auth header needed). The response's `data.reports[0]` holds the result. Full interactive docs are at `http://localhost:8000/docs`.

| Walker | Purpose |
|---|---|
| `AddTask`, `UpdateTask`, `CompleteTask`, `ScheduleTask`, `DeleteTask` | Task CRUD (`UpdateTask` is partial) |
| `ListTasks` | Filter by status / project / tag |
| `LinkDependency` | Add or remove a "waits on" edge (cycle-checked) |
| `NextActions`, `PlanDay`, `WeekView` | Planning views |
| `AddProject`, `ListProjects`, `AddGoal`, `ListGoals` | Projects and goals with progress rollups |
| `SyncCanvas`, `SyncOura`, `GetHealth` | Integrations |
| `LoadDemo` | Load or refresh the demo week |

Send `today: "YYYY-MM-DD"` (your local date) so "today" means your day, not the server's.

## Layout

```
main.jac                   entry: registers the walkers + the client route table
start.sh                   one-command setup + run
services/models.jac        nodes, edges, view objects (the shared wire contract)
services/planner.jac       task / planning / project / goal walkers
services/integrations.jac  Canvas + Oura sync
services/demo.jac          LoadDemo: the sample week behind ./plan demo
components/api.cl.jac      client data layer: every web/mobile call to a walker goes through here
components/*.cl.jac        shared UI: TaskRow, TaskEditor, HealthCard, SyncButton, Toast
routes/Web*.cl.jac, WeekPage, TodayPage, ProjectsPage   web app
routes/Mobile*.cl.jac      mobile app (/m)
styles/global.css          styles for both clients (light + dark)
cli/plan.jac               terminal client (decodes responses into the same view types)
plan                       wrapper: ./plan <command>
tests/planner_tests.jac    walker tests
```

## How the pieces share data

The walkers are the only place planning logic lives. The CLI calls them over REST (`POST /walker/<Name>`). The web and mobile UIs call the same walkers through `components/api.cl.jac`, which uses Jac's `root spawn` from the browser. The walkers are public, so every client reads and writes the same shared graph.
