"""plan - the terminal client for the Planner server.

    ./plan <command> [options]          (wrapper for: jac run cli/plan.jac ...)

Talks to the same server as the web and mobile apps over its REST API, so
anything you add here shows up everywhere. Responses are decoded into the
same typed view objects the server defines in services/models.jac, so the
CLI and server share one contract. Run `./plan help` for commands.
"""

import os;
import sys;
import json;
import argparse;
import from urllib.request { urlopen, Request }
import from urllib.error { HTTPError, URLError }
import from datetime { date, timedelta }
import from services.models {
    TaskView, ProjectView, GoalView, HealthView, DayPlan, WeekDay, WeekPlan, SyncResult
}


glob CONFIG_DIR: str = os.path.join(os.path.expanduser("~"), ".planner"),
     CONFIG_FILE: str = os.path.join(CONFIG_DIR, "cli.json"),
     DEFAULT_SERVER: str = "http://localhost:8000",
     COLOR: bool = os.isatty(1) and not os.environ.get("NO_COLOR");


# ================================================================ output helpers

def c(text: str, code: str) -> str {
    return f"\033[{code}m{text}\033[0m" if COLOR else text;
}

def bold(t: str) -> str { return c(t, "1"); }
def dim(t: str) -> str { return c(t, "2"); }
def red(t: str) -> str { return c(t, "31"); }
def green(t: str) -> str { return c(t, "32"); }
def yellow(t: str) -> str { return c(t, "33"); }
def cyan(t: str) -> str { return c(t, "36"); }

def die(msg: str) {
    os.write(2, (red("error: ") + msg + "\n").encode());
    sys.exit(1);
}


# ================================================================ config (~/.planner/cli.json)

obj Config {
    has server: str = "",
        last: list[str] = [];
}

def load_config() -> Config {
    try {
        with open(CONFIG_FILE) as f {
            raw = json.load(f) as dict[str, any];
        }
        return Config(
            server=str(raw.get("server") or ""),
            last=[str(x) for x in ((raw.get("last") or []) as list[any])]
        );
    } except (FileNotFoundError, json.JSONDecodeError) {
        return Config();
    }
}

def save_config(cfg: Config) {
    os.makedirs(CONFIG_DIR, exist_ok=True);
    with open(CONFIG_FILE, "w") as f {
        json.dump(
            {"server": cfg.server, "last": cfg.last},
            f,
            indent=2
        );
    }
}

def server_url(cfg: Config) -> str {
    return str(os.environ.get("PLANNER_SERVER") or cfg.server or DEFAULT_SERVER).rstrip("/");
}


# ================================================================ HTTP

def http_post(url: str, body: dict[str, any]) -> dict[str, any] {
    headers: dict[str, str] = {"Content-Type": "application/json"};
    req = Request(url, data=json.dumps(body).encode(), headers=headers, method="POST");
    try {
        resp = urlopen(req, timeout=30);
        text = str(resp.read().decode());
        resp.close();
        return json.loads(text) as dict[str, any];
    } except HTTPError as e {
        try {
            return json.loads(str(e.read().decode())) as dict[str, any];
        } except json.JSONDecodeError {
            return {"ok": False, "error": {"message": f"HTTP {e.code}"}};
        }
    } except URLError {
        die(f"can't reach the planner server at {server_url(load_config())} - is it running? (jac start main.jac)");
    }
    return {};
}

def error_message(payload: dict[str, any]) -> str {
    err = payload.get("error");
    if isinstance(err, dict) and err.get("message") {
        return str(err["message"]);
    }
    detail = payload.get("detail");
    if isinstance(detail, list) and detail {
        first = detail[0] as dict[str, any];
        loc = [str(x) for x in ((first.get("loc") or []) as list[any])];
        return f"{'.'.join(loc)}: {first.get('msg', '')}";
    }
    return str(detail or "request failed");
}

