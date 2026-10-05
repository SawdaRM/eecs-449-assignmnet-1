"""Walker-level tests for the planner graph.

Run with:  jac test

Tests run on the local test root (not any signed-in user's root), and each
test starts by clearing that root, so reruns are repeatable and your real
planner data is never touched.
"""

import from services.models { Task, Project, Goal, HealthSnapshot, CalEvent, CalSettings, TaskView }
import from services.planner {
    AddTask, CompleteTask, LinkDependency, NextActions, PlanDay, ListTasks, DeleteTask,
    ClearCompleted, WeekView
}
import from services.integrations { SyncCanvas, SyncOura }
import from services.calendar {
    SyncCalendar, CalendarWeekView, SaveCalendarSettings, parse_calendar
}
import from datetime { datetime }

glob DAY: str = "2026-09-28";

def reset() {
    for n in [root-->] {
        if isinstance(n, Task) or isinstance(n, Project) or isinstance(n, Goal) or isinstance(n, HealthSnapshot)
            or isinstance(n, CalEvent) or isinstance(n, CalSettings) {
            del n;
        }
    }
}

def add(title: str, due: str = "", minutes: int = 30) -> TaskView {
    return (root spawn AddTask(title=title, due=due, est_minutes=minutes, today=DAY)).reports[0];
}

def titles(views: list[TaskView]) -> list[str] {
    return [v.title for v in views];
}

test "add and complete a task" {
    reset();
    t = add("t-basic");
    assert t.status == "todo";
    done = (root spawn CompleteTask(id=t.id, today=DAY)).reports[0];
    assert done.status == "done";
    assert done.done_at != "";
    reopened = (root spawn CompleteTask(id=t.id, done=False, today=DAY)).reports[0];
    assert reopened.status == "todo";
}

test "dependencies block until done" {
    reset();
    first = add("t-first");
    second = add("t-second");
    linked = (root spawn LinkDependency(task_id=second.id, depends_on_id=first.id, today=DAY)).reports[0];
    assert linked.blocked;
    assert linked.blocked_by == ["t-first"];
    nxt = titles((root spawn NextActions(limit=50, today=DAY)).reports[0]);
    assert "t-first" in nxt;
    assert "t-second" not in nxt;
    root spawn CompleteTask(id=first.id, today=DAY);
    assert "t-second" in titles((root spawn NextActions(limit=50, today=DAY)).reports[0]);
}

test "dependency cycles are rejected" {
    reset();
    a = add("t-cycle-a");
    b = add("t-cycle-b");
    c = add("t-cycle-c");
    root spawn LinkDependency(task_id=a.id, depends_on_id=b.id, today=DAY);
    root spawn LinkDependency(task_id=b.id, depends_on_id=c.id, today=DAY);
    try {
        root spawn LinkDependency(task_id=c.id, depends_on_id=a.id, today=DAY);
        assert False, "c -> a should close a cycle";
    } except ValueError {
        assert True;
    }
}

test "day plan respects capacity and puts overdue first" {
    reset();
    add("t-overdue", due="2026-09-01");
    for i in range(10) {
        add(f"t-big-{i}", minutes=100);
    }
    plan = (root spawn PlanDay(today=DAY)).reports[0];
    assert titles(plan.overdue) == ["t-overdue"];
    used = sum([v.est_minutes for v in (plan.overdue + plan.today + plan.suggested)]);
    assert used <= plan.capacity_minutes;
    committed = (root spawn PlanDay(today=DAY, commit=True)).reports[0];
    assert len(committed.suggested) == 0;
    assert len(committed.today) == len(plan.suggested);
}

test "syncs are idempotent" {
    reset();
    first = (root spawn SyncCanvas(mock=True, today=DAY)).reports[0];
    again = (root spawn SyncCanvas(mock=True, today=DAY)).reports[0];
    assert first.created == 5;
    assert again.created == 0;
    o1 = (root spawn SyncOura(mock=True, days=3, today=DAY)).reports[0];
    o2 = (root spawn SyncOura(mock=True, days=3, today=DAY)).reports[0];
    assert o1.created == 3 and o2.created == 0 and o2.updated == 3;
}

test "delete removes the task" {
    reset();
    t = add("t-delete-me");
    root spawn DeleteTask(id=t.id);
    remaining = titles((root spawn ListTasks(status="all", today=DAY)).reports[0]);
    assert "t-delete-me" not in remaining;
}

test "demo week loads and re-running replaces it" {
    reset();
    import from services.demo { LoadDemo }
    first = (root spawn LoadDemo(today=DAY)).reports[0];
    again = (root spawn LoadDemo(today=DAY)).reports[0];
    tasks = (root spawn ListTasks(status="all", today=DAY)).reports[0];
    assert first.created == again.created;
    assert again.updated == first.created;       # all old demo tasks replaced
    assert len(tasks) == first.created;
    blocked = [t for t in tasks if t.blocked];
    assert len(blocked) > 0;                     # dependency chains present
}

