"""Integrations: Canvas assignments and Oura health data.

Both work out of the box with MOCK data, so the app is fully usable (and
gradable) without a real account. To use real data, set these environment
variables on the server:

    CANVAS_ICS_URL      Canvas -> Calendar -> "Calendar Feed" link (secret URL)
    OURA_ACCESS_TOKEN   an OAuth2 access token for the Oura API v2

Syncs are idempotent: re-running updates existing nodes instead of
duplicating them (Canvas tasks are keyed by the event UID, health by day).
"""

import os;
import json;
import hashlib;
import from urllib.request { urlopen, Request }
import from datetime { date, datetime, timedelta }
import from services.models {
    Task, HealthSnapshot, HealthView, SyncResult,
    health_view, _now, _day_or_today
}
import from services.planner { _set_project }


# ================================================================ Canvas

obj CanvasEvent {
    has uid: str,
        title: str,
        due: str,
        course: str,
        url: str;
}

"""A realistic-looking week of assignments, relative to `today`."""
def _mock_canvas(today: str) -> list[CanvasEvent] {
    base = date.fromisoformat(today);
    rows = [
        ("eecs449-a1", "Assignment 1: Planning app in Jac", 6, "EECS 449"),
        ("eecs449-r3", "Reading response 3", 2, "EECS 449"),
        ("eecs482-p2", "Project 2: Thread library", 10, "EECS 482"),
        ("eecs482-hw4", "Homework 4", 4, "EECS 482"),
        ("stats250-lab5", "Lab 5 worksheet", 1, "STATS 250"),
    ];
    return [
        CanvasEvent(
            uid=f"mock-{uid}",
            title=title,
            due=(base + timedelta(days=offset)).isoformat(),
            course=course,
            url=""
        )
        for (uid, title, offset, course) in rows
    ];
}

"""ICS wraps long lines by starting the continuation with a space."""
def _unfold_ics(text: str) -> list[str] {
    lines: list[str] = [];
    for raw in text.replace("\r\n", "\n").split("\n") {
        if raw.startswith(" ") and lines {
            lines[-1] = lines[-1] + raw[1:];
        } else {
            lines.append(raw);
        }
    }
    return lines;
}

def _parse_ics(text: str) -> list[CanvasEvent] {
    events: list[CanvasEvent] = [];
    cur: dict[str, str] = {};
    inside = False;
    for line in _unfold_ics(text) {
        if line == "BEGIN:VEVENT" {
            inside = True;
            cur = {};
        } elif line == "END:VEVENT" {
            inside = False;
            start = cur.get("DTSTART", "");
            digits = "".join([c for c in start if c.isdigit()]);
            if len(digits) >= 8 and cur.get("SUMMARY", "") {
                summary = cur["SUMMARY"].replace("\\,", ",").replace("\\;", ";");
                course = "";
                if summary.endswith("]") and " [" in summary {
                    course = summary[summary.rindex(" [") + 2:-1];
                    summary = summary[:summary.rindex(" [")];
                }
                events.append(
                    CanvasEvent(
                        uid=cur.get("UID", summary),
                        title=summary,
                        due=f"{digits[0:4]}-{digits[4:6]}-{digits[6:8]}",
                        course=course,
                        url=cur.get("URL", "")
                    )
                );
            }
        } elif inside and ":" in line {
            key = line.split(":", 1)[0].split(";", 1)[0];
            cur[key] = line.split(":", 1)[1];
        }
    }
    return events;
}

def _fetch_canvas(url: str) -> list[CanvasEvent] {
    resp = urlopen(url, timeout=15);
    text = str(resp.read().decode("utf-8", "replace"));
    resp.close();
    return _parse_ics(text);
}

walker:pub SyncCanvas {
    """Turn Canvas assignments into tasks (project = course name).

    Uses CANVAS_ICS_URL when set; otherwise (or with `mock: true`) mock data.
    Only assignments due from `today` onward are imported.
    """
    has mock: bool = False,
        today: str = "",
        reports: list[SyncResult] = [];

    can sync with Root entry {
        day = _day_or_today(self.today);
        url = os.environ.get("CANVAS_ICS_URL", "");
        use_mock = self.mock or not url;
        events = _mock_canvas(day) if use_mock else _fetch_canvas(url);

        existing: dict[str, Task] = {};
        for t in [root-->[?:Task]] {
            if t.source == "canvas" and t.external_id {
                existing[t.external_id] = t;
            }
        }
        created = 0;
        updated = 0;
        for ev in events {
            if ev.due < day {
                continue;
            }
            if ev.uid in existing {
                t = existing[ev.uid];
                if t.due != ev.due or t.title != ev.title {
                    t.due = ev.due;
                    t.title = ev.title;
                    updated += 1;
                }
                continue;
            }
            t = (root ++> Task(
                title=ev.title,
                notes=ev.url,
                due=ev.due,
                priority=1,
                est_minutes=90,
                energy="high",
                source="canvas",
                external_id=ev.uid,
                tags=["school"],
                created_at=_now()
            ))[0];
            if ev.course {
                _set_project(t, ev.course);
            }
            created += 1;
        }
        src = "mock" if use_mock else "canvas";
        report SyncResult(
            source=src,
            created=created,
            updated=updated,
            message=f"Canvas ({src}): {created} new, {updated} updated."
        );
    }
}

# ================================================================ Oura

def _round1(x: float) -> float {
    return int(x * 10 + 0.5) / 10;
}

def _hhmm(minutes: int) -> str {
    m = minutes % 1440;
    return f"{m // 60:02d}:{m % 60:02d}";
}