"""Call POST /walker/<name> and return its single report.

There is no login: every client works on the server's one shared plan.
"""
def api(walker_name: str, body: dict[str, any]) -> any {
    cfg = load_config();
    body["today"] = date.today().isoformat();
    payload = http_post(f"{server_url(cfg)}/walker/{walker_name}", body);
    if not payload.get("ok") {
        die(error_message(payload));
    }
    data = payload["data"] as dict[str, any];
    reports = (data.get("reports") or []) as list[any];
    return reports[0] if reports else None;
}


# ================================================================ decoding into shared view types

def _fields(raw: any) -> dict[str, any] {
    d = raw as dict[str, any];
    return {k: v for (k, v) in d.items() if not k.startswith("_jac")};
}

def to_task(raw: any) -> TaskView { return TaskView(**_fields(raw)); }
def to_tasks(raw: any) -> list[TaskView] { return [to_task(x) for x in ((raw or []) as list[any])]; }
def to_project(raw: any) -> ProjectView { return ProjectView(**_fields(raw)); }
def to_goal(raw: any) -> GoalView { return GoalView(**_fields(raw)); }
def to_health(raw: any) -> HealthView { return HealthView(**_fields(raw)); }
def to_sync(raw: any) -> SyncResult { return SyncResult(**_fields(raw)); }

def to_plan(raw: any) -> DayPlan {
    d = _fields(raw);
    return DayPlan(
        day=str(d["day"]),
        health=to_health(d["health"]) if d.get("health") else None,
        capacity_minutes=int(d["capacity_minutes"]),
        planned_minutes=int(d["planned_minutes"]),
        overdue=to_tasks(d["overdue"]),
        today=to_tasks(d["today"]),
        suggested=to_tasks(d["suggested"]),
        done_today=to_tasks(d["done_today"]),
        note=str(d["note"])
    );
}

def to_week(raw: any) -> WeekPlan {
    d = _fields(raw);
    days: list[WeekDay] = [];
    for x in d["days"] as list[any] {
        wd = _fields(x);
        days.append(
            WeekDay(
                day=str(wd["day"]),
                weekday=str(wd["weekday"]),
                tasks=to_tasks(wd["tasks"]),
                minutes=int(wd["minutes"])
            )
        );
    }
    return WeekPlan(start=str(d["start"]), days=days, unscheduled=to_tasks(d["unscheduled"]));
}


# ================================================================ parsing helpers

"""today / tomorrow / mon..sun / +N / YYYY-MM-DD / none (clear)."""
def parse_day(text: str) -> str {
    t = text.strip().lower();
    today = date.today();
    if t in ["", "none", "clear"] {
        return "";
    }
    if t in ["today", "tod"] {
        return today.isoformat();
    }
    if t in ["tomorrow", "tom", "tmr"] {
        return (today + timedelta(days=1)).isoformat();
    }
    if t.startswith("+") and t[1:].isdigit() {
        return (today + timedelta(days=int(t[1:]))).isoformat();
    }
    names = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
    if t[:3] in names {
        ahead = (names.index(t[:3]) - today.weekday()) % 7;
        return (today + timedelta(days=ahead or 7)).isoformat();
    }
    try {
        return date.fromisoformat(t).isoformat();
    } except ValueError {
        die(f"don't understand the date '{text}' (try today, tomorrow, fri, +3, 2026-10-01)");
    }
    return "";
}

"""Number the tasks just printed so `plan done 2` works next."""
def remember_listing(tasks: list[TaskView]) {
    cfg = load_config();
    cfg.last = [t.id for t in tasks];
    save_config(cfg);
}

"""A number from the last listing, or the start of a task id."""
def resolve_task(ref: str) -> str {
    cfg = load_config();
    if ref.isdigit() and len(ref) <= 3 {
        n = int(ref);
        if 1 <= n and n <= len(cfg.last) {
            return cfg.last[n - 1];
        }
        die(f"no task #{ref} in your last list - run `plan ls` or `plan today` first");
    }
    matches = [t.id for t in to_tasks(api("ListTasks", {"status": "all"})) if t.id.startswith(ref)];
    if len(matches) == 1 {
        return matches[0];
    }
    die(f"'{ref}' matches {len(matches)} tasks - use more of the id");
    return "";
}


# ================================================================ rendering

