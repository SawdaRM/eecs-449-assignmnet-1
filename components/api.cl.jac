"""Client-side data layer shared by the web and mobile UIs.

Every function here spawns one of the server walkers (the same ones the CLI
calls over REST) and returns its typed report. Pages never talk to the
server directly - they call these, so the web and mobile apps stay in sync
with each other and with the CLI.
"""

sv import from ..services.planner {
    AddTask, UpdateTask, CompleteTask, ScheduleTask, DeleteTask, ListTasks, ClearCompleted,
    LinkDependency, NextActions, PlanDay, WeekView,
    AddProject, ListProjects, AddGoal, ListGoals,
    TaskView, ProjectView, GoalView, HealthView, DayPlan, WeekPlan, WeekDay
}
sv import from ..services.integrations { SyncCanvas, SyncOura, GetHealth, SyncResult }
sv import from ..services.demo { LoadDemo }


# ================================================================ dates (local time)

glob MONTHS: list[str] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
     DAYS: list[str] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

def pad2(n: int) -> str {
    return ("0" + str(n))[-2:];
}

def _iso(d: any) -> str {
    return f"{d.getFullYear()}-{pad2((d.getMonth() as int) + 1)}-{pad2(d.getDate() as int)}";
}

def _parse(day: str) -> any {
    parts = day.split("-");
    return new(Date, int(parts[0]), int(parts[1]) - 1, int(parts[2]));  # jac:ignore[W2001]
}

def:pub today_iso() -> str {
    return _iso(new(Date));  # jac:ignore[W2001]
}

def:pub add_days(day: str, n: int) -> str {
    d = _parse(day);
    d.setDate((d.getDate() as int) + n);
    return _iso(d);
}

def:pub monday_of(day: str) -> str {
    d = _parse(day);
    back = ((d.getDay() as int) + 6) % 7;
    return add_days(day, 0 - back);
}

def:pub weekday_short(day: str) -> str {
    return DAYS[_parse(day).getDay() as int];
}

def:pub month_day(day: str) -> str {
    d = _parse(day);
    return f"{MONTHS[d.getMonth() as int]} {d.getDate()}";
}

"""'today', 'tomorrow', 'Fri', or 'Oct 3' relative to today."""
def:pub friendly_day(day: str) -> str {
    if not day {
        return "";
    }
    today = today_iso();
    if day == today {
        return "today";
    }
    if day == add_days(today, 1) {
        return "tomorrow";
    }
    if day == add_days(today, -1) {
        return "yesterday";
    }
    if day > today and day <= add_days(today, 6) {
        return weekday_short(day);
    }
    return month_day(day);
}

def:pub long_day(day: str) -> str {
    full = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    d = _parse(day);
    return f"{full[d.getDay() as int]}, {MONTHS[d.getMonth() as int]} {d.getDate()}";
}

def:pub hours(minutes: int) -> str {
    if minutes < 60 {
        return f"{minutes}m";
    }
    rest = minutes % 60;
    return f"{(minutes - rest) / 60}h{pad2(rest) if rest else ''}";
}

"""Readable message from a failed walker call."""
def:pub err_text(e: any) -> str {
    msg = str(e.message if e and e.message else e);
    return msg.replace("Error: ", "")[:200];
}


# ================================================================ tasks

async def:pub add_task(
    title: str,
    due: str,
    scheduled: str,
    project: str,
    priority: int,
    est_minutes: int,
    energy: str
) -> TaskView {
    result = root spawn AddTask(
        title=title,
        due=due,
        scheduled=scheduled,
        project=project,
        priority=priority,
        est_minutes=est_minutes,
        energy=energy,
        today=today_iso()
    );
    return result.reports[0];
}

async def:pub update_task(
    id: str,
    title: str,
    notes: str,
    due: str,
    scheduled: str,
    project: str,
    priority: int,
    est_minutes: int,
    energy: str,
    tags: list[str]
) -> TaskView {
    result = root spawn UpdateTask(
        id=id,
        title=title,
        notes=notes,
        due=due,
        scheduled=scheduled,
        project=project,
        priority=priority,
        est_minutes=est_minutes,
        energy=energy,
        tags=tags,
        today=today_iso()
    );
    return result.reports[0];
}

