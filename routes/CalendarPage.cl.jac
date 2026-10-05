"""Web Calendar: the week as timelines (sleep, meals, Google Calendar events,
free time), with each day's free time compared to its to-do load."""

import from "@jac/runtime" { Link }
import from ..components.api {
    calendar_week, sync_calendar, set_done, today_iso, now_hhmm, monday_of, add_days,
    month_day, hours, clock, to_min, err_text
}
import from ..components.DayTimeline { DayTimeline, night_min }
import from ..components.CalendarSettings { CalendarSettings }
import from ..components.Toast { Toast }
sv import from ..services.calendar { CalendarWeek, DayBudget }
sv import from ..services.planner { TaskView }

def:pub CalendarPage -> JsxElement {
    has start: str = monday_of(today_iso()),
        week: CalendarWeek | None = None,
        settingsOpen: bool = False,
        syncing: bool = False,
        toast: str = "";

    today = today_iso();

    async def load {
        w = await calendar_week(start);
        week = w;
    }

    async can with [start] entry {
        try {
            await load();
        } except Exception as e {
            toast = err_text(e);
        }
    }

    async def sync(e: MouseEvent) {
        syncing = True;
        try {
            r = await sync_calendar();
            toast = r.message;
            await load();
        } except Exception as err {
            toast = err_text(err);
        }
        syncing = False;
    }

    async def toggle(t: TaskView) {
        try {
            await set_done(t.id, t.status != "done");
            await load();
        } except Exception as err {
            toast = err_text(err);
        }
    }

    async def after_settings(msg: str) {
        toast = msg;
        await load();
    }

    if week is None {
        return <p className="muted">Loading calendar…</p>;
    }

    days: list[DayBudget] = week.days;
    # One shared vertical scale: from the earliest wake-up to the latest bedtime.
    # (min()/max() over a list don't translate to the browser, so loop.)
    earliest = 1440;
    latest = 0;
    for d in days {
        earliest = to_min(d.wake) if to_min(d.wake) < earliest else earliest;
        latest = night_min(d.bedtime) if night_min(d.bedtime) > latest else latest;
    }
    grid_start = max(0, earliest - earliest % 60 - 60);
    grid_end = min(1560, latest - latest % 60 + 90);
    scale = 0.75;
    now_min = to_min(now_hhmm());
    hour_marks = [m for m in range(grid_start, grid_end + 1) if m % 60 == 0];

    free_total = sum([d.free_left_minutes if d.day == today else (d.free_minutes if d.day > today else 0) for d in days]);
    todo_total = sum([d.task_minutes for d in days if d.day >= today]);

    def day_head(d: DayBudget) -> JsxElement {
        avail = d.free_left_minutes if d.day == today else d.free_minutes;
        past = d.day < today;
        over = (not past) and d.task_minutes > avail;
        pct = min(100, int(d.task_minutes * 100 / avail)) if avail > 0 else (100 if d.task_minutes else 0);
        open_tasks = [t for t in d.tasks if t.status == "todo"];
        return
            <div className={"cal-head" + (" today" if d.day == today else "") + (" past" if past else "")}>
                <div className="row" style={{"alignItems": "baseline"}}>
                    <span className="day">{d.weekday}</span>
                    <span className="muted small">{month_day(d.day)}</span>
                </div>
                <div className="free-num">{hours(avail) if not past else "–"}</div>
                <div className="small muted">
                    {("free left today" if d.day == today else "free") if not past else "past"}
                </div>
                {if not past {
                    <div key="m" style={{"marginTop": "6px"}}>
                        <div className={"meter over" if over else "meter"}><div style={{"width": str(pct) + "%"}}/></div>
                        <div className="small" style={{"marginTop": "3px", "color": "var(--danger)" if over else "var(--muted)"}}>
                            {(hours(d.task_minutes) + " of to-dos") if d.task_minutes else "No to-dos"}
                            {(" · over by " + hours(d.task_minutes - avail)) if over else ""}
                        </div>
                    </div>
                }}
                {for ev in d.all_day {
                    <div key={ev.id} className="pill allday" title={ev.title}>{ev.title}</div>
                }}
                {for t in open_tasks[:4] {
                    <div key={t.id} className="cal-task">
                        <button
                            className={"check" + (" on" if t.status == "done" else "")}
                            onClick={lambda e: MouseEvent { toggle(t); }}
                            aria-label={"Mark done: " + t.title}
                            title="Mark done"
                        />
                        <span className="grow" title={t.title}>{t.title}</span>
                        <span className="faint">{hours(t.est_minutes)}</span>
                    </div>
                }}
                {if len(open_tasks) > 4 {
                    <Link key="more" to="/" className="small">{"+" + str(len(open_tasks) - 4) + " more on the board"}</Link>
                }}
            </div>;
    }

    return
        <div>
            <div className="page-head">
                <h1>{"Week of " + month_day(start)}</h1>
                <div className="row">
                    <button className="small" onClick={lambda e: MouseEvent { start = add_days(start, -7); }}>← Prev</button>
                    <button className="small" onClick={lambda e: MouseEvent { start = monday_of(today_iso()); }}>This week</button>
                    <button className="small" onClick={lambda e: MouseEvent { start = add_days(start, 7); }}>Next →</button>
                </div>
                <span className="muted small">
                    {f"{hours(free_total)} free · {hours(todo_total)} of to-dos ahead this week"}
                </span>
                <span className="spacer"/>
                <button onClick={lambda e: MouseEvent { settingsOpen = True; }}>⚙ Settings</button>
                <button onClick={sync} disabled={syncing}>{"Syncing…" if syncing else "⟳ Sync calendar"}</button>
            </div>

            {if not week.connected {
                <div key="connect" className="card row wrap" style={{"marginBottom": "14px", "background": "var(--accent-soft)"}}>
                    <div className="grow">
                        <h2>{"Showing a sample calendar" if week.source == "mock" else "No calendar yet"}</h2>
                        <div className="small muted">Connect your Google Calendar to plan around your real classes, meetings and plans.</div>
                    </div>
                    <button className="primary" onClick={lambda e: MouseEvent { settingsOpen = True; }}>Connect Google Calendar</button>
                </div>
            }}

            <div className="cal-legend small muted">
                <span><i className="sw event"/>Event</span>
                <span><i className="sw meal"/>Meal</span>
                <span><i className="sw free"/>Free for to-dos</span>
                <span><i className="sw sleep"/>Sleep</span>
                {if week.last_synced {
                    <span key="ls" className="faint">{"Synced " + week.last_synced.replace("T", " ")[:16]}</span>
                }}
            </div>

            <div className="cal-week">
                <div className="cal-corner"/>
                {for d in days {
                    <div key={"h" + d.day}>{day_head(d)}</div>
                }}
                <div className="cal-hours" style={{"height": str(int((grid_end - grid_start) * scale)) + "px"}}>
                    {for m in hour_marks {
                        <span key={str(m)} style={{"top": str(int((m - grid_start) * scale)) + "px"}}>{clock(str((m % 1440) / 60) + ":00")}</span>
                    }}
                </div>
                {for d in days {
                    <div key={"t" + d.day} className={"cal-col" + (" today" if d.day == today else "")}>
                        <DayTimeline
                            day={d}
                            gridStart={grid_start}
                            gridEnd={grid_end}
                            scale={scale}
                            nowMin={now_min if d.day == today else -1}
                            compact={True}
                        />
                    </div>
                }}
            </div>

            {if settingsOpen {
                <CalendarSettings onClose={lambda { settingsOpen = False; }} onSaved={after_settings}/>
            }}
            <Toast message={toast} onClear={lambda { toast = ""; }}/>
        </div>;
}