test "finished tasks stay in place until cleared" {
    reset();
    t = (root spawn AddTask(title="t-stays", scheduled=DAY, today=DAY)).reports[0];
    add("t-other");
    root spawn CompleteTask(id=t.id, today=DAY);
    plan = (root spawn PlanDay(today=DAY)).reports[0];
    assert "t-stays" in titles(plan.today);          # still listed, just done
    week = (root spawn WeekView(today=DAY)).reports[0];
    assert "t-stays" in [v.title for d in week.days for v in d.tasks];
    root spawn CompleteTask(id=t.id, done=False, today=DAY);   # un-cross it
    root spawn CompleteTask(id=t.id, today=DAY);
    cleared = (root spawn ClearCompleted()).reports[0];
    assert cleared == 1;
    assert "t-stays" not in titles((root spawn ListTasks(status="all", today=DAY)).reports[0]);
    assert "t-stays" not in titles((root spawn PlanDay(today=DAY)).reports[0].today);
    assert "t-other" in titles((root spawn ListTasks(status="all", today=DAY)).reports[0]);
}

glob ICS: str = "\n".join([
    "BEGIN:VCALENDAR",
    # weekly Mon/Wed class, 4 times, with one Wednesday skipped
    "BEGIN:VEVENT", "UID:class", "SUMMARY:Lecture", "DTSTART:20260928T103000", "DTEND:20260928T120000",
    "RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4", "EXDATE:20260930T103000", "END:VEVENT",
    # one occurrence moved an hour later
    "BEGIN:VEVENT", "UID:class", "SUMMARY:Lecture (moved)", "RECURRENCE-ID:20261005T103000",
    "DTSTART:20261005T113000", "DTEND:20261005T130000", "END:VEVENT",
    # a cancelled event and an all-day event
    "BEGIN:VEVENT", "UID:gone", "SUMMARY:Cancelled", "STATUS:CANCELLED", "DTSTART:20260929T090000", "DTEND:20260929T100000", "END:VEVENT",
    "BEGIN:VEVENT", "UID:fair", "SUMMARY:Career fair", "DTSTART;VALUE=DATE:20260929", "DTEND;VALUE=DATE:20260930", "END:VEVENT",
    "END:VCALENDAR"
]);

test "calendar feed: repeats, skipped and moved occurrences" {
    occs = parse_calendar(ICS, datetime(2026, 9, 28), datetime(2026, 10, 12));
    lectures = sorted([o.start.strftime("%m-%d %H:%M") + " " + o.title for o in occs if o.uid == "class"]);
    # 4 occurrences: 09-28, (09-30 skipped), 10-05 moved, 10-07 -> COUNT counts the skipped one
    assert lectures == ["09-28 10:30 Lecture", "10-05 11:30 Lecture (moved)", "10-07 10:30 Lecture"], lectures;
    assert "Cancelled" not in [o.title for o in occs];
    fair = [o for o in occs if o.uid == "fair"];
    assert len(fair) == 1 and fair[0].all_day;
}

test "calendar sync is idempotent" {
    reset();
    first = (root spawn SyncCalendar(mock=True, today=DAY)).reports[0];
    again = (root spawn SyncCalendar(mock=True, today=DAY)).reports[0];
    assert first.created > 10;
    assert again.created == 0 and again.updated == 0;
}

test "free time = waking day minus events and meals" {
    reset();
    root spawn SaveCalendarSettings(sleep_need_hours=8.0);
    # No Oura data: bed 23:00, up 07:00 -> 16h awake, minus 2h15 of meals.
    week = (root spawn CalendarWeekView(start=DAY, today=DAY)).reports[0];
    d = week.days[0];
    assert (d.wake, d.bedtime) == ("07:00", "23:00");
    assert d.awake_minutes == 960 and d.meal_minutes == 135;
    assert d.free_minutes == 960 - 135;
    # A 2h exam over lunch time pushes lunch to right after it.
    root ++> CalEvent(uid="x", title="Exam", day=DAY, start="12:00", end="14:00");
    d = (root spawn CalendarWeekView(start=DAY, today=DAY)).reports[0].days[0];
    assert d.event_minutes == 120 and d.meal_minutes == 135;
    assert [(b.start, b.end) for b in d.blocks if b.label == "Lunch"] == [("14:00", "14:45")];
    assert d.free_minutes == 960 - 120 - 135;
    # Late in the day only what's left counts, and the plan is capped by it.
    late = (root spawn CalendarWeekView(start=DAY, today=DAY, now="21:00")).reports[0].days[0];
    assert late.free_left_minutes == 120;    # 21:00 -> 23:00
    add("t-long", minutes=180);
    plan = (root spawn PlanDay(today=DAY, now="21:00")).reports[0];
    assert plan.capacity_minutes == 120;
    assert "t-long" not in titles(plan.suggested);
}

test "Oura's optimal bedtime sets the day's end" {
    reset();
    root ++> HealthSnapshot(day=DAY, readiness=80, wake="06:30", optimal_bedtime="22:15");
    d = (root spawn CalendarWeekView(start=DAY, today=DAY)).reports[0].days[0];
    assert (d.wake, d.bedtime, d.bedtime_source) == ("06:30", "22:15", "oura");
}
