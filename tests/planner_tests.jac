"""Walker-level tests for the planner graph.

Run with:  jac test

Tests run on the local test root (not any signed-in user's root), and each
test starts by clearing that root, so reruns are repeatable and your real
planner data is never touched.
"""

import from services.models { Task, Project, Goal, HealthSnapshot, TaskView }
import from services.planner {
    AddTask, CompleteTask, LinkDependency, NextActions, PlanDay, ListTasks, DeleteTask
}
import from services.integrations { SyncCanvas, SyncOura }

glob DAY: str = "2026-09-28";

def reset() {
    for n in [root-->] {
        if isinstance(n, Task) or isinstance(n, Project) or isinstance(n, Goal) or isinstance(n, HealthSnapshot) {
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