def fmt_day(d: str) -> str {
    if not d {
        return "";
    }
    day = date.fromisoformat(d);
    delta = (day - date.today()).days;
    if delta == 0 {
        return "today";
    }
    if delta == 1 {
        return "tomorrow";
    }
    if delta == -1 {
        return "yesterday";
    }
    if 1 < delta and delta < 7 {
        return day.strftime("%a");
    }
    return f"{day.strftime('%b')} {day.day}";
}

def task_text(t: TaskView) -> str {
    title = dim(t.title) if t.status == "done" else t.title;
    if t.priority == 1 and t.status != "done" {
        title = bold(title) + red(" !");
    }
    bits: list[str] = [];
    if t.due {
        due_txt = f"due {fmt_day(t.due)}";
        bits.append(red(due_txt) if t.overdue else yellow(due_txt));
    }
    if t.scheduled and t.scheduled != t.due {
        bits.append(cyan(f"on {fmt_day(t.scheduled)}"));
    }
    if t.project_name {
        bits.append(dim(f"[{t.project_name}]"));
    }
    bits.append(dim(f"{t.est_minutes}m"));
    if t.energy != "normal" {
        bits.append(dim(f"{t.energy}-energy"));
    }
    for tag in t.tags {
        bits.append(dim(f"#{tag}"));
    }
    if t.blocked {
        bits.append(dim("waiting on: " + ", ".join(t.blocked_by)));
    }
    return f"{title}  {'  '.join(bits)}";
}

def task_line(n: int, t: TaskView) -> str {
    box = green("✔") if t.status == "done" else (dim("⧗") if t.blocked else "○");
    return f"{dim(str(n).rjust(3))} {box} {task_text(t)}";
}

def print_tasks(tasks: list[TaskView], start: int = 1) -> int {
    n = start;
    for t in tasks {
        print(task_line(n, t));
        n += 1;
    }
    return n;
}

def hours(minutes: int) -> str {
    return f"{minutes // 60}h{str(minutes % 60).rjust(2, '0')}" if minutes >= 60 else f"{minutes}m";
}

def long_day(d: str) -> str {
    day = date.fromisoformat(d);
    return f"{day.strftime('%A, %B')} {day.day}";
}


# ================================================================ commands

def cmd_status(a: any) {
    cfg = load_config();
    url = server_url(cfg);
    print(f"server: {url}");
    try {
        resp = urlopen(f"{url}/healthz", timeout=5);
        resp.close();
        print("status: " + green("reachable"));
    } except Exception {
        print("status: " + red("not reachable") + " - start it with `jac start main.jac`");
    }
    print(f"config: {CONFIG_FILE}");
}

def cmd_server(a: any) {
    cfg = load_config();
    cfg.server = str(a.url).rstrip("/");
    cfg.last = [];
    save_config(cfg);
    print(f"server set to {cfg.server}");
}

def cmd_add(a: any) {
    body: dict[str, any] = {"title": " ".join(a.title as list[str])};
    if a.due {
        body["due"] = parse_day(str(a.due));
    }
    if a.on {
        body["scheduled"] = parse_day(str(a.on));
    }
    if a.project {
        body["project"] = str(a.project);
    }
    if a.priority {
        body["priority"] = int(a.priority);
    }
    if a.minutes {
        body["est_minutes"] = int(a.minutes);
    }
    if a.energy {
        body["energy"] = str(a.energy);
    }
    if a.tags {
        body["tags"] = [x for x in str(a.tags).split(",") if x.strip()];
    }
    if a.after {
        body["depends_on"] = [resolve_task(x.strip()) for x in str(a.after).split(",")];
    }
    t = to_task(api("AddTask", body));
    print(green("+ added ") + task_text(t));
}

