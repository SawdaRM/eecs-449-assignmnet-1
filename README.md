# Planner: a readiness-aware, graph-based planner in Jac

**Name:** Sawda Mim (uniqname: sawdam)  
**UMID:** 95969742  
EECS 449, Assignment 1

## What it is

Planner is a personal planner that knows **what blocks what** and **how much you can realistically do today**. Your tasks, projects and goals live in a graph on a Jac server, and four clients share it: a server, a web app, a mobile app and a CLI.

| Web: week board | Web: today | Mobile: today |
|---|---|---|
| ![Week board](docs/web-week.png) | ![Today](docs/web-today.png) | ![Mobile](docs/mobile-today.png) |

### Main features

- **Readiness-aware daily plan.** *Today* lists what's overdue and what's due, then fills the rest of the day with the best unblocked tasks. How much it plans depends on your readiness score: about 6h on a strong day, 5h on a normal day, 3h on a low one. Deep-focus work moves later when you're tired. If you've overbooked, it tells you which task to move.
- **Tasks that wait on other tasks.** A task can wait on others ("Record the demo video" waits on "Build the web board" and "Polish mobile screens"). Blocked tasks are marked everywhere, *Next up* shows only what you can start now, and a link that would create a loop is refused.
- **Week planning board.** A Mon–Sun board plus a *Someday* column. Drag tasks between days, and click any task to edit everything about it.
- **Projects and goals.** Tasks belong to projects, and projects support goals. Goal progress rolls up automatically.
- **Canvas and Oura.** Canvas assignments become tasks, with the course as the project. Oura sleep and readiness shape the plan. Both work out of the box with realistic mock data, and syncing twice never duplicates anything.
- **Four clients, one plan.** A task added in the terminal shows up on the web board and your phone. Check it off on your phone and the CLI sees it. There's no sign-in: everyone connected to the server shares the same plan.

## Setup

### Prerequisites

- **Python 3.12 or newer** (on a Mac: `brew install python@3.12`)
- **Node.js or Bun**, used to build the web client (on a Mac: `brew install node`)

### Install (once)

From the repository root:

```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install jaseci        # Jac + jac-scale (server) + jac-client (web/mobile)
```

The first `jac run` also installs the web client's npm packages automatically (you can run `jac install` to do that ahead of time).

