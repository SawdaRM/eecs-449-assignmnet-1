import from ..components.api {
    week_view, list_projects, list_tasks, add_task, set_done, schedule_task,
    today_iso, monday_of, add_days, month_day, hours, err_text
}
import from ..components.TaskRow { TaskRow }
import from ..components.TaskEditor { TaskEditor }
import from ..components.SyncButton { SyncButton }
import from ..components.Toast { Toast }
sv import from ..services.planner { TaskView, ProjectView, WeekPlan }

"""Web home: plan the week on a board. Drag tasks between days."""
def:pub WeekPage -> JsxElement {
    has start: str = monday_of(today_iso()),
        week: WeekPlan | None = None,
        projects: list[ProjectView] = [],
        allTasks: list[TaskView] = [],
        editing: TaskView | None = None,
        dragOver: str = "",
        toast: str = "",
        title: str = "",
        day: str = "",
        due: str = "",
        project: str = "",
        priority: str = "2",
        minutes: str = "30",
        energy: str = "normal";

    today = today_iso();

    async def load {
        w = await week_view(start);
        ps = await list_projects();
        ts = await list_tasks("all");
        week = w;
        projects = ps;
        allTasks = ts;
    }

    async can with [start] entry {
        try {
            await load();
        } except Exception as e {
            toast = err_text(e);
        }
    }

    async def add(e: FormEvent) {
        e.preventDefault();
        if not title.strip() {
            return;
        }
        try {
            await add_task(title.strip(), due, day, project, int(priority), int(minutes or "30"), energy);
            title = "";
            await load();
        } except Exception as err {
            toast = err_text(err);
        }
    }

    async def toggle(t: TaskView) {
        try {
            await set_done(t.id, t.status != "done");
            await load();
        } except Exception as err {
            toast = err_text(err);
        }
    }

    async def move(task_id: str, target: str) {
        try {
            await schedule_task(task_id, target);
            await load();
        } except Exception as err {
            toast = err_text(err);
        }
    }

    async def after_edit(msg: str) {
        toast = msg;
        await load();
    }

    def drop_handlers(zone: str, target: str) -> dict {
        return {
            "onDragOver": lambda e: any { e.preventDefault(); dragOver = zone; },
            "onDragLeave": lambda e: any { dragOver = ""; },
            "onDrop": lambda e: any {
                e.preventDefault();
                dragOver = "";
                move(str(e.dataTransfer.getData("text/plain")), target);
            }
        };
    }

    days = week.days if week is not None else [];
    unscheduled = week.unscheduled if week is not None else [];
    week_minutes = sum([d.minutes for d in days]);
    open_count = len([t for d in days for t in d.tasks if t.status == "todo"]);

    return
        <div>
            <div className="page-head">
                <h1>{"Week of " + month_day(start)}</h1>
                <div className="row">
                    <button className="small" onClick={lambda e: MouseEvent { start = add_days(start, -7); }}>
                        ← Prev
                    </button>
                    <button className="small" onClick={lambda e: MouseEvent { start = monday_of(today_iso()); }}>
                        This week
                    </button>
                    <button className="small" onClick={lambda e: MouseEvent { start = add_days(start, 7); }}>
                        Next →
                    </button>
                </div>
                <span className="muted small">
                    {f"{open_count} open · {hours(week_minutes)} planned"}
                </span>
                <span className="spacer"/>
                <SyncButton onDone={after_edit}/>
            </div>

            <form className="quick-add card" onSubmit={add}>
                <input
                    className="title"
                    placeholder="Add a task…"
                    value={title}
                    onChange={lambda e: ChangeEvent { title = e.target.value; }}
                    aria-label="Task title"
                />
                <select value={day} onChange={lambda e: ChangeEvent { day = e.target.value; }} aria-label="Day">
                    <option value="">Unscheduled</option>
                    {for d in days {
                        <option key={d.day} value={d.day}>{d.weekday + " " + month_day(d.day)}</option>
                    }}
                </select>
                <input
                    className="date"
                    type="date"
                    value={due}
                    onChange={lambda e: ChangeEvent { due = e.target.value; }}
                    title="Due date"
                    aria-label="Due date"
                />
                <input
                    list="board-projects"
                    placeholder="Project"
                    value={project}
                    onChange={lambda e: ChangeEvent { project = e.target.value; }}
                    style={{"flex": "1 1 140px", "width": "auto"}}
                    aria-label="Project"
                />
                <datalist id="board-projects">
                    {for p in projects {
                        <option key={p.id} value={p.name}/>
                    }}
                </datalist>
                <select value={priority} onChange={lambda e: ChangeEvent { priority = e.target.value; }} aria-label="Priority">
                    <option value="1">High priority</option>
                    <option value="2">Normal</option>
                    <option value="3">Low</option>
                </select>
                <select value={minutes} onChange={lambda e: ChangeEvent { minutes = e.target.value; }} aria-label="Estimate">
                    <option value="15">15m</option>
                    <option value="30">30m</option>
                    <option value="60">1h</option>
                    <option value="90">1h30</option>
                    <option value="120">2h</option>
                    <option value="180">3h</option>
                </select>
                <select value={energy} onChange={lambda e: ChangeEvent { energy = e.target.value; }} aria-label="Energy">
                    <option value="normal">Normal</option>
                    <option value="high">Deep focus</option>
                    <option value="low">Light</option>
                </select>
                <button className="primary" type="submit">Add</button>
            </form>

            <div className="board">
                {for d in days {
                    <section
                        key={d.day}
                        className={"col" + (" today" if d.day == today else "") + (" drop" if dragOver == d.day else "")}
                        {**drop_handlers(d.day, d.day)}
                    >
                        <div className="col-head">
                            <span className="day">{d.weekday}</span>
                            <span className="muted small">{month_day(d.day)}</span>
                            <span className={"load over" if d.minutes > 360 else "load"}>
                                {hours(d.minutes) if d.minutes else ""}
                            </span>
                        </div>
                        {if len(d.tasks) == 0 {
                            <div key="s193" className="empty">Drop tasks here</div>
                        }}
                        {for t in d.tasks {
                            <TaskRow
                                key={t.id}
                                task={t}
                                onToggle={toggle}
                                onOpen={lambda x: TaskView { editing = x; }}
                                showScheduled={False}
                                draggable={True}
                            />
                        }}
                    </section>
                }}
                <section
                    className={"col" + (" drop" if dragOver == "none" else "")}
                    {**drop_handlers("none", "")}
                >
                    <div className="col-head">
                        <span className="day">Someday</span>
                        <span className="load">{str(len(unscheduled))}</span>
                    </div>
                    {if len(unscheduled) == 0 {
                        <div key="s216" className="empty">No loose tasks</div>
                    }}
                    {for t in unscheduled {
                        <TaskRow
                            key={t.id}
                            task={t}
                            onToggle={toggle}
                            onOpen={lambda x: TaskView { editing = x; }}
                            draggable={True}
                        />
                    }}
                </section>
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
