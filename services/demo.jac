"""Demo data: a realistic student week, so every feature has something to show.

`LoadDemo` builds goals, projects, tasks spread across this week, a few
finished ones, and "waits on" chains, all relative to `today`. Demo tasks are
marked `source="demo"`, and re-running replaces them (your own tasks are
never touched). Clients follow it with SyncCanvas + SyncOura (mock) to add
assignments and readiness data.
"""

import from datetime { date, timedelta }
import from services.models { Task, Goal, Project, Supports, DependsOn, SyncResult, _now }
import from services.planner { _set_project, _find_goal, _find_project }


obj DemoTask {
    has key: str,
        title: str,
        project: str = "",
        due: int | None = None,        # days from today
        on: int | None = None,         # scheduled day, days from today
        minutes: int = 30,
        energy: str = "normal",
        priority: int = 2,
        done_ago: int | None = None,   # finished N days ago (0 = today)
        after: list[str] = [],         # keys of tasks this one waits on
        tags: list[str] = [];
}

glob GOALS: list[tuple[str, int, list[str]]] = [
    ("Finish the semester strong", 75, ["EECS 449", "EECS 482"]),
    ("Land a summer internship", 120, ["Internship search"])
];

glob TASKS: list[DemoTask] = [
    # EECS 449: this project
    DemoTask(key="model", title="Design the planner graph model", project="EECS 449", done_ago=2, minutes=60, energy="high"),
    DemoTask(key="board", title="Build the web week board", project="EECS 449", on=0, due=2, minutes=120, energy="high", priority=1, after=["model"]),
    DemoTask(key="mobile", title="Polish the mobile screens", project="EECS 449", on=1, minutes=90, after=["model"]),
    DemoTask(key="video", title="Record the demo video", project="EECS 449", due=5, minutes=45, after=["board", "mobile"]),
    # EECS 482
    DemoTask(key="spec", title="Read the thread library spec", project="EECS 482", done_ago=1, minutes=60),
    DemoTask(key="sched", title="Implement the thread scheduler", project="EECS 482", due=4, on=2, minutes=180, energy="high", priority=1, after=["spec"]),
    DemoTask(key="tests", title="Write scheduler test cases", project="EECS 482", due=6, minutes=90, after=["sched"]),
    # Internship search
    DemoTask(key="resume", title="Update resume with the planner project", project="Internship search", on=0, minutes=45, energy="low"),
    DemoTask(key="apply", title="Apply to three companies", project="Internship search", due=6, minutes=90, after=["resume"]),
    DemoTask(key="chat", title="Prep questions for coffee chat", project="Internship search", on=2, minutes=30),
    # Life
    DemoTask(key="books", title="Return library books", due=-2, minutes=15, energy="low", tags=["errand"]),
    DemoTask(key="groceries", title="Groceries", on=0, minutes=40, energy="low", tags=["errand"]),
    DemoTask(key="mom", title="Call mom", on=1, minutes=20, energy="low"),
    DemoTask(key="gym", title="Gym: legs", on=3, minutes=60, tags=["health"]),
    DemoTask(key="laundry", title="Laundry", minutes=30, energy="low", tags=["errand"]),
    DemoTask(key="coffee", title="Morning planning session", done_ago=0, minutes=15, energy="low")
];

def _day(today: date, offset: int | None) -> str {
    return "" if offset is None else (today + timedelta(days=offset)).isoformat();
}

walker:pub LoadDemo {
    """Replace the demo tasks with a fresh demo week."""
    has today: str = "",
        reports: list[SyncResult] = [];

    can seed with Root entry {
        today = date.fromisoformat(self.today) if self.today else date.today();

        removed = 0;
        for t in [root-->[?:Task]] {
            if t.source == "demo" {
                del t;
                removed += 1;
            }
        }

        for (title, days_out, projects) in GOALS {
            g = _find_goal(title);
            if g is None {
                g = (root ++> Goal(title=title, created_at=_now()))[0];
            }
            g.target_date = (today + timedelta(days=days_out)).isoformat();
            for name in projects {
                p = _find_project(name);
                if p is None {
                    p = (root ++> Project(name=name, created_at=_now()))[0];
                }
                if not [p ->:Supports:->] {
                    p +>:Supports:+> g;
                }
            }
        }

        made: dict[str, Task] = {};
        for d in TASKS {
            done = d.done_ago is not None;
            t = (root ++> Task(
                title=d.title,
                due=_day(today, d.due),
                scheduled=_day(today, d.on),
                priority=d.priority,
                est_minutes=d.minutes,
                energy=d.energy,
                status="done" if done else "todo",
                done_at=(_day(today, 0 - (d.done_ago or 0)) + "T09:00:00") if done else "",
                source="demo",
                tags=d.tags,
                created_at=_now()
            ))[0];
            if d.project {
                _set_project(t, d.project);
            }
            for k in d.after {
                if k in made {
                    t +>:DependsOn:+> made[k];
                }
            }
            made[d.key] = t;
        }

        report SyncResult(
            source="demo",
            created=len(made),
            updated=removed,
            message=f"Demo week loaded: {len(made)} tasks, {len(GOALS)} goals."
        );
    }
}
