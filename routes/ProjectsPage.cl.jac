"""Web: goals and the projects that roll up into them, with progress."""

import from ..components.api {
    list_projects, list_goals, list_tasks, add_project, add_goal, set_done, friendly_day, err_text
}
import from ..components.TaskRow { TaskRow }
import from ..components.TaskEditor { TaskEditor }
import from ..components.Toast { Toast }
sv import from ..services.planner { TaskView, ProjectView, GoalView }

def:pub ProjectsPage -> JsxElement {
    has projects: list[ProjectView] = [],
        goals: list[GoalView] = [],
        tasks: list[TaskView] = [],
        editing: TaskView | None = None,
        projName: str = "",
        projGoal: str = "",
        goalTitle: str = "",
        goalDate: str = "",
        toast: str = "";

    async def load {
        ps = await list_projects();
        gs = await list_goals();
        ts = await list_tasks("all");
        projects = ps;
        goals = gs;
        tasks = ts;
    }

    async can with entry {
        try {
            await load();
        } except Exception as e {
            toast = err_text(e);
        }
    }

    async def new_project(e: FormEvent) {
        e.preventDefault();
        if not projName.strip() {
            return;
        }
        try {
            await add_project(projName.strip(), projGoal.strip());
            projName = "";
            projGoal = "";
            await load();
        } except Exception as err {
            toast = err_text(err);
        }
    }

    async def new_goal(e: FormEvent) {
        e.preventDefault();
        if not goalTitle.strip() {
            return;
        }
        try {
            await add_goal(goalTitle.strip(), goalDate);
            goalTitle = "";
            goalDate = "";
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

    async def after_edit(msg: str) {
        toast = msg;
        await load();
    }

    def open(t: TaskView) {
        editing = t;
    }

    loose = [t for t in tasks if t.status == "todo" and not t.project_name];

    return
        <div>
            <div className="page-head"><h1>Projects & goals</h1></div>

            <section className="section">
                <h3>Goals</h3>
                <div className="grid-cards">
                    {for g in goals {
                        <div key={g.id} className="card">
                            <div className="row">
                                <h2 className="grow">{g.title}</h2>
                                <span className="muted small">{str(int(g.progress * 100)) + "%"}</span>
                            </div>
                            <div className="meter" style={{"margin": "10px 0 8px"}}>
                                <div style={{"width": str(int(g.progress * 100)) + "%"}}/>
                            </div>
                            <div className="small muted">
                                {f"{g.done} of {g.total} tasks done"}
                                {g.target_date and " · by " + friendly_day(g.target_date)}
                            </div>
                            <div className="row wrap" style={{"marginTop": "8px", "gap": "4px"}}>
                                {for name in g.projects {
                                    <span key={name} className="pill project">{name}</span>
                                }}
                                {if len(g.projects) == 0 {
                                    <span key="s113" className="faint small">Link a project to this goal below.</span>
                                }}
                            </div>
                        </div>
                    }}
                    <form className="card" onSubmit={new_goal} style={{"display": "flex", "flexDirection": "column", "gap": "8px"}}>
                        <h2>New goal</h2>
                        <input
                            placeholder="e.g. Finish the semester strong"
                            value={goalTitle}
                            onChange={lambda e: ChangeEvent { goalTitle = e.target.value; }}
                            aria-label="Goal title"
                        />
                        <label className="field">
                            Target date (optional)
                            <input type="date" value={goalDate} onChange={lambda e: ChangeEvent { goalDate = e.target.value; }}/>
                        </label>
                        <button className="primary" type="submit">Add goal</button>
                    </form>
                </div>
            </section>

            <section className="section">
                <h3>Projects</h3>
                <form className="quick-add card" onSubmit={new_project}>
                    <input
                        className="title"
                        placeholder="New project name"
                        value={projName}
                        onChange={lambda e: ChangeEvent { projName = e.target.value; }}
                        aria-label="Project name"
                    />
                    <input
                        list="goal-names"
                        placeholder="Supports goal (optional)"
                        value={projGoal}
                        onChange={lambda e: ChangeEvent { projGoal = e.target.value; }}
                        style={{"flex": "2 1 200px", "width": "auto"}}
                        aria-label="Goal"
                    />
                    <datalist id="goal-names">
                        {for g in goals {
                            <option key={g.id} value={g.title}/>
                        }}
                    </datalist>
                    <button className="primary" type="submit">Add / link project</button>
                </form>
                <div className="grid-cards">
                    {for p in projects {
                        <div key={p.id} className="card">
                            <div className="row">
                                <h2 className="grow">{p.name}</h2>
                                <span className="muted small">{f"{p.done}/{p.total}"}</span>
                            </div>
                            {p.goal_title and <div className="small muted">{"→ " + p.goal_title}</div>}
                            <div className="meter" style={{"margin": "10px 0"}}>
                                <div style={{"width": str(int(p.progress * 100)) + "%"}}/>
                            </div>
                            {for t in tasks {
                                if t.project_id == p.id and t.status == "todo" {
                                    <TaskRow key={t.id} task={t} onToggle={toggle} onOpen={open} showProject={False}/>
                                }
                            }}
                            {if p.total > 0 and p.done == p.total {
                                <p key="alldone" className="muted small">All done 🎉</p>
                            }}
                        </div>
                    }}
                    {if len(loose) > 0 {
                        <div key="s179" className="card">
                            <h2 style={{"marginBottom": "10px"}}>No project</h2>
                            {for t in loose {
                                <TaskRow key={t.id} task={t} onToggle={toggle} onOpen={open}/>
                            }}
                        </div>
                    }}
                </div>
            </section>

            {if editing is not None {
                <TaskEditor
                    key={editing.id}
                    task={editing}
                    allTasks={tasks}
                    projects={projects}
                    onClose={lambda { editing = None; }}
                    onSaved={after_edit}
                />
            }}
            <Toast message={toast} onClear={lambda { toast = ""; }}/>
        </div>;
}
