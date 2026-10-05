"""Planner API: walkers that read and reshape the task graph.

Every walker here is public (`walker:pub`): there is no login. All clients
share one planner graph (the server's shared root), so the web app, the
mobile app and the CLI always show the same plan. They are
served as `POST /walker/<Name>`; request-body keys map onto `has` fields and
each walker reports exactly one value (read `data.reports[0]`).

Dates are ISO strings. Clients pass `today` (their local date) so "today"
means the user's day, not the server's.
"""

import from datetime { date, timedelta }
import from services.models {
    Goal, Project, Task, HealthSnapshot,
    PartOf, Supports, DependsOn,
    TaskView, ProjectView, GoalView, HealthView, DayPlan, WeekDay, WeekPlan,
    task_view, project_view, goal_view, health_view,
    _now, _day_or_today, _valid_day, _clean_energy, _clean_priority
}
import from services.calendar { budget_context, day_budget }


glob KEEP: str = "~keep";

# ================================================================ lookups

def _find_task(ref: str) -> Task | None {
    for t in [root-->[?:Task]] {
        if jid(t) == ref {
            return t;
        }
    }
    return None;
}

"""Match a project by id, or by name (case-insensitive)."""
def _find_project(ref: str) -> Project | None {
    key = ref.strip().lower();
    for p in [root-->[?:Project]] {
        if jid(p) == ref or p.name.lower() == key {
            return p;
        }
    }
    return None;
}

def _find_goal(ref: str) -> Goal | None {
    key = ref.strip().lower();
    for g in [root-->[?:Goal]] {
        if jid(g) == ref or g.title.lower() == key {
            return g;
        }
    }
    return None;
}

def _get_or_create_project(ref: str) -> Project {
    found = _find_project(ref);
    if found is not None {
        return found;
    }
    return (root ++> Project(name=ref.strip(), created_at=_now()))[0];
}

def _set_project(t: Task, ref: str) {
    for e in [edge t ->:PartOf:->] {
        del e;
    }
    if ref.strip() {
        p = _get_or_create_project(ref);
        t +>:PartOf:+> p;
    }
}

def _health_for(target_day: str) -> HealthSnapshot | None {
    for h in [root-->[?:HealthSnapshot, day == target_day]] {
        return h;
    }
    return None;
}

def _is_blocked(t: Task) -> bool {
    for d in [t ->:DependsOn:->] {
        if d.status != "done" {
            return True;
        }
    }
    return False;
}


# ================================================================ planning logic

"""Minutes of focused work to plan for, based on readiness (0 = unknown)."""
def _capacity(readiness: int) -> int {
    if readiness == 0 {
        return 300;
    }
    if readiness >= 85 {
        return 360;
    }
    if readiness >= 70 {
        return 300;
    }
    return 180;
}

"""Lower score = do it sooner."""
def _score(t: Task, today: str, readiness: int) -> int {
    s = 0;
    if t.due {
        days_left = (date.fromisoformat(t.due) - date.fromisoformat(today)).days;
        s += -500 if days_left < 0 else days_left * 10;
    } else {
        s += 150;
    }
    if t.scheduled == today {
        s -= 300;
    }
    s += (t.priority - 1) * 40;
    if t.energy == "high" {
        if readiness > 0 and readiness < 70 {
            s += 90;        # tired: push deep work back
        } elif readiness >= 85 {
            s -= 20;        # great day: pull deep work forward
        }
    } elif t.energy == "low" and readiness > 0 and readiness < 70 {
        s -= 20;
    }
    return s;
}

def _sort_views(views: list[TaskView]) -> list[TaskView] {
    views.sort(
        key=lambda v: TaskView : (
            v.scheduled or v.due or "9999-99-99",
            v.due or "9999-99-99",
            v.priority,
            v.title.lower()
        )
    );
    return views;
}


# ================================================================ tasks

walker:pub AddTask {
    has title: str;
    has notes: str = "",
        due: str = "",
        scheduled: str = "",
        priority: int = 2,
        est_minutes: int = 30,
        energy: str = "normal",
        project: str = "",
        tags: list[str] = [],
        depends_on: list[str] = [],
        today: str = "",
        reports: list[TaskView] = [];

    can create with Root entry {
        if not self.title.strip() {
            raise ValueError("title is required");
        }
        if not (_valid_day(self.due) and _valid_day(self.scheduled)) {
            raise ValueError("dates must be YYYY-MM-DD");
        }
        t = (root ++> Task(
            title=self.title.strip(),
            notes=self.notes,
            due=self.due,
            scheduled=self.scheduled,
            priority=_clean_priority(self.priority),
            est_minutes=max(5, self.est_minutes),
            energy=_clean_energy(self.energy),
            tags=[x.strip().lower() for x in self.tags if x.strip()],
            created_at=_now()
        ))[0];
        _set_project(t, self.project);
        for dep_id in self.depends_on {
            dep = _find_task(dep_id);
            if dep is not None {
                t +>:DependsOn:+> dep;
            }
        }
        report task_view(t, _day_or_today(self.today));
    }
}

