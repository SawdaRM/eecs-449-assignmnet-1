"""Planner data model: the graph that every client (web, mobile, CLI) shares.

Each signed-in user gets their own `root`. Everything hangs off it:

    root ──► Task ──PartOf──► Project ──Supports──► Goal
               │
               └──DependsOn──► Task        (this task is blocked until that one is done)

    root ──► HealthSnapshot   (one per day, from Oura or mock data)

Tasks always hang directly off `root`, so "all my tasks" is a single hop.
Projects, goals and dependencies are typed edges layered on top.
"""

import from datetime { date, datetime }


# ---------------------------------------------------------------- nodes

node Goal {
    has title: str;
    has target_date: str = "";
    has created_at: str = "";
}

node Project {
    has name: str;
    has color: str = "#6366f1";
    has archived: bool = False;
    has created_at: str = "";
}

node Task {
    has title: str;
    has notes: str = "";
    has due: str = "";            # ISO date "YYYY-MM-DD" or ""
    has scheduled: str = "";      # the day you plan to work on it, or ""
    has priority: int = 2;        # 1 = high, 2 = normal, 3 = low
    has est_minutes: int = 30;
    has energy: str = "normal";   # "high" (deep focus) | "normal" | "low"
    has status: str = "todo";     # "todo" | "done"
    has done_at: str = "";
    has created_at: str = "";
    has source: str = "manual";   # "manual" | "canvas"
    has external_id: str = "";    # id in the source system, for idempotent sync
    has tags: list[str] = [];
}

node HealthSnapshot {
    has day: str;
    has readiness: int = 0;
    has sleep_score: int = 0;
    has sleep_hours: float = 0.0;
    has steps: int = 0;
    has source: str = "mock";
}


# ---------------------------------------------------------------- edges

edge PartOf: Task --> Project {}

edge Supports: Project --> Goal {}

edge DependsOn: Task --> Task {}


# ---------------------------------------------------------------- views (wire format)

obj TaskView {
    has id: str,
        title: str,
        notes: str,
        due: str,
        scheduled: str,
        priority: int,
        est_minutes: int,
        energy: str,
        status: str,
        done_at: str,
        source: str,
        tags: list[str],
        project_id: str,
        project_name: str,
        depends_on: list[str],
        blocked_by: list[str],
        blocked: bool,
        overdue: bool;
}

obj ProjectView {
    has id: str,
        name: str,
        color: str,
        goal_id: str,
        goal_title: str,
        total: int,
        done: int,
        progress: float;
}

obj GoalView {
    has id: str,
        title: str,
        target_date: str,
        projects: list[str],
        total: int,
        done: int,
        progress: float;
}

obj HealthView {
    has day: str,
        readiness: int,
        sleep_score: int,
        sleep_hours: float,
        steps: int,
        source: str;
}

obj DayPlan {
    has day: str,
        health: HealthView | None,
        capacity_minutes: int,
        planned_minutes: int,
        overdue: list[TaskView],
        today: list[TaskView],
        suggested: list[TaskView],
        done_today: list[TaskView],
        note: str;
}

obj WeekDay {
    has day: str,
        weekday: str,
        tasks: list[TaskView],
        minutes: int;
}

obj WeekPlan {
    has start: str,
        days: list[WeekDay],
        unscheduled: list[TaskView];
}

obj SyncResult {
    has source: str,
        created: int,
        updated: int,
        message: str;
}


# ---------------------------------------------------------------- helpers

def _today() -> str {
    return date.today().isoformat();
}

def _now() -> str {
    return datetime.now().isoformat(timespec="seconds");
}

"""Clients send their local date; fall back to the server's date."""
def _day_or_today(day: str) -> str {
    return day if day else _today();
}

def _valid_day(day: str) -> bool {
    if not day {
        return True;
    }
    try {
        _ = date.fromisoformat(day);
        return True;
    } except ValueError {
        return False;
    }
}

def _clean_energy(energy: str) -> str {
    e = energy.lower().strip();
    return e if e in ["high", "normal", "low"] else "normal";
}

def _clean_priority(p: int) -> int {
    return max(1, min(3, p));
}


def task_view(t: Task, today: str) -> TaskView {
    projects = [t ->:PartOf:->];
    deps = [t ->:DependsOn:->];
    blockers = [d.title for d in deps if d.status != "done"];
    return TaskView(
        id=jid(t),
        title=t.title,
        notes=t.notes,
        due=t.due,
        scheduled=t.scheduled,
        priority=t.priority,
        est_minutes=t.est_minutes,
        energy=t.energy,
        status=t.status,
        done_at=t.done_at,
        source=t.source,
        tags=t.tags,
        project_id=jid(projects[0]) if projects else "",
        project_name=projects[0].name if projects else "",
        depends_on=[jid(d) for d in deps],
        blocked_by=blockers,
        blocked=len(blockers) > 0,
        overdue=(t.status != "done" and t.due != "" and t.due < today)
    );
}

def health_view(h: HealthSnapshot) -> HealthView {
    return HealthView(
        day=h.day,
        readiness=h.readiness,
        sleep_score=h.sleep_score,
        sleep_hours=h.sleep_hours,
        steps=h.steps,
        source=h.source
    );
}

def project_view(p: Project) -> ProjectView {
    tasks = [p <-:PartOf:<-];
    done = len([t for t in tasks if t.status == "done"]);
    goals = [p ->:Supports:->];
    return ProjectView(
        id=jid(p),
        name=p.name,
        color=p.color,
        goal_id=jid(goals[0]) if goals else "",
        goal_title=goals[0].title if goals else "",
        total=len(tasks),
        done=done,
        progress=(done * 1000 // len(tasks)) / 1000 if tasks else 0.0
    );
}

"""Progress rolls up two hops: Goal <- Project <- Task."""
def goal_view(g: Goal) -> GoalView {
    projects = [g <-:Supports:<-];
    total = 0;
    done = 0;
    for p in projects {
        tasks = [p <-:PartOf:<-];
        total += len(tasks);
        done += len([t for t in tasks if t.status == "done"]);
    }
    return GoalView(
        id=jid(g),
        title=g.title,
        target_date=g.target_date,
        projects=[p.name for p in projects],
        total=total,
        done=done,
        progress=(done * 1000 // total) / 1000 if total else 0.0
    );
}
