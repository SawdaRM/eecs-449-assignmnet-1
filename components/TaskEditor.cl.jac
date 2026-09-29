"""Side drawer for editing every field of a task, including what it waits on.

Render it with `key={task.id}` so its state resets when a different task opens.
"""

import from .api { join_strs, update_task, link_dependency, delete_task, err_text }
sv import from ..services.planner { TaskView, ProjectView }

def:pub TaskEditor(
    task: TaskView,
    allTasks: list[TaskView],
    projects: list[ProjectView],
    onClose: Callable[[], None],
    onSaved: Callable[[str], None]
) -> JsxElement {
    has title: str = task.title,
        notes: str = task.notes,
        due: str = task.due,
        scheduled: str = task.scheduled,
        project: str = task.project_name,
        priority: str = str(task.priority),
        minutes: str = str(task.est_minutes),
        energy: str = task.energy,
        tags: str = join_strs(task.tags, ", "),
        deps: list[str] = task.depends_on,
        saving: bool = False,
        error: str = "";

    candidates = [t for t in allTasks if t.id != task.id and (t.status == "todo" or t.id in task.depends_on)];

    def toggle_dep(tid: str) {
        if tid in deps {
            deps = [d for d in deps if d != tid];
        } else {
            deps = deps + [tid];
        }
    }

    async def save {
        saving = True;
        error = "";
        try {
            await update_task(
                task.id,
                title,
                notes,
                due,
                scheduled,
                project,
                int(priority),
                int(minutes or "30"),
                energy,
                [x.strip() for x in tags.split(",") if x.strip()]
            );
            for d in deps {
                if d not in task.depends_on {
                    await link_dependency(task.id, d, False);
                }
            }
            for d in task.depends_on {
                if d not in deps {
                    await link_dependency(task.id, d, True);
                }
            }
            onSaved("Saved");
            onClose();
        } except Exception as e {
            error = err_text(e);
        }
        saving = False;
    }

    async def remove {
        try {
            await delete_task(task.id);
            onSaved("Deleted");
            onClose();
        } except Exception as e {
            error = err_text(e);
        }
    }

    def close(e: MouseEvent) {
        onClose();
    }

    return
        <>
            <div className="backdrop" onClick={close}/>
            <aside className="drawer" role="dialog" aria-label="Edit task">
                <div className="row">
                    <h2 className="grow">Edit task</h2>
                    <button className="ghost" onClick={close} aria-label="Close">✕</button>
                </div>
                <label className="field">
                    Title
                    <input value={title} onChange={lambda e: ChangeEvent { title = e.target.value; }}/>
                </label>
                <div className="two">
                    <label className="field">
                        Due
                        <input type="date" value={due} onChange={lambda e: ChangeEvent { due = e.target.value; }}/>
                    </label>
                    <label className="field">
                        Work on
                        <input
                            type="date"
                            value={scheduled}
                            onChange={lambda e: ChangeEvent { scheduled = e.target.value; }}
                        />
                    </label>
                    <label className="field">
                        Priority
                        <select value={priority} onChange={lambda e: ChangeEvent { priority = e.target.value; }}>
                            <option value="1">High</option>
                            <option value="2">Normal</option>
                            <option value="3">Low</option>
                        </select>
                    </label>
                    <label className="field">
                        Energy
                        <select value={energy} onChange={lambda e: ChangeEvent { energy = e.target.value; }}>
                            <option value="high">Deep focus</option>
                            <option value="normal">Normal</option>
                            <option value="low">Light</option>
                        </select>
                    </label>
                    <label className="field">
                        Minutes
                        <input
                            type="number"
                            min="5"
                            step="5"
                            value={minutes}
                            onChange={lambda e: ChangeEvent { minutes = e.target.value; }}
                        />
                    </label>
                    <label className="field">
                        Project
                        <input
                            list="project-names"
                            value={project}
                            placeholder="none"
                            onChange={lambda e: ChangeEvent { project = e.target.value; }}
                        />
                        <datalist id="project-names">
                            {for p in projects {
                                <option key={p.id} value={p.name}/>
                            }}
                        </datalist>
                    </label>
                </div>
                <label className="field">
                    Tags (comma separated)
                    <input value={tags} onChange={lambda e: ChangeEvent { tags = e.target.value; }}/>
                </label>
                <label className="field">
                    Notes
                    <textarea rows={3} value={notes} onChange={lambda e: ChangeEvent { notes = e.target.value; }}/>
                </label>
                <div className="field">
                    <span className="small muted">Waits on (can't start until these are done)</span>
                    <div className="dep-list card">
                        {if len(candidates) == 0 {
                            <span key="s164" className="faint small">No other open tasks.</span>
                        }}
                        {for t in candidates {
                            <label key={t.id}>
                                <input
                                    type="checkbox"
                                    checked={t.id in deps}
                                    onChange={lambda e: ChangeEvent { toggle_dep(t.id); }}
                                />
                                {t.title}
                            </label>
                        }}
                    </div>
                </div>
                {error and <div className="pill overdue">{error}</div>}
                <div className="row">
                    <button className="primary" onClick={save} disabled={saving}>
                        {"Saving…" if saving else "Save"}
                    </button>
                    <button onClick={close}>Cancel</button>
                    <span className="spacer"/>
                    <button className="danger ghost" onClick={remove}>Delete</button>
                </div>
            </aside>
        </>;
}
