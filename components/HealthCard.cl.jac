"""Readiness ring + how full today is. Used on web Today and mobile Today."""

import from .api { hours }
sv import from ..services.planner { DayPlan }

def:pub HealthCard(plan: DayPlan) -> JsxElement {
    h = plan.health;
    score = h.readiness if h is not None else 0;
    tone = "none" if h is None else ("good" if score >= 85 else ("mid" if score >= 70 else "low"));
    pct = min(100, int(plan.planned_minutes * 100 / plan.capacity_minutes)) if plan.capacity_minutes else 0;
    over = plan.planned_minutes > plan.capacity_minutes;

    return
        <div className="card">
            <div className="readiness">
                <div className={"ring " + tone} title="Readiness">{str(score) if h is not None else "–"}</div>
                <div className="grow">
                    <div style={{"fontWeight": "600"}}>
                        {"Readiness " + str(score) if h is not None else "No health data yet"}
                    </div>
                    {if h is not None {
                        <div key="s21" className="small muted">
                            {f"Slept {h.sleep_hours}h · sleep score {h.sleep_score} · {h.steps} steps"}
                        </div>
                    }}
                    <div className="small muted">{plan.note}</div>
                </div>
            </div>
            <div style={{"marginTop": "12px"}}>
                <div className="row small" style={{"marginBottom": "5px"}}>
                    <span className="grow muted">Today's load</span>
                    <span className={"muted" if not over else ""} style={{"color": "var(--danger)"} if over else {}}>
                        {hours(plan.planned_minutes) + " of " + hours(plan.capacity_minutes)}
                    </span>
                </div>
                <div className={"meter over" if over else "meter"}>
                    <div style={{"width": str(pct) + "%"}}/>
                </div>
            </div>
        </div>;
}