def cmd_today(a: any) {
    p = to_plan(api("PlanDay", {"commit": bool(a.commit)}));
    print(bold(long_day(p.day)));
    h = p.health;
    if h is not None {
        print(dim(f"readiness {h.readiness} · sleep {h.sleep_hours}h (score {h.sleep_score}) · {h.source}"));
    }
    print(dim(p.note));
    shown: list[TaskView] = [];
    n = 1;
    if p.overdue {
        print("\n" + red("Overdue"));
        n = print_tasks(p.overdue, n);
        shown.extend(p.overdue);
    }
    print("\n" + bold("Today") + dim(f"  {hours(p.planned_minutes)} planned of {hours(p.capacity_minutes)}"));
    if p.today {
        n = print_tasks(p.today, n);
        shown.extend(p.today);
    } else {
        print(dim("    nothing scheduled yet"));
    }
    if p.suggested {
        print("\n" + cyan("Suggested") + dim("  (run `plan today --commit` to schedule these)"));
        n = print_tasks(p.suggested, n);
        shown.extend(p.suggested);
    }
    if p.done_today {
        print("\n" + green(f"Done today ({len(p.done_today)})"));
        n = print_tasks(p.done_today, n);
        shown.extend(p.done_today);
    }
    remember_listing(shown);
}

def cmd_ls(a: any) {
    status = "all" if a.all else ("done" if a.done else "todo");
    body: dict[str, any] = {"status": status};
    if a.project {
        body["project"] = str(a.project);
    }
    if a.tag {
        body["tag"] = str(a.tag);
    }
    tasks = to_tasks(api("ListTasks", body));
    if not tasks {
        print(dim("no tasks"));
        return;
    }
    print_tasks(tasks);
    remember_listing(tasks);
}

def cmd_next(a: any) {
    tasks = to_tasks(api("NextActions", {"limit": int(a.n)}));
    if not tasks {
        print(dim("nothing actionable - nice"));
        return;
    }
    print(bold("Next up") + dim("  (unblocked, best first)"));
    print_tasks(tasks);
    remember_listing(tasks);
}

def cmd_done(a: any) {
    ids = [resolve_task(str(ref)) for ref in (a.tasks as list[str])];
    for tid in ids {
        t = to_task(api("CompleteTask", {"id": tid, "done": not a.undo}));
        mark = "reopened" if a.undo else "done";
        print(green(f"✔ {mark}: ") + t.title);
    }
}

def cmd_rm(a: any) {
    ids = [resolve_task(str(ref)) for ref in (a.tasks as list[str])];
    for tid in ids {
        api("DeleteTask", {"id": tid});
        print(f"deleted {tid[:8]}");
    }
    cfg = load_config();
    cfg.last = [];
    save_config(cfg);
}

def cmd_sched(a: any) {
    t = to_task(api("ScheduleTask", {"id": resolve_task(str(a.task)), "on": parse_day(str(a.day))}));
    when = fmt_day(t.scheduled) if t.scheduled else "unscheduled";
    print(cyan(f"→ {when}: ") + t.title);
}

def cmd_edit(a: any) {
    body: dict[str, any] = {"id": resolve_task(str(a.task))};
    if a.title {
        body["title"] = str(a.title);
    }
    if a.due is not None {
        body["due"] = parse_day(str(a.due));
    }
    if a.project is not None {
        body["project"] = str(a.project);
    }
    if a.priority {
        body["priority"] = int(a.priority);
    }
    if a.minutes {
        body["est_minutes"] = int(a.minutes);
    }
    if a.energy {
        body["energy"] = str(a.energy);
    }
    if a.tags is not None {
        body["tags"] = [x for x in str(a.tags).split(",") if x.strip()];
    }
    t = to_task(api("UpdateTask", body));
    print(green("✎ updated ") + task_text(t));
}

def cmd_dep(a: any) {
    t = to_task(api("LinkDependency", {
        "task_id": resolve_task(str(a.task)),
        "depends_on_id": resolve_task(str(a.on)),
        "remove": bool(a.remove)
    }));
    if t.blocked {
        print(f"{t.title} " + dim("now waits on: ") + ", ".join(t.blocked_by));
    } else {
        print(f"{t.title} " + dim("has no open blockers"));
    }
}