"""Partial update: only the fields you send change.

Omitted fields keep their sentinel default ("~keep" / -1) and are left alone.
Send "" to clear a text/date field (e.g. `"due": ""`, `"project": ""`).
"""
walker:pub UpdateTask {
    has id: str;
    has title: str = KEEP,
        notes: str = KEEP,
        due: str = KEEP,
        scheduled: str = KEEP,
        priority: int = -1,
        est_minutes: int = -1,
        energy: str = KEEP,
        project: str = KEEP,
        tags: list[str] = [KEEP],
        today: str = "",
        reports: list[TaskView] = [];

    can apply with Root entry {
        t = _find_task(self.id);
        if t is None {
            raise ValueError(f"no task with id {self.id}");
        }
        if self.title != KEEP and self.title.strip() {
            t.title = self.title.strip();
        }
        if self.notes != KEEP {
            t.notes = self.notes;
        }
        if self.due != KEEP {
            if not _valid_day(self.due) {
                raise ValueError("due must be YYYY-MM-DD");
            }
            t.due = self.due;
        }
        if self.scheduled != KEEP {
            if not _valid_day(self.scheduled) {
                raise ValueError("scheduled must be YYYY-MM-DD");
            }
            t.scheduled = self.scheduled;
        }
        if self.priority != -1 {
            t.priority = _clean_priority(self.priority);
        }
        if self.est_minutes != -1 {
            t.est_minutes = max(5, self.est_minutes);
        }
        if self.energy != KEEP {
            t.energy = _clean_energy(self.energy);
        }
        if self.tags != [KEEP] {
            t.tags = [x.strip().lower() for x in self.tags if x.strip()];
        }
        if self.project != KEEP {
            _set_project(t, self.project);
        }
        report task_view(t, _day_or_today(self.today));
    }
}

walker:pub CompleteTask {
    """Mark a task done (or `done: false` to reopen it)."""
    has id: str;
    has done: bool = True,
        today: str = "",
        reports: list[TaskView] = [];

    can mark with Root entry {
        t = _find_task(self.id);
        if t is None {
            raise ValueError(f"no task with id {self.id}");
        }
        if self.done {
            t.status = "done";
            t.done_at = _now();
        } else {
            t.status = "todo";
            t.done_at = "";
        }
        report task_view(t, _day_or_today(self.today));
    }
}

walker:pub ScheduleTask {
    """Put a task on a specific day (`on: ""` unschedules it)."""
    has id: str;
    has on: str = "",
        today: str = "",
        reports: list[TaskView] = [];

    can move with Root entry {
        t = _find_task(self.id);
        if t is None {
            raise ValueError(f"no task with id {self.id}");
        }
        if not _valid_day(self.on) {
            raise ValueError("on must be YYYY-MM-DD");
        }
        t.scheduled = self.on;
        report task_view(t, _day_or_today(self.today));
    }
}

walker:pub DeleteTask {
    has id: str;
    has reports: list[str] = [];

    can remove with Root entry {
        t = _find_task(self.id);
        if t is None {
            raise ValueError(f"no task with id {self.id}");
        }
        gone = jid(t);
        del t;      # cascades to its PartOf / DependsOn edges
        report gone;
    }
}

walker:pub ListTasks {
    """Walk every task on your root and report the matching ones.

    status: "todo" | "done" | "all";  project / tag narrow further.
    """
    has status: str = "todo",
        project: str = "",
        tag: str = "",
        today: str = "",
        found: list[TaskView] = [],
        reports: list[list[TaskView]] = [];

    can start with Root entry {
        visit [-->[?:Task]];
    }

    can check with Task entry {
        if here.archived {
            skip;
        }
        if self.status != "all" and here.status != self.status {
            skip;
        }
        if self.tag and self.tag.lower() not in here.tags {
            skip;
        }
        v = task_view(here, _day_or_today(self.today));
        if self.project {
            key = self.project.lower();
            if v.project_id != self.project and v.project_name.lower() != key {
                skip;
            }
        }
        self.found.append(v);
    }

    can finish with Root exit {
        report _sort_views(self.found);
    }
}

walker:pub ClearCompleted {
    """Hide every finished task from the lists ("Clear completed").

    Cleared tasks are archived, not deleted: they still count toward project
    and goal progress. Reports how many were cleared.
    """
    has reports: list[int] = [];

    can clear with Root entry {
        n = 0;
        for t in [root-->[?:Task]] {
            if t.status == "done" and not t.archived {
                t.archived = True;
                n += 1;
            }
        }
        report n;
    }
}