No other configuration is needed. Canvas and Oura use mock data unless you set the optional variables described under [Integrations](#integrations-optional).

## Run the server and web app

```bash
source .venv/bin/activate   # if it isn't already
jac run
```

`jac run` starts the Jac server and the web app (it is configured as a full-stack Jac app in `jac.toml`, so this is equivalent to `jac start main.jac --dev`). Once it prints **Server ready**, open **http://localhost:8000**. Keep this terminal open while you use the app. The data is saved in `.jac/data/` and is still there after a restart.

Shortcut: `./start.sh` does the install steps above (only if needed) and then runs `jac run`.

**Load sample data (recommended for a first look):** click **Load demo week** on the empty web board, or run `./plan demo`. This loads 16 tasks, 2 goals, waiting chains, Canvas assignments and a week of readiness data. Running it again replaces only the demo tasks.

**Using the web app:**

- **Week** (`/`): drag tasks between days. Click a task to edit its dates, priority, energy, project, tags and what it *waits on*. Tick the circle to finish it. The quick-add bar is at the top.
- **Today** (`/today`): overdue, today and suggested tasks, with a readiness card and a load meter. *Add all to today* schedules the suggestions.
- **Projects & goals** (`/projects`): create goals, link projects to them, and watch progress roll up.

## Mobile app

The mobile app is the same Jac client with a phone layout (`/m`), connected to the same server.

**On a phone (no extra setup):**

1. Start the server with `jac run` on your computer.
2. Put the phone on the **same Wi-Fi** and open `http://<your-computer's-IP>:8000`. On a Mac, `ipconfig getifaddr en0` prints the IP, and `./start.sh` prints the full link. Phones open the mobile layout automatically.
3. No phone handy? Open http://localhost:8000/m in a browser, or click **Mobile view** in the web app's top bar.

**Using it:** there are four tabs.

- **Today:** tap a circle to finish a task. *Plan my day* accepts the suggestions.
- **Upcoming:** the next 7 days.
- **+ Add:** type a title, then tap chips for when, how long and how much energy.
- **Me:** 7 days of readiness, *Sync Canvas + Oura*, *Load demo week*, and the switch to the desktop view.

**Optional: build a native iOS or Android app** from the same code with Capacitor. This needs Xcode (iOS) or Android Studio (Android).

```bash
# In jac.toml, set [plugins.client.api] base_url to an address the phone can reach,
# e.g. base_url = "http://192.168.1.25:8000", and keep the server running with `jac run`.
jac setup mobile --platform ios            # one time (or: --platform android)
jac build --client mobile --platform ios   # builds the app (Android: an .apk in android/app/build/outputs/apk/)
npx cap open ios                           # open in Xcode to run it on a simulator/device
```

The native app opens straight into the mobile layout, and the server accepts its cross-origin requests.

## CLI

The CLI (`cli/plan.jac`) talks to the same server over REST. Run it from the repository root in a **second terminal** while `jac run` is running. The `./plan` wrapper uses `.venv` automatically.

```bash
./plan status                 # which server, and is it reachable?
./plan demo                   # load the demo week

./plan today                  # today's plan: overdue / today / suggested, readiness, load vs capacity
./plan today --commit         # schedule the suggestions onto today
./plan next                   # what you can start right now (nothing blocking it)
./plan week                   # the week, day by day

./plan add Finish HW 4 -p "EECS 482" -d fri -P 1 -e high -t 120
./plan add Groceries -o today -e low --tags errand
./plan ls                     # numbers the tasks 1, 2, 3...
./plan done 2                 # ...so you can refer to them by number
./plan dep 3 1                # task 3 waits on task 1
./plan sched 4 tomorrow       # move a task to another day
./plan edit 4 -t 45 --tags school

./plan projects               # progress bars;  ./plan projects "EECS 449" --goal "Finish strong"
./plan goals                  # goals and their projects
./plan sync all               # Canvas + Oura (mock unless configured)
./plan health                 # the last 7 days of readiness and sleep
./plan help                   # every command
```

- **Options:** `-d` is the due date, `-o` the day to work on it, `-p` the project, `-P` the priority (1–3), `-t` the minutes, `-e` the energy (high/normal/low), and `-a` the task(s) it waits on.
- **Dates:** you can write `today`, `tomorrow`, `mon`..`sun`, `+3` or `2026-10-01`.
- **Another server:** run `./plan server http://host:port` to use a different server.

## How the four parts fit together

```
             ┌──────────── Jac server (jac run) ─────────────┐
 CLI ──REST──▶│ walkers: PlanDay, NextActions, AddTask, ...    │
 Web ──spawn─▶│        ↓ traverse ↓                           │
 Mobile ─────▶│ graph: Task ─PartOf→ Project ─Supports→ Goal  │
             │        Task ─DependsOn→ Task, HealthSnapshot   │
             └──────── persisted in .jac/data ────────────────┘
```

- **Server** (`main.jac`, `services/`): all planning logic lives here, as walkers that move through the graph. `PlanDay` gathers open tasks and ranks them against your readiness. `ReachesTask` walks `DependsOn` edges to catch loops. Goal progress is counted over `Supports` and `PartOf` edges. Every walker is a public REST endpoint (`POST /walker/<Name>`, with docs at `/docs`).
- **Web and mobile** (`routes/`, `components/`): one Jac client app with two layouts. Every call goes through `components/api.cl.jac`, which runs the same walkers from the browser (`root spawn`).
- **CLI** (`cli/plan.jac`): calls the same walkers over HTTP. It decodes the replies into the same typed view objects the server defines in `services/models.jac`, so the server and CLI share one definition of the data.
- **Integrations** (`services/integrations.jac`): write Canvas assignments and Oura readiness into the graph, where `PlanDay` uses them.

Because the planning logic lives only in the walkers, the three clients can't disagree about what's due, what's blocked or what fits today.

### What makes it impressive

- **It plans for you instead of just storing lists.** Readiness sets the day's capacity, the order depends on due dates, priority and energy fit, and an overbooked day gets a concrete suggestion of what to move.
- **It uses Jac's graph model for real.** Dependencies, cycle checks and progress rollups are graph traversals, not SQL-style lookups.
- **Each client suits its job.** The web app is for planning (drag-and-drop week, full editor, goals). The mobile app is for doing (big tap targets, one-tap add, tabs; it also builds as a native app). The CLI is for speed (`./plan add ...`, `./plan done 2`).
- **Real inputs.** Canvas and Oura, with mock data so it works immediately.
- **Polish and reliability.** Light and dark themes, empty states, clear error messages, idempotent syncs, data that survives restarts, 7 automated walker tests (`jac test`), and the whole web + mobile + CLI flow checked in a browser from a fresh checkout.

| Task editor ("waits on") | Projects & goals | Mobile: upcoming |
|---|---|---|
| ![Editor](docs/web-editor.png) | ![Projects](docs/web-projects.png) | ![Upcoming](docs/mobile-upcoming.png) |

## Integrations (optional)

Set these before `jac run` to use real data instead of mock data:

| Variable | Where to get it |
|---|---|
| `CANVAS_ICS_URL` | Canvas → Calendar → **Calendar Feed** (a private link; don't commit it) |
| `OURA_ACCESS_TOKEN` | An OAuth2 access token for the Oura API v2 |

> The Oura code uses the v2 endpoints (`daily_readiness`, `daily_sleep`, `sleep`, `daily_activity`) but hasn't been tried with a live account.

## Tests

```bash
jac test      # walker tests: CRUD, dependencies, cycles, capacity, idempotent sync, demo data
```

Tests run on their own test root and never touch the planner's real data.

## Troubleshooting

- **http://localhost:8000 doesn't load:** the server must be running. Keep the `jac run` terminal open and wait for the URLs to print (the first start builds the web app).
- **"Port already in use":** another copy is probably running. Stop it, or free ports 8000 and 8001.
- **`./plan` says it can't reach the server:** start `jac run` first. `./plan status` checks the connection.
- **The phone can't connect:** make sure the phone and computer are on the same Wi-Fi, and that you used the computer's IP address, not `localhost`.

## Project layout

```
main.jac                   entry point: registers the walkers + the client route table
services/models.jac        graph nodes/edges and view objects (the shared data contract)
services/planner.jac       task, planning, project and goal walkers
services/integrations.jac  Canvas + Oura sync
services/demo.jac          LoadDemo: the sample week
components/                shared UI + api.cl.jac (all client → walker calls)
routes/                    web pages (WebShell, WeekPage, TodayPage, ProjectsPage) and mobile screens (Mobile*)
styles/global.css          styles for web + mobile (light/dark)
cli/plan.jac, plan         the CLI and its wrapper
tests/planner_tests.jac    walker tests
start.sh                   optional one-step setup + jac run
jac.toml                   project config (jac run → server + web app; mobile settings)
```