async def:pub set_done(id: str, done: bool) -> TaskView {
    result = root spawn CompleteTask(id=id, done=done, today=today_iso());
    return result.reports[0];
}

async def:pub schedule_task(id: str, on: str) -> TaskView {
    result = root spawn ScheduleTask(id=id, on=on, today=today_iso());
    return result.reports[0];
}

async def:pub delete_task(id: str) -> str {
    result = root spawn DeleteTask(id=id);
    return result.reports[0];
}

"""Hide all finished tasks (they're archived, so progress still counts them)."""
async def:pub clear_completed() -> int {
    result = root spawn ClearCompleted();
    return result.reports[0];
}

async def:pub list_tasks(status: str) -> list[TaskView] {
    result = root spawn ListTasks(status=status, today=today_iso());
    return result.reports[0];
}

async def:pub link_dependency(task_id: str, depends_on_id: str, remove: bool) -> TaskView {
    result = root spawn LinkDependency(
        task_id=task_id, depends_on_id=depends_on_id, remove=remove, today=today_iso()
    );
    return result.reports[0];
}

async def:pub next_actions(limit: int) -> list[TaskView] {
    result = root spawn NextActions(limit=limit, today=today_iso());
    return result.reports[0];
}


# ================================================================ planning views

async def:pub plan_day(commit: bool) -> DayPlan {
    result = root spawn PlanDay(today=today_iso(), commit=commit);
    return result.reports[0];
}

async def:pub week_view(start: str) -> WeekPlan {
    result = root spawn WeekView(start=start, today=today_iso());
    return result.reports[0];
}


# ================================================================ projects & goals

async def:pub list_projects() -> list[ProjectView] {
    result = root spawn ListProjects();
    return result.reports[0];
}

async def:pub add_project(name: str, goal: str) -> ProjectView {
    result = root spawn AddProject(name=name, goal=goal);
    return result.reports[0];
}

async def:pub list_goals() -> list[GoalView] {
    result = root spawn ListGoals();
    return result.reports[0];
}

async def:pub add_goal(title: str, target_date: str) -> GoalView {
    result = root spawn AddGoal(title=title, target_date=target_date);
    return result.reports[0];
}


# ================================================================ integrations

async def:pub sync_canvas() -> SyncResult {
    result = root spawn SyncCanvas(today=today_iso());
    return result.reports[0];
}

async def:pub sync_oura() -> SyncResult {
    result = root spawn SyncOura(today=today_iso());
    return result.reports[0];
}

"""Fill the planner with a realistic demo week (plus mock Canvas + Oura)."""
async def:pub load_demo() -> str {
    result = root spawn LoadDemo(today=today_iso());
    first: SyncResult = result.reports[0];
    c = await sync_canvas();
    o = await sync_oura();
    return f"{first.message} {c.message} {o.message}";
}

async def:pub health(days: int) -> list[HealthView] {
    result = root spawn GetHealth(days=days, today=today_iso());
    return result.reports[0];
}


# ================================================================ which UI

"""Phones (and the native Capacitor shell) get the mobile UI by default.

Choosing a view explicitly (the "desktop view" / "mobile view" links) is
remembered in localStorage.
"""
def:pub prefers_mobile() -> bool {
    if (window as any).Capacitor {
        return True;
    }
    choice = "";
    try {
        choice = localStorage.getItem("planner_view") or "";
    } except Exception {
        choice = "";
    }
    if choice {
        return choice == "mobile";
    }
    return window.innerWidth < 700;
}

def:pub remember_view(view: str) {
    try {
        localStorage.setItem("planner_view", view);
    } except Exception {
        return;
    }
}


"""`sep.join(items)` - Python's str.join isn't available in client Jac."""
def:pub join_strs(items: list[str], sep: str) -> str {
    out = "";
    for (i, s) in enumerate(items) {
        out = out + (sep if i > 0 else "") + s;
    }
    return out;
}


"""There are no accounts. A leftover login token from an older version would
make the server use that user's private graph instead of the shared plan,
so remove it before any request goes out."""
def:pub forget_login() {
    try {
        localStorage.removeItem("jac_token");
    } except Exception {
        return;
    }
}
