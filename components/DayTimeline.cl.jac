"""One day as a vertical timeline: sleep, meals, calendar events and the free
time between them. Used by the web Calendar week and the mobile Calendar day.

`gridStart` / `gridEnd` are minutes since midnight (gridEnd may pass 1440),
`scale` is pixels per minute.
"""

import from .api { to_min, clock, hours }
sv import from ..services.calendar { DayBudget, TimeBlock }

"""Bedtimes before noon are after midnight: '00:30' -> 1470."""
def:pub night_min(hhmm: str) -> int {
    m = to_min(hhmm);
    return m + 1440 if m < 720 else m;
}

def:pub DayTimeline(
    day: DayBudget,
    gridStart: int,
    gridEnd: int,
    scale: float,
    nowMin: int = -1,
    compact: bool = False
) -> JsxElement {
    wake = to_min(day.wake);
    bed = night_min(day.bedtime);

    def px(m: int) -> str {
        return str(int((m - gridStart) * scale)) + "px";
    }

    def end_of(b: TimeBlock) -> int {
        e = to_min(b.end);
        return e if e > to_min(b.start) else e + 1440;
    }

    # Side-by-side lanes for overlapping events.
    lane_of: dict[str, int] = {};
    lane_ends: list[int] = [];
    for (i, b) in enumerate(day.blocks) {
        if b.kind == "event" or b.kind == "tentative" {
            start = to_min(b.start);
            lane = 0;
            while lane < len(lane_ends) and lane_ends[lane] > start {
                lane += 1;
            }
            if lane == len(lane_ends) {
                lane_ends.append(end_of(b));
            } else {
                lane_ends[lane] = end_of(b);
            }
            lane_of[str(i)] = lane;
        }
    }

    def block_style(i: int, b: TimeBlock) -> dict[str, str] {
        top = to_min(b.start);
        height = max(12, int((end_of(b) - top) * scale) - 2);
        left = 4 + lane_of.get(str(i), 0) * 12;
        return {"top": px(top), "height": str(height) + "px", "left": str(left) + "px"};
    }

    def tall(b: TimeBlock, needed: int) -> bool {
        return (end_of(b) - to_min(b.start)) * scale >= needed;
    }

    def label_for(b: TimeBlock) -> str {
        if b.kind == "free" {
            return "Free " + hours(b.minutes);
        }
        return b.label;
    }

    return
        <div className={"tl" + (" compact" if compact else "")} style={{"height": str(int((gridEnd - gridStart) * scale)) + "px"}}>
            {if wake > gridStart {
                <div key="sleep-am" className="tl-sleep" style={{"top": "0px", "height": px(wake)}}>
                    {if (wake - gridStart) * scale >= 18 {
                        <span key="l">{"Up " + clock(day.wake)}</span>
                    }}
                </div>
            }}
            {if bed < gridEnd {
                <div key="sleep-pm" className="tl-sleep night" style={{"top": px(bed), "bottom": "0px"}}>
                    <span>{"Bed " + clock(day.bedtime) + (" · Oura" if day.bedtime_source == "oura" else "")}</span>
                </div>
            }}
            {for (i, b) in enumerate(day.blocks) {
                <div
                    key={str(i) + b.start + b.kind}
                    className={"tl-block " + b.kind}
                    style={block_style(i, b)}
                    title={label_for(b) + " · " + clock(b.start) + "–" + clock(b.end)}
                >
                    {if tall(b, 16) {
                        <div key="t" className="tl-title">{label_for(b)}</div>
                    }}
                    {if tall(b, 32) and b.kind != "free" {
                        <div key="w" className="tl-when">{clock(b.start) + "–" + clock(b.end)}</div>
                    }}
                </div>
            }}
            {if nowMin >= gridStart and nowMin <= gridEnd {
                <div key="now" className="tl-now" style={{"top": px(nowMin)}}/>
            }}
        </div>;
}
