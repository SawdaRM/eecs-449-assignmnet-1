"""'Clear completed' button: hides every crossed-out task, everywhere."""

import from .api { clear_completed, err_text }

def:pub ClearDoneButton(onDone: Callable[[str], None], small: bool = False) -> JsxElement {
    has busy: bool = False;

    async def run {
        busy = True;
        try {
            n = await clear_completed();
            onDone(f"Cleared {n} completed task" + ("" if n == 1 else "s") if n else "No completed tasks to clear");
        } except Exception as e {
            onDone(err_text(e));
        }
        busy = False;
    }

    return
        <button className={"small" if small else ""} onClick={run} disabled={busy} title="Hide all crossed-out tasks">
            {"Clearing…" if busy else "Clear completed"}
        </button>;
}
