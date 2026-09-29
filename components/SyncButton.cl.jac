"""Pull Canvas assignments and Oura health data (mock data unless configured)."""

import from .api { sync_canvas, sync_oura, err_text }

def:pub SyncButton(onDone: Callable[[str], None], label: str = "Sync Canvas + Oura") -> JsxElement {
    has busy: bool = False;

    async def run {
        busy = True;
        try {
            c = await sync_canvas();
            o = await sync_oura();
            onDone(f"{c.message} {o.message}");
        } except Exception as e {
            onDone(err_text(e));
        }
        busy = False;
    }

    return
        <button onClick={run} disabled={busy} title="Import assignments and readiness data">
            {"Syncing…" if busy else "⟳ " + label}
        </button>;
}
