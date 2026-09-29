"""Mobile Me: last week of readiness/sleep, sync, and view switching."""

import from "@jac/runtime" { useNavigate }
import from ..components.api { health, friendly_day, remember_view, err_text, load_demo }
import from ..components.SyncButton { SyncButton }
import from ..components.Toast { Toast }
sv import from ..services.planner { HealthView }

def:pub MobileMe -> JsxElement {
    has days: list[HealthView] = [],
        toast: str = "";

    nav = useNavigate();

    async def load {
        hs = await health(7);
        days = hs;
    }

    async can with entry {
        try {
            await load();
        } except Exception as e {
            toast = err_text(e);
        }
    }

    async def synced(msg: str) {
        toast = msg;
        await load();
    }

    async def demo {
        try {
            msg = await load_demo();
            toast = msg;
            await load();
        } except Exception as e {
            toast = err_text(e);
        }
    }

    def tone(score: int) -> str {
        return "good" if score >= 85 else ("mid" if score >= 70 else "low");
    }

    def desktop(e: MouseEvent) {
        remember_view("web");
        nav("/");
    }

    return
        <>
            <header className="m-head"><h1>Me</h1></header>
            <div className="m-body">
                <section className="section">
                    <h3>Last 7 days</h3>
                    {if len(days) == 0 {
                        <p key="s53" className="muted small">No health data yet. Sync to pull it in.</p>
                    }}
                    <div className="card" style={{"padding": "6px 14px"}}>
                        {for h in days {
                            <div key={h.day} className="row" style={{"padding": "8px 0"}}>
                                <div className={"ring " + tone(h.readiness)} style={{"width": "40px", "height": "40px", "fontSize": "14px"}}>
                                    {str(h.readiness)}
                                </div>
                                <div className="grow">
                                    <div style={{"fontWeight": "600"}}>{friendly_day(h.day).capitalize()}</div>
                                    <div className="small muted">{f"{h.sleep_hours}h sleep · {h.steps} steps"}</div>
                                </div>
                                <span className="pill">{h.source}</span>
                            </div>
                        }}
                    </div>
                </section>
                <section className="section" style={{"display": "flex", "flexDirection": "column", "gap": "8px"}}>
                    <SyncButton onDone={synced}/>
                    <button onClick={demo}>Load demo week</button>
                    <button onClick={desktop}>Switch to desktop view</button>
                </section>
            </div>
            <Toast message={toast} onClear={lambda { toast = ""; }}/>
        </>;
}