"""Deterministic fake data: the same day always gets the same numbers."""
def _mock_health(day: str) -> HealthSnapshot {
    h = int(hashlib.sha256(day.encode()).hexdigest()[:8], 16);
    sleep_hours = _round1(5.5 + ((h // 7) % 30) / 10);   # 5.5..8.4
    optimal = 22 * 60 + 30 + 15 * ((h // 17) % 4);       # 22:30..23:15
    went_to_bed = optimal + (h // 23) % 70 - 10;         # a bit before to an hour late
    return HealthSnapshot(
        day=day,
        readiness=55 + h % 41,                    # 55..95
        sleep_score=58 + (h // 41) % 38,          # 58..95
        sleep_hours=sleep_hours,
        steps=3000 + (h // 13) % 9000,
        source="mock",
        bedtime=_hhmm(went_to_bed),
        wake=_hhmm(went_to_bed + int(sleep_hours * 60) + 25),
        optimal_bedtime=_hhmm(optimal)
    );
}

def _oura_get(path: str, start: str, end: str, token: str) -> list[dict] {
    url = f"https://api.ouraring.com/v2/usercollection/{path}?start_date={start}&end_date={end}";
    req = Request(url, headers={"Authorization": f"Bearer {token}"});
    resp = urlopen(req, timeout=15);
    body = str(resp.read().decode());
    resp.close();
    return json.loads(body).get("data", []) as list[dict];
}

"""'2026-10-04T23:12:00-04:00' -> '23:12' (the wall-clock time Oura recorded)."""
def _clock(stamp: str) -> str {
    if "T" not in stamp {
        return "";
    }
    return stamp.split("T", 1)[1][:5];
}

def _fetch_oura(start: str, end: str, token: str) -> list[HealthSnapshot] {
    by_day: dict[str, HealthSnapshot] = {};

    def slot(d: str) -> HealthSnapshot {
        if d not in by_day {
            by_day[d] = HealthSnapshot(day=d, source="oura");
        }
        return by_day[d];
    }

    for r in _oura_get("daily_readiness", start, end, token) {
        slot(str(r["day"])).readiness = int(r.get("score") or 0);
    }
    for r in _oura_get("daily_sleep", start, end, token) {
        slot(str(r["day"])).sleep_score = int(r.get("score") or 0);
    }
    for r in _oura_get("sleep", start, end, token) {
        secs = r.get("total_sleep_duration") or 0;
        s = slot(str(r["day"]));
        hrs = _round1(float(secs) / 3600);
        if hrs >= s.sleep_hours {
            # the main sleep of the night: when you went to bed and got up
            s.sleep_hours = hrs;
            s.bedtime = _clock(str(r.get("bedtime_start") or ""));
            s.wake = _clock(str(r.get("bedtime_end") or ""));
        }
    }
    # Oura's recommended bedtime window (offsets in seconds from midnight).
    # Not every account has it, so a failure here doesn't stop the sync.
    try {
        for r in _oura_get("sleep_time", start, end, token) {
            win = r.get("optimal_bedtime") or {};
            if isinstance(win, dict) and win.get("start_offset") is not None {
                secs = int(win["start_offset"]);
                slot(str(r["day"])).optimal_bedtime = _hhmm((secs // 60) % 1440);
            }
        }
    } except Exception {}
    for r in _oura_get("daily_activity", start, end, token) {
        slot(str(r["day"])).steps = int(r.get("steps") or 0);
    }
    return list(by_day.values());
}

walker:pub SyncOura {
    """Store one HealthSnapshot per day for the last `days` days (ending today).

    Uses OURA_ACCESS_TOKEN when set; otherwise (or with `mock: true`) mock data.
    """
    has days: int = 7,
        mock: bool = False,
        today: str = "",
        reports: list[SyncResult] = [];

    can sync with Root entry {
        end = date.fromisoformat(_day_or_today(self.today));
        start = end - timedelta(days=max(1, self.days) - 1);
        token = os.environ.get("OURA_ACCESS_TOKEN", "");
        use_mock = self.mock or not token;
        if use_mock {
            fresh = [
                _mock_health((start + timedelta(days=i)).isoformat())
                for i in range((end - start).days + 1)
            ];
        } else {
            fresh = _fetch_oura(start.isoformat(), end.isoformat(), token);
        }

        existing: dict[str, HealthSnapshot] = {};
        for h in [root-->[?:HealthSnapshot]] {
            existing[h.day] = h;
        }
        created = 0;
        updated = 0;
        for snap in fresh {
            if snap.day in existing {
                old = existing[snap.day];
                old.readiness = snap.readiness;
                old.sleep_score = snap.sleep_score;
                old.sleep_hours = snap.sleep_hours;
                old.steps = snap.steps;
                old.source = snap.source;
                old.bedtime = snap.bedtime;
                old.wake = snap.wake;
                old.optimal_bedtime = snap.optimal_bedtime;
                updated += 1;
            } else {
                root ++> snap;
                created += 1;
            }
        }
        src = "mock" if use_mock else "oura";
        report SyncResult(
            source=src,
            created=created,
            updated=updated,
            message=f"Oura ({src}): {created} new days, {updated} refreshed."
        );
    }
}

walker:pub GetHealth {
    """Health snapshots for the last `days` days, newest first."""
    has days: int = 7,
        today: str = "",
        reports: list[list[HealthView]] = [];

    can read with Root entry {
        end = _day_or_today(self.today);
        start = (date.fromisoformat(end) - timedelta(days=max(1, self.days) - 1)).isoformat();
        snaps = [h for h in [root-->[?:HealthSnapshot]] if start <= h.day and h.day <= end];
        snaps.sort(key=lambda h: HealthSnapshot : h.day, reverse=True);
        report [health_view(h) for h in snaps];
    }
}
