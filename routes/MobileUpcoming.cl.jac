"""Mobile Upcoming: the next seven days, grouped by day, plus anything unscheduled."""

import from ..components.api { week_view, set_done, today_iso, friendly_day, month_day, err_text }
import from ..components.TaskRow { TaskRow }
import from ..components.Toast { Toast }
import from ..components.ClearDoneButton { ClearDoneButton }
sv import from ..services.planner { TaskView, WeekPlan }

def:pub MobileUpcoming -> JsxElement {
    has week: WeekPlan | None = None,
        toast: str = "";

    async def load {
        # Start the 7-day window today (not Monday) so it's always "what's next".
        w = await week_view(today_iso());
        week = w;
    }

    async can with entry {
        try {
            await load();
        } except Exception as e {
            toast = err_text(e);
        }
    }

    async def after_clear(msg: str) {
        toast = msg;
        await load();
    }

    async def toggle(t: TaskView) {
        try {
            await set_done(t.id, t.status != "done");
            await load();
        } except Exception as e {
            toast = err_text(e);
        }
    }

    days = week.days if week is not None else [];
    unscheduled = week.unscheduled if week is not None else [];

    return
        <>
            <header className="m-head">
                <h1 className="grow">Upcoming</h1>
                <ClearDoneButton onDone={after_clear} small={True}/>
            </header>
            <div className="m-body">
                {for d in days {
                    open_tasks = d.tasks;
                    if len(open_tasks) > 0 {
                        <section key={d.day} className="section">
                            <h3>
                                {friendly_day(d.day).capitalize() if friendly_day(d.day) in ["today", "tomorrow"] else d.weekday + " " + month_day(d.day)}
                            </h3>
                            {for t in open_tasks {
                                <TaskRow key={t.id} task={t} onToggle={toggle} showScheduled={False}/>
                            }}
                        </section>
                    }
                }}
                {if len(unscheduled) > 0 {
                    <section key="s55" className="section">
                        <h3>Someday</h3>
                        {for t in unscheduled {
                            <TaskRow key={t.id} task={t} onToggle={toggle}/>
                        }}
                    </section>
                }}
                {if week is not None and len(unscheduled) == 0 and len([t for d in days for t in d.tasks]) == 0 {
                    <p key="s63" className="muted">Nothing coming up. Enjoy it.</p>
                }}
            </div>
            <Toast message={toast} onClear={lambda { toast = ""; }}/>
        </>;
}
