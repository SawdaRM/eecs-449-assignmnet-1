"""Pull Canvas assignments, Oura health data and Google Calendar events
(mock data unless configured)."""

import from .api { sync_all, err_text }

def:pub SyncButton(onDone: Callable[[str], None], label: str = "Sync all") -> JsxElement {
    has busy: bool = False;

    async def run {
        busy = True;
        try {
            onDone(await sync_all());
        } except Exception as e {
            onDone(err_text(e));
        }
        busy = False;
    }

    return
        <button onClick={run} disabled={busy} title="Import assignments, readiness data and calendar events">
            {"Syncing…" if busy else "⟳ " + label}
        </button>;
}
