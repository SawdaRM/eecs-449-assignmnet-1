"""Drawer: connect Google Calendar and set meal times + sleep need.

The private calendar link is write-only: the server never sends it back, so
the field stays empty and shows "Connected" once a link is saved.
"""

import from .api { cal_settings, save_cal_settings, sync_calendar, err_text }
sv import from ..services.calendar { CalSettingsView }

def:pub CalendarSettings(onClose: Callable[[], None], onSaved: Callable[[str], None]) -> JsxElement {
    has loaded: CalSettingsView | None = None,
        url: str = "",
        breakfast: str = "08:00",
        breakfastMin: str = "30",
        lunch: str = "12:30",
        lunchMin: str = "45",
        dinner: str = "18:30",
        dinnerMin: str = "60",
        sleepNeed: str = "8",
        saving: bool = False,
        error: str = "";

    async can with entry {
        try {
            s = await cal_settings();
            loaded = s;
            breakfast = s.breakfast;
            breakfastMin = str(s.breakfast_minutes);
            lunch = s.lunch;
            lunchMin = str(s.lunch_minutes);
            dinner = s.dinner;
            dinnerMin = str(s.dinner_minutes);
            sleepNeed = str(s.sleep_need_hours);
        } except Exception as e {
            error = err_text(e);
        }
    }

    async def store(link: str) {
        saving = True;
        error = "";
        try {
            await save_cal_settings(
                link,
                breakfast,
                int(breakfastMin or "0"),
                lunch,
                int(lunchMin or "0"),
                dinner,
                int(dinnerMin or "0"),
                float(sleepNeed or "8")
            );
            r = await sync_calendar();
            onSaved(r.message);
            onClose();
        } except Exception as e {
            error = err_text(e);
        }
        saving = False;
    }

    async def save(e: FormEvent) {
        e.preventDefault();
        await store(url.strip() if url.strip() else "~keep");
    }

    async def disconnect(e: MouseEvent) {
        await store("");
    }

    connected = loaded is not None and loaded.connected;
    from_env = loaded is not None and loaded.from_env;

    def meal(label: str, at: str, mins: str, set_at: Callable[[str], None], set_mins: Callable[[str], None]) -> JsxElement {
        return
            <div className="two">
                <label className="field">
                    {label}
                    <input type="time" value={at} onChange={lambda e: ChangeEvent { set_at(e.target.value); }}/>
                </label>
                <label className="field">
                    Minutes
                    <input type="number" min="0" max="240" step="5" value={mins} onChange={lambda e: ChangeEvent { set_mins(e.target.value); }}/>
                </label>
            </div>;
    }

    return
        <>
            <div className="backdrop" onClick={lambda e: MouseEvent { onClose(); }}/>
            <form className="drawer" onSubmit={save}>
                <div className="row">
                    <h2 className="grow">Calendar settings</h2>
                    <button type="button" className="ghost small" onClick={lambda e: MouseEvent { onClose(); }}>Close</button>
                </div>

                <section className="card" style={{"display": "flex", "flexDirection": "column", "gap": "8px"}}>
                    <div className="row">
                        <strong className="grow">Google Calendar</strong>
                        {if connected {
                            <span key="on" className="pill" style={{"background": "var(--ok-soft)", "color": "var(--ok)"}}>Connected</span>
                        } else {
                            <span key="off" className="pill">Sample data</span>
                        }}
                    </div>
                    <ol className="small muted" style={{"margin": "0", "paddingLeft": "18px"}}>
                        <li>Open Google Calendar on a computer, click ⚙ → <strong>Settings</strong>.</li>
                        <li>Under <strong>Settings for my calendars</strong>, pick your calendar.</li>
                        <li>Scroll to <strong>Integrate calendar</strong> and copy the <strong>Secret address in iCal format</strong>.</li>
                    </ol>
                    <input
                        type="password"
                        autoComplete="off"
                        placeholder={"Paste a new link to replace the saved one" if connected else "https://calendar.google.com/calendar/ical/…/basic.ics"}
                        value={url}
                        onChange={lambda e: ChangeEvent { url = e.target.value; }}
                        aria-label="Google Calendar iCal link"
                    />
                    <div className="small faint">The link is private: anyone with it can see your events. It's stored on your planner server and never shown again.</div>
                    {if from_env {
                        <div key="env" className="small muted">Using GOOGLE_CALENDAR_ICS_URL from the server environment.</div>
                    }}
                    {if connected and not from_env {
                        <button key="dc" type="button" className="danger small" style={{"alignSelf": "flex-start"}} onClick={disconnect} disabled={saving}>
                            Disconnect
                        </button>
                    }}
                </section>

                <section style={{"display": "flex", "flexDirection": "column", "gap": "10px"}}>
                    <strong>Meals</strong>
                    <div className="small muted" style={{"marginTop": "-6px"}}>Blocked out every day. Set minutes to 0 to skip a meal.</div>
                    {meal("Breakfast", breakfast, breakfastMin, lambda v: str { breakfast = v; }, lambda v: str { breakfastMin = v; })}
                    {meal("Lunch", lunch, lunchMin, lambda v: str { lunch = v; }, lambda v: str { lunchMin = v; })}
                    {meal("Dinner", dinner, dinnerMin, lambda v: str { dinner = v; }, lambda v: str { dinnerMin = v; })}
                </section>

                <label className="field">
                    Sleep you need (hours)
                    <input type="number" min="4" max="12" step="0.25" value={sleepNeed} onChange={lambda e: ChangeEvent { sleepNeed = e.target.value; }}/>
                    <span className="small faint">
                        Your day ends at Oura's optimal bedtime (or 11pm without Oura). On days that haven't happened yet,
                        you're assumed to wake up this long after the previous night's bedtime.
                    </span>
                </label>

                {if error {
                    <div key="err" className="small" style={{"color": "var(--danger)"}}>{error}</div>
                }}
                <div className="row" style={{"marginTop": "auto"}}>
                    <span className="spacer"/>
                    <button type="button" onClick={lambda e: MouseEvent { onClose(); }}>Cancel</button>
                    <button type="submit" className="primary" disabled={saving}>{"Saving…" if saving else "Save & sync"}</button>
                </div>
            </form>
        </>;
}
