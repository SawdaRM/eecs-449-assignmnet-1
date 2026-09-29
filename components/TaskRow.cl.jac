"""One task: a round checkbox plus title and metadata pills.

Shared by the web board, the web Today page, and every mobile screen.
"""

import from .api { join_strs, friendly_day, hours }
sv import from ..services.planner { TaskView }

def:pub TaskRow(
    task: TaskView,
    onToggle: Callable[[TaskView], None],
    onOpen: Callable[[TaskView], None] | None = None,
    showScheduled: bool = True,
    showProject: bool = True,
    draggable: bool = False
) -> JsxElement {
    done = task.status == "done";

    def toggle(e: MouseEvent) {
        e.stopPropagation();
        onToggle(task);
    }

    def open(e: MouseEvent) {
        if onOpen {
            onOpen(task);
        }
    }

    def drag_start(e: any) {
        e.dataTransfer.setData("text/plain", task.id);
        e.dataTransfer.effectAllowed = "move";
    }

    cls = "task" + (" done" if done else "") + (" blocked" if task.blocked and not done else "");
    hint = ("Waiting on: " + join_strs(task.blocked_by, ", ")) if task.blocked else "Mark done";

    return
        <div className={cls} draggable={draggable} onDragStart={drag_start} data-testid="task">
            <button
                className={"check on" if done else "check"}
                onClick={toggle}
                title={hint}
                aria-label={("Reopen " if done else "Complete ") + task.title}
            >
                {"✓" if done else ""}
            </button>
            <div className="body" onClick={open}>
                <div className="title">
                    {task.title}
                    {task.priority == 1 and not done and <span className="prio" title="High priority">!</span>}
                </div>
                <div className="meta">
                    {if task.due {
                        <span key="due" className={"pill overdue" if task.overdue else "pill due"}>
                            {"due " + friendly_day(task.due)}
                        </span>
                    }}
                    {if showScheduled and task.scheduled and task.scheduled != task.due {
                        <span key="on" className="pill">{"on " + friendly_day(task.scheduled)}</span>
                    }}
                    {if showProject and task.project_name {
                        <span key="proj" className="pill project">{task.project_name}</span>
                    }}
                    <span className="pill">{hours(task.est_minutes)}</span>
                    {if task.energy == "high" {
                        <span key="hi" className="pill" title="Needs deep focus">⚡ focus</span>
                    } elif task.energy == "low" {
                        <span key="lo" className="pill" title="Low energy is fine">☁ light</span>
                    }}
                    {if task.blocked and not done {
                        <span key="blk" className="pill blocked">{"⧗ " + join_strs(task.blocked_by, ", ")}</span>
                    }}
                </div>
            </div>
        </div>;
}