walker:pub LinkDependency {
    """`task_id` depends on `depends_on_id`. Refuses links that form a cycle."""
    has task_id: str,
        depends_on_id: str;
    has remove: bool = False,
        today: str = "",
        reports: list[TaskView] = [];

    can link with Root entry {
        t = _find_task(self.task_id);
        dep = _find_task(self.depends_on_id);
        if t is None or dep is None {
            raise ValueError("both tasks must exist");
        }
        if self.remove {
            for e in [edge t ->:DependsOn:-> dep] {
                del e;
            }
        } else {
            if t == dep {
                raise ValueError("a task can't depend on itself");
            }
            # Would dep (transitively) depend on t? Then linking closes a loop.
            probe = dep spawn ReachesTask(target=jid(t));
            if probe.found {
                raise ValueError("that link would create a dependency cycle");
            }
            if not [t ->:DependsOn:-> dep] {
                t +>:DependsOn:+> dep;
            }
        }
        report task_view(t, _day_or_today(self.today));
    }
}

walker:pub ReachesTask {
    """Depth-first walk along DependsOn edges looking for `target`."""
    has target: str;
    has found: bool = False,
        seen: list[str] = [];

    can step with Task entry {
        me = jid(here);
        if me in self.seen {
            skip;
        }
        self.seen.append(me);
        if me == self.target {
            self.found = True;
            disengage;
        }
        visit :0: [here ->:DependsOn:->];
    }
}


# ================================================================ planning views

walker:pub NextActions {
    """Tasks you can start right now (not done, nothing blocking), best first."""
    has limit: int = 5,
        today: str = "",
        candidates: list[Task] = [],
        reports: list[list[TaskView]] = [];

    can start with Root entry {
        visit [-->[?:Task]];
    }

    can check with Task entry {
        if here.status == "todo" and not _is_blocked(here) {
            self.candidates.append(here);
        }
    }

    can finish with Root exit {
        day = _day_or_today(self.today);
        h = _health_for(day);
        readiness = h.readiness if h is not None else 0;
        self.candidates.sort(key=lambda t: Task : _score(t, day, readiness));
        report [task_view(t, day) for t in self.candidates[:max(1, self.limit)]];
    }
}

walker:pub PlanDay {
    """Build today's plan.

    - overdue:   tasks whose due date has passed (still open, or finished today)
    - today:     tasks scheduled or due today, plus anything finished today
    - suggested: unblocked tasks that fit the remaining capacity, ranked by
                 due date, priority and (if you have Oura data) energy fit
    Capacity is the smaller of what your readiness allows and the free time
    left between calendar events, meals and bedtime (from `now`, "HH:MM").
    Finished tasks stay in their section (crossed out) until you clear them.
    `commit: true` schedules the suggestions onto today.
    """
    has today: str = "",
        now: str = "",
        commit: bool = False,
        tasks: list[Task] = [],
        reports: list[DayPlan] = [];

    can start with Root entry {
        visit [-->[?:Task]];
    }

    can collect with Task entry {
        if not here.archived {
            self.tasks.append(here);
        }
    }

    can finish with Root exit {
        day = _day_or_today(self.today);
        h = _health_for(day);
        readiness = h.readiness if h is not None else 0;
        focus = _capacity(readiness);
        budget = day_budget(day, day, self.now, budget_context());
        capacity = min(focus, budget.free_left_minutes);

        def done_today(t: Task) -> bool {
            return t.status == "done" and t.done_at.startswith(day);
        }

        overdue = [
            t for t in self.tasks
            if t.due and t.due < day and (t.status == "todo" or done_today(t))
        ];
        on_today = [
            t for t in self.tasks
            if t not in overdue
            and ((t.scheduled == day or t.due == day) or done_today(t))
        ];
        planned = sum([t.est_minutes for t in on_today]);

        pool = [
            t for t in self.tasks
            if t.status == "todo"
            and t not in on_today
            and t not in overdue
            and not _is_blocked(t)
            and not (t.scheduled and t.scheduled > day)
        ];
        pool.sort(key=lambda t: Task : _score(t, day, readiness));

        suggested: list[Task] = [];
        room = capacity - planned - sum([t.est_minutes for t in overdue]);
        for t in pool {
            if t.est_minutes <= room {
                suggested.append(t);
                room -= t.est_minutes;
            }
        }

        if self.commit {
            for t in suggested {
                t.scheduled = day;
            }
            on_today = on_today + suggested;
            planned += sum([t.est_minutes for t in suggested]);
            suggested = [];
        }

        if h is None {
            note = "No health data for today - planning a standard day.";
        } elif readiness < 70 {
            note = f"Readiness {readiness}: lighter day, deep work pushed later.";
        } elif readiness >= 85 {
            note = f"Readiness {readiness}: strong day, deep work pulled forward.";
        } else {
            note = f"Readiness {readiness}: normal day.";
        }
        if budget.free_left_minutes < focus {
            left = budget.free_left_minutes;
            if left == 0 {
                note += f" No free time left before bed ({budget.bedtime}).";
            } else {
                note += f" Only {left // 60}h{left % 60:02d} free left before bed ({budget.bedtime}), so that's the cap.";
            }
        }

        # Overbooked? Point at the task that's easiest to move: scheduled for
        # today but not due today, deep-focus first on a tired day.
        load = planned + sum([t.est_minutes for t in overdue]);
        if load > capacity {
            movable = [t for t in on_today if t.due != day and t.status == "todo"];
            movable.sort(
                key=lambda t: Task : (
                    0 if (t.energy == "high" and 0 < readiness and readiness < 70) else 1,
                    0 - t.priority,
                    0 - t.est_minutes
                )
            );
            over = load - capacity;
            if movable {
                note += f" Over by {over} min - consider moving \"{movable[0].title}\" to tomorrow.";
            } else {
                note += f" Over by {over} min.";
            }
        }

        report DayPlan(
            day=day,
            health=health_view(h) if h is not None else None,
            capacity_minutes=capacity,
            planned_minutes=planned,
            overdue=_sort_views([task_view(t, day) for t in overdue]),
            today=_sort_views([task_view(t, day) for t in on_today]),
            suggested=[task_view(t, day) for t in suggested],
            done_today=[],
            note=note,
            wake=budget.wake,
            bedtime=budget.bedtime,
            event_minutes=budget.event_minutes,
            free_minutes=budget.free_minutes,
            free_left_minutes=budget.free_left_minutes,
            readiness_capacity=focus
        );
    }
}