def cmd_week(a: any) {
    w = to_week(api("WeekView", {"start": parse_day(str(a.start)) if a.start else ""}));
    shown: list[TaskView] = [];
    n = 1;
    today = date.today().isoformat();
    for d in w.days {
        day = date.fromisoformat(d.day);
        label = f"{d.weekday} {day.strftime('%b')} {day.day}";
        head = bold(label + "  ← today") if d.day == today else label;
        print("\n" + head + dim(f"  {hours(d.minutes)}"));
        if d.tasks {
            n = print_tasks(d.tasks, n);
            shown.extend(d.tasks);
        }
    }
    if w.unscheduled {
        print("\n" + dim("Unscheduled"));
        n = print_tasks(w.unscheduled, n);
        shown.extend(w.unscheduled);
    }
    remember_listing(shown);
}

def cmd_projects(a: any) {
    words = a.name as list[str];
    if words {
        p = to_project(api("AddProject", {"name": " ".join(words), "goal": str(a.goal or "")}));
        print(green("✔ project ") + p.name + (dim(f" → {p.goal_title}") if p.goal_title else ""));
        return;
    }
    projects = [to_project(x) for x in ((api("ListProjects", {}) or []) as list[any])];
    if not projects {
        print(dim("no projects yet - `plan add \"task\" -p NAME` creates one"));
    }
    for p in projects {
        bar_len = 20;
        filled = int(p.progress * bar_len);
        bar = green("█" * filled) + dim("░" * (bar_len - filled));
        goal = dim(f"  → {p.goal_title}") if p.goal_title else "";
        print(f"{bar} {p.done}/{p.total}  {bold(p.name)}{goal}");
    }
}

def cmd_goals(a: any) {
    words = a.title as list[str];
    if words {
        g = to_goal(api("AddGoal", {"title": " ".join(words), "target_date": parse_day(str(a.by)) if a.by else ""}));
        print(green("✔ goal ") + g.title);
        return;
    }
    goals = [to_goal(x) for x in ((api("ListGoals", {}) or []) as list[any])];
    if not goals {
        print(dim("no goals yet - try: plan goals Finish the semester strong --by 2026-12-15"));
    }
    for g in goals {
        pct = int(g.progress * 100);
        by = dim(f"  by {g.target_date}") if g.target_date else "";
        print(f"{bold(g.title)}  {pct}% ({g.done}/{g.total} tasks){by}");
        for name in g.projects {
            print(dim(f"    · {name}"));
        }
    }
}

def cmd_sync(a: any) {
    source = str(a.source);
    targets = ["canvas", "oura"] if source == "all" else [source];
    for s in targets {
        walker_name = "SyncCanvas" if s == "canvas" else "SyncOura";
        r = to_sync(api(walker_name, {"mock": bool(a.mock)}));
        print(green("✔ ") + r.message);
    }
}

def cmd_health(a: any) {
    rows = [to_health(x) for x in ((api("GetHealth", {"days": int(a.days)}) or []) as list[any])];
    if not rows {
        print(dim("no health data - run `plan sync oura`"));
        return;
    }
    for h in rows {
        r = h.readiness;
        colored = green(str(r)) if r >= 85 else (yellow(str(r)) if r >= 70 else red(str(r)));
        print(f"{h.day}  readiness {colored}  sleep {h.sleep_hours}h ({h.sleep_score})  steps {h.steps}  {dim(h.source)}");
    }
}


# ================================================================ argument parser

def _int(text: str) -> int {
    return int(text);
}


