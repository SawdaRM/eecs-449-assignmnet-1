"""Mobile quick add: a title and a few taps."""

import from "@jac/runtime" { useNavigate }
import from ..components.api { add_task, list_projects, today_iso, add_days, monday_of, err_text }
import from ..components.Toast { Toast }
sv import from ..services.planner { ProjectView }

def:pub MobileAdd -> JsxElement {
    has title: str = "",
        when: str = "today",
        due: str = "",
        project: str = "",
        priority: int = 2,
        minutes: int = 30,
        energy: str = "normal",
        projects: list[ProjectView] = [],
        busy: bool = False,
        toast: str = "";

    nav = useNavigate();

    async can with entry {
        try {
            ps = await list_projects();
            projects = ps;
        } except Exception {
            projects = [];
        }
    }

    def scheduled_for(choice: str) -> str {
        today = today_iso();
        if choice == "today" {
            return today;
        }
        if choice == "tomorrow" {
            return add_days(today, 1);
        }
        if choice == "weekend" {
            return add_days(monday_of(today), 5);
        }
        return "";
    }

    async def save(e: FormEvent) {
        e.preventDefault();
        if not title.strip() {
            toast = "Give it a title first";
            return;
        }
        busy = True;
        try {
            await add_task(title.strip(), due, scheduled_for(when), project, priority, minutes, energy);
            title = "";
            due = "";
            toast = "Added";
            busy = False;
            nav("/m");
        } except Exception as err {
            toast = err_text(err);
            busy = False;
        }
    }

    def chip(label: str, on: bool, pick: Callable[[], None]) -> JsxElement {
        return
            <button type="button" className={"chip on" if on else "chip"} onClick={lambda e: MouseEvent { pick(); }}>
                {label}
            </button>;
    }

    return
        <>
            <header className="m-head"><h1>New task</h1></header>
            <form className="m-body m-form" onSubmit={save}>
                <input
                    className="big"
                    placeholder="What needs doing?"
                    value={title}
                    autoFocus={True}
                    onChange={lambda e: ChangeEvent { title = e.target.value; }}
                    aria-label="Task title"
                />
                <div>
                    <h3 style={{"marginBottom": "8px"}}>When</h3>
                    <div className="chips">
                        {chip("Today", when == "today", lambda { when = "today"; })}
                        {chip("Tomorrow", when == "tomorrow", lambda { when = "tomorrow"; })}
                        {chip("This weekend", when == "weekend", lambda { when = "weekend"; })}
                        {chip("Someday", when == "", lambda { when = ""; })}
                    </div>
                </div>
                <div>
                    <h3 style={{"marginBottom": "8px"}}>How long</h3>
                    <div className="chips">
                        {chip("15m", minutes == 15, lambda { minutes = 15; })}
                        {chip("30m", minutes == 30, lambda { minutes = 30; })}
                        {chip("1h", minutes == 60, lambda { minutes = 60; })}
                        {chip("2h", minutes == 120, lambda { minutes = 120; })}
                    </div>
                </div>
                <div>
                    <h3 style={{"marginBottom": "8px"}}>Energy</h3>
                    <div className="chips">
                        {chip("⚡ Deep focus", energy == "high", lambda { energy = "high"; })}
                        {chip("Normal", energy == "normal", lambda { energy = "normal"; })}
                        {chip("☁ Light", energy == "low", lambda { energy = "low"; })}
                    </div>
                </div>
                <div className="chips">
                    {chip("! High priority", priority == 1, lambda { priority = 1 if priority != 1 else 2; })}
                </div>
                <label className="field">
                    Due date (optional)
                    <input type="date" value={due} onChange={lambda e: ChangeEvent { due = e.target.value; }}/>
                </label>
                <label className="field">
                    Project (optional)
                    <select value={project} onChange={lambda e: ChangeEvent { project = e.target.value; }}>
                        <option value="">None</option>
                        {for p in projects {
                            <option key={p.id} value={p.name}>{p.name}</option>
                        }}
                    </select>
                </label>
                <button className="primary" type="submit" disabled={busy}>{"Adding…" if busy else "Add task"}</button>
            </form>
            <Toast message={toast} onClear={lambda { toast = ""; }}/>
        </>;
}