walker:pub WeekView {
    """Seven days starting at `start` (default: this week's Monday)."""
    has start: str = "",
        today: str = "",
        reports: list[WeekPlan] = [];

    can build with Root entry {
        day = _day_or_today(self.today);
        if self.start {
            first = date.fromisoformat(self.start);
        } else {
            d = date.fromisoformat(day);
            first = d - timedelta(days=d.weekday());
        }
        tasks = [t for t in [root-->[?:Task]] if not t.archived];
        days: list[WeekDay] = [];
        for i in range(7) {
            cur = (first + timedelta(days=i)).isoformat();
            on_day = [
                task_view(t, day) for t in tasks
                if t.scheduled == cur or (not t.scheduled and t.due == cur)
            ];
            days.append(
                WeekDay(
                    day=cur,
                    weekday=(first + timedelta(days=i)).strftime("%a"),
                    tasks=_sort_views(on_day),
                    minutes=sum([v.est_minutes for v in on_day if v.status == "todo"])
                )
            );
        }
        unscheduled = [
            task_view(t, day) for t in tasks
            if not t.scheduled and not t.due
        ];
        report WeekPlan(
            start=first.isoformat(), days=days, unscheduled=_sort_views(unscheduled)
        );
    }
}


# ================================================================ projects & goals

walker:pub AddProject {
    has name: str;
    has color: str = "#6366f1",
        goal: str = "",
        reports: list[ProjectView] = [];

    can create with Root entry {
        if not self.name.strip() {
            raise ValueError("name is required");
        }
        p = _find_project(self.name);
        if p is None {
            p = (root ++> Project(name=self.name.strip(), color=self.color, created_at=_now()))[0];
        }
        if self.goal.strip() {
            g = _find_goal(self.goal);
            if g is None {
                g = (root ++> Goal(title=self.goal.strip(), created_at=_now()))[0];
            }
            for e in [edge p ->:Supports:->] {
                del e;
            }
            p +>:Supports:+> g;
        }
        report project_view(p);
    }
}

walker:pub ListProjects {
    has include_archived: bool = False,
        reports: list[list[ProjectView]] = [];

    can gather with Root entry {
        report [
            project_view(p) for p in [root-->[?:Project]]
            if self.include_archived or not p.archived
        ];
    }
}

walker:pub AddGoal {
    has title: str;
    has target_date: str = "",
        reports: list[GoalView] = [];

    can create with Root entry {
        if not self.title.strip() {
            raise ValueError("title is required");
        }
        if not _valid_day(self.target_date) {
            raise ValueError("target_date must be YYYY-MM-DD");
        }
        g = _find_goal(self.title);
        if g is None {
            g = (root ++> Goal(title=self.title.strip(), created_at=_now()))[0];
        }
        g.target_date = self.target_date or g.target_date;
        report goal_view(g);
    }
}

walker:pub ListGoals {
    has reports: list[list[GoalView]] = [];

    can gather with Root entry {
        report [goal_view(g) for g in [root-->[?:Goal]]];
    }
}
