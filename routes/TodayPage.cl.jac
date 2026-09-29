"""Web Today: the day plan from PlanDay, with one click to accept suggestions."""

import from ..components.api { plan_day, list_tasks, list_projects, set_done, long_day, today_iso, hours, err_text }
import from ..components.TaskRow { TaskRow }
import from ..components.TaskEditor { TaskEditor }
import from ..components.HealthCard { HealthCard }
import from ..components.SyncButton { SyncButton }
import from ..components.Toast { Toast }
sv import from ..services.planner { TaskView, ProjectView, DayPlan }

def:pub TodayPage -> JsxElement {
    has plan: DayPlan | None = None,
        allTasks: list[TaskView] = [],
        projects: list[ProjectView] = [],
        editing: TaskView | None = None,
        busy: bool = False,
        toast: str = "";

    async def load {
        p = await plan_day(False);
        ts = await list_tasks("all");
        ps = await list_projects();
        plan = p;
        allTasks = ts;
        projects = ps;
    }

    async can with entry {
        try {
            await load();
        } except Exception as e {
            toast = err_text(e);
        }
    }

    async def accept {
        busy = True;
        try {
            p = await plan_day(True);
            plan = p;
            toast = "Suggestions added to today";
        } except Exception as e {
            toast = err_text(e);
        }
        busy = False;
    }

    async def toggle(t: TaskView) {
        try {
            await set_done(t.id, t.status != "done");
            await load();
        } except Exception as e {
            toast = err_text(e);
        }
    }

    async def after_edit(msg: str) {
        toast = msg;
        await load();
    }

    def open(t: TaskView) {
        editing = t;
    }

    if plan is None {
        return <p className="muted">Loading today…</p>;
    }

    return
        <div>
            <div className="page-head">
                <h1>{long_day(plan.day)}</h1>
                <span className="spacer"/>
                <SyncButton onDone={after_edit}/>
            </div>
            <div className="split">
                <div>
                    {if plan.overdue {
                        <section key="s79" className="section">
                            <h3 style={{"color": "var(--danger)"}}>Overdue</h3>
                            {for t in plan.overdue {
                                <TaskRow key={t.id} task={t} onToggle={toggle} onOpen={open}/>
                            }}
                        </section>
                    }}
                    <section className="section">
                        <h3>Today <span className="faint">{hours(plan.planned_minutes)}</span></h3>
                        {if len(plan.today) == 0 {
                            <p key="s89" className="muted small">Nothing scheduled yet. Accept the suggestions below, or drag tasks onto today on the Week board.</p>
                        }}
                        {for t in plan.today {
                            <TaskRow key={t.id} task={t} onToggle={toggle} onOpen={open} showScheduled={False}/>
                        }}
                    </section>
                    {if plan.suggested {
                        <section key="s96" className="section">
                            <h3>
                                Suggested
                                <span className="spacer"/>
                                <button className="primary small" onClick={accept} disabled={busy}>
                                    {"Adding…" if busy else "Add all to today"}
                                </button>
                            </h3>
                            <p className="muted small" style={{"marginTop": "0"}}>
                                Unblocked tasks ranked by due date, priority and how much energy they need, sized to fit your capacity.
                            </p>
                            {for t in plan.suggested {
                                <TaskRow key={t.id} task={t} onToggle={toggle} onOpen={open}/>
                            }}
                        </section>
                    }}
                    {if plan.done_today {
                        <section key="s113" className="section">
                            <h3 style={{"color": "var(--ok)"}}>{"Done today · " + str(len(plan.done_today))}</h3>
                            {for t in plan.done_today {
                                <TaskRow key={t.id} task={t} onToggle={toggle} onOpen={open}/>
                            }}
                        </section>
                    }}
                </div>
                <aside>
                    <HealthCard plan={plan}/>
                </aside>
            </div>
            {if editing is not None {
                <TaskEditor
                    key={editing.id}
                    task={editing}
                    allTasks={allTasks}
                    projects={projects}
                    onClose={lambda { editing = None; }}
                    onSaved={after_edit}
                />
            }}
            <Toast message={toast} onClear={lambda { toast = ""; }}/>
        </div>;
}
