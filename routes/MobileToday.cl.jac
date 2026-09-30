"""Mobile Today: readiness, then everything to do today. Tap the circle to finish."""

import from ..components.api { plan_day, set_done, long_day, err_text }
import from ..components.TaskRow { TaskRow }
import from ..components.HealthCard { HealthCard }
import from ..components.Toast { Toast }
import from ..components.ClearDoneButton { ClearDoneButton }
sv import from ..services.planner { TaskView, DayPlan }

def:pub MobileToday -> JsxElement {
    has plan: DayPlan | None = None,
        busy: bool = False,
        toast: str = "";

    async def load {
        p = await plan_day(False);
        plan = p;
    }

    async can with entry {
        try {
            await load();
        } except Exception as e {
            toast = err_text(e);
        }
    }

    async def toggle(t: TaskView) {
        try {
            await set_done(t.id, t.status != "done");
            if t.status != "done" {
                toast = "Done: " + t.title;
            }
            await load();
        } except Exception as e {
            toast = err_text(e);
        }
    }

    async def after_clear(msg: str) {
        toast = msg;
        await load();
    }

    async def accept {
        busy = True;
        try {
            p = await plan_day(True);
            plan = p;
            toast = "Planned your day";
        } except Exception as e {
            toast = err_text(e);
        }
        busy = False;
    }

    if plan is None {
        return <div className="m-head"><h1>Today</h1></div>;
    }

    shown: list[TaskView] = plan.overdue + plan.today;
    left = len([t for t in shown if t.status == "todo"]);

    return
        <>
            <header className="m-head">
                <div className="grow">
                    <div className="date">{long_day(plan.day)}</div>
                    <h1>{"All clear" if left == 0 else f"{left} to do today"}</h1>
                </div>
                <ClearDoneButton onDone={after_clear} small={True}/>
            </header>
            <div className="m-body">
                <div className="section"><HealthCard plan={plan}/></div>
                {if plan.overdue {
                    <section key="s67" className="section">
                        <h3 style={{"color": "var(--danger)"}}>Overdue</h3>
                        {for t in plan.overdue {
                            <TaskRow key={t.id} task={t} onToggle={toggle}/>
                        }}
                    </section>
                }}
                <section className="section">
                    <h3>Today</h3>
                    {if len(plan.today) == 0 {
                        <p key="s77" className="muted small">Nothing scheduled.</p>
                    }}
                    {for t in plan.today {
                        <TaskRow key={t.id} task={t} onToggle={toggle} showScheduled={False}/>
                    }}
                </section>
                {if plan.suggested {
                    <section key="s84" className="section">
                        <h3>Suggested for today</h3>
                        {for t in plan.suggested {
                            <TaskRow key={t.id} task={t} onToggle={toggle}/>
                        }}
                        <button className="primary" style={{"width": "100%", "marginTop": "10px", "padding": "12px"}} onClick={accept} disabled={busy}>
                            {"Planning…" if busy else "Plan my day with these"}
                        </button>
                    </section>
                }}
                {if plan.done_today {
                    <section key="s95" className="section">
                        <h3 style={{"color": "var(--ok)"}}>{"Done · " + str(len(plan.done_today))}</h3>
                        {for t in plan.done_today {
                            <TaskRow key={t.id} task={t} onToggle={toggle}/>
                        }}
                    </section>
                }}
            </div>
            <Toast message={toast} onClear={lambda { toast = ""; }}/>
        </>;
}
