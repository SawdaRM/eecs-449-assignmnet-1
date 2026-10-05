"""Mobile Calendar: one day's timeline and how much free time it leaves.
Swipe through the week with the day chips."""

import from ..components.api {
    calendar_week, sync_calendar, today_iso, now_hhmm, monday_of, add_days,
    long_day, hours, clock, to_min, err_text
}
import from ..components.DayTimeline { DayTimeline, night_min }
import from ..components.CalendarSettings { CalendarSettings }
import from ..components.Toast { Toast }
sv import from ..services.calendar { CalendarWeek, DayBudget }

def:pub MobileCalendar -> JsxElement {
    has day: str = today_iso(),
        week: CalendarWeek | None = None,
        settingsOpen: bool = False,
        syncing: bool = False,
        toast: str = "";

    today = today_iso();
    start = monday_of(day);

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

    async def after_settings(msg: str) {
        toast = msg;
        await load();
    }

    picked: list[DayBudget] = [d for d in week.days if d.day == day] if week is not None else [];

    return
        <>
            <header className="m-head">
                <div className="grow">
                    <div className="date">{long_day(day)}</div>
                    <h1>Calendar</h1>
                </div>
                <button className="small" onClick={lambda e: MouseEvent { settingsOpen = True; }} aria-label="Calendar settings">⚙</button>
                <button className="small" onClick={sync} disabled={syncing}>{"…" if syncing else "⟳ Sync"}</button>
            </header>
            <div className="m-body">
                <div className="chips" style={{"flexWrap": "nowrap", "overflowX": "auto", "marginBottom": "12px"}}>
                    <button className="chip" onClick={lambda e: MouseEvent { day = add_days(day, -7); }} aria-label="Previous week">‹</button>
                    {for i in range(7) {
                        <button
                            key={str(i)}
                            className={"chip" + (" on" if add_days(start, i) == day else "")}
                            onClick={lambda e: MouseEvent { day = add_days(start, i); }}
                        >
                            {("Today" if add_days(start, i) == today else ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][i])}
                        </button>
                    }}
                    <button className="chip" onClick={lambda e: MouseEvent { day = add_days(day, 7); }} aria-label="Next week">›</button>
                </div>

                {if week is not None and not week.connected {
                    <div key="connect" className="card small" style={{"marginBottom": "12px", "background": "var(--accent-soft)"}}>
                        {"Sample calendar. "}
                        <a href="#" onClick={lambda e: MouseEvent { e.preventDefault(); settingsOpen = True; }}>Connect Google Calendar</a>
                    </div>
                }}

                {for d in picked {
                    <div key={d.day}>
                        <div className="card section">
                            <div className="row">
                                <div className="grow">
                                    <div className="free-num">{hours(d.free_left_minutes if d.day == today else d.free_minutes)}</div>
                                    <div className="small muted">{"free left today" if d.day == today else "free for to-dos"}</div>
                                </div>
                                <div className="small muted" style={{"textAlign": "right"}}>
                                    <div>{"Up " + clock(d.wake) + " · bed " + clock(d.bedtime)}</div>
                                    <div>{hours(d.event_minutes) + " events · " + hours(d.meal_minutes) + " meals"}</div>
                                    <div style={{"color": "var(--danger)"} if d.task_minutes > d.free_minutes else {}}>
                                        {hours(d.task_minutes) + " of to-dos"}
                                    </div>
                                </div>
                            </div>
                            {for ev in d.all_day {
                                <div key={ev.id} className="pill allday" style={{"marginTop": "8px"}}>{ev.title}</div>
                            }}
                        </div>
                        <div className="cal-mobile">
                            <DayTimeline
                                day={d}
                                gridStart={max(0, to_min(d.wake) - to_min(d.wake) % 60 - 60)}
                                gridEnd={min(1560, night_min(d.bedtime) + 60)}
                                scale={1.0}
                                nowMin={to_min(now_hhmm()) if d.day == today else -1}
                            />
                        </div>
                    </div>
                }}
            </div>
            {if settingsOpen {
                <CalendarSettings onClose={lambda { settingsOpen = False; }} onSaved={after_settings}/>
            }}
            <Toast message={toast} onClear={lambda { toast = ""; }}/>
        </>;
}