def build_parser() -> argparse.ArgumentParser {
    p = argparse.ArgumentParser(
        prog="plan",
        description="Terminal client for your Jac planner.",
        epilog="Dates accept: today, tomorrow, mon..sun, +3, 2026-10-01. "
        + "Refer to tasks by their number in the last list you printed, or an id prefix."
    );
    sub = p.add_subparsers(dest="cmd", metavar="<command>");

    r = sub.add_parser("server", help=f"point the CLI at another server (default {DEFAULT_SERVER})");
    r.add_argument("url");
    r.set_defaults(fn=cmd_server);

    r = sub.add_parser("status", help="show which server the CLI uses and whether it is up");
    r.set_defaults(fn=cmd_status);

    r = sub.add_parser("add", help="add a task");
    r.add_argument("title", nargs="+");
    r.add_argument("-d", "--due", help="due date");
    r.add_argument("-o", "--on", help="day you plan to work on it");
    r.add_argument("-p", "--project", help="project name (created if new)");
    r.add_argument("-P", "--priority", type=_int, choices=[1, 2, 3], help="1 high, 2 normal, 3 low");
    r.add_argument("-t", "--minutes", type=_int, help="estimated minutes");
    r.add_argument("-e", "--energy", choices=["high", "normal", "low"]);
    r.add_argument("--tags", help="comma-separated tags");
    r.add_argument("-a", "--after", help="task(s) this waits on, comma-separated");
    r.set_defaults(fn=cmd_add);

    r = sub.add_parser("today", help="today's plan: overdue, scheduled, suggested");
    r.add_argument("-c", "--commit", action="store_true", help="schedule the suggestions onto today");
    r.set_defaults(fn=cmd_today);

    r = sub.add_parser("ls", help="list open tasks");
    r.add_argument("-p", "--project");
    r.add_argument("--tag");
    g = r.add_mutually_exclusive_group();
    g.add_argument("--all", action="store_true", help="include done tasks");
    g.add_argument("--done", action="store_true", help="only done tasks");
    r.set_defaults(fn=cmd_ls);

    r = sub.add_parser("next", help="what you can work on right now");
    r.add_argument("-n", type=_int, default=5);
    r.set_defaults(fn=cmd_next);

    r = sub.add_parser("done", help="mark task(s) complete");
    r.add_argument("tasks", nargs="+");
    r.add_argument("-u", "--undo", action="store_true", help="reopen instead");
    r.set_defaults(fn=cmd_done);

    r = sub.add_parser("rm", help="delete task(s)");
    r.add_argument("tasks", nargs="+");
    r.set_defaults(fn=cmd_rm);

    r = sub.add_parser("sched", help="move a task to a day ('none' unschedules)");
    r.add_argument("task");
    r.add_argument("day");
    r.set_defaults(fn=cmd_sched);

    r = sub.add_parser("edit", help="change a task's fields");
    r.add_argument("task");
    r.add_argument("--title");
    r.add_argument("-d", "--due", help="due date ('none' clears it)");
    r.add_argument("-p", "--project", help="project ('' removes it)");
    r.add_argument("-P", "--priority", type=_int, choices=[1, 2, 3]);
    r.add_argument("-t", "--minutes", type=_int);
    r.add_argument("-e", "--energy", choices=["high", "normal", "low"]);
    r.add_argument("--tags");
    r.set_defaults(fn=cmd_edit);

    r = sub.add_parser("dep", help="make TASK wait on another task");
    r.add_argument("task");
    r.add_argument("on", help="the task it waits on");
    r.add_argument("--remove", action="store_true");
    r.set_defaults(fn=cmd_dep);

    r = sub.add_parser("week", help="this week, day by day");
    r.add_argument("--start", help="first day to show");
    r.set_defaults(fn=cmd_week);

    r = sub.add_parser("projects", help="list projects, or add one: projects NAME [--goal G]");
    r.add_argument("name", nargs="*");
    r.add_argument("-g", "--goal");
    r.set_defaults(fn=cmd_projects);

    r = sub.add_parser("goals", help="list goals, or add one: goals TITLE [--by DATE]");
    r.add_argument("title", nargs="*");
    r.add_argument("--by");
    r.set_defaults(fn=cmd_goals);

    r = sub.add_parser("sync", help="pull Canvas assignments / Oura data");
    r.add_argument("source", choices=["canvas", "oura", "all"]);
    r.add_argument("--mock", action="store_true", help="force mock data");
    r.set_defaults(fn=cmd_sync);

    r = sub.add_parser("health", help="recent readiness & sleep");
    r.add_argument("--days", type=_int, default=7);
    r.set_defaults(fn=cmd_health);

    return p;
}


with entry {
    parser = build_parser();
    argv = sys.argv[1:];
    if not argv or argv[0] == "help" {
        parser.print_help();
    } else {
        args = parser.parse_args(argv);
        args.fn(args);
    }
}
