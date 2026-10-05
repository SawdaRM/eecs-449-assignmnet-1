"""Google Calendar + the daily time budget.

Sync: Google Calendar publishes every calendar as a private iCal feed
("Settings -> your calendar -> Integrate calendar -> Secret address in iCal
format"). Paste that link on the Calendar page (or set GOOGLE_CALENDAR_ICS_URL
on the server) and SyncCalendar imports the events, expanding repeating ones
(weekly classes, etc.). Without a link it uses a mock week, like Canvas/Oura.

Budget: for each day, the waking window runs from your wake time to tonight's
bedtime (Oura's optimal bedtime when available). Calendar events and meals are
taken out; what's left is free time for to-dos. PlanDay plans no more than
that (and no more than your readiness allows).
"""

import os;
import from urllib.request { urlopen, Request }
import from datetime { date, datetime, timedelta, timezone, tzinfo }
import from zoneinfo { ZoneInfo }
import from services.models {
    Task, HealthSnapshot, CalEvent, CalSettings,
    EventView, TimeBlock, DayBudget, CalendarWeek, CalSettingsView, SyncResult, TaskView,
    task_view, event_view, _now, _day_or_today
}


glob KEEP_TEXT: str = "~keep",
     WEEKDAYS: dict[str, int] = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6},
     DEFAULT_BEDTIME: str = "23:00",
     MIN_FREE_BLOCK: int = 15,       # gaps shorter than this aren't usable free time
     SYNC_DAYS_BACK: int = 7,
     SYNC_DAYS_AHEAD: int = 56;


# ================================================================ time helpers

"""'HH:MM' -> minutes since midnight (-1 if it isn't a time)."""
def _to_min(hhmm: str) -> int {
    parts = hhmm.strip().split(":");
    if len(parts) < 2 or not parts[0].isdigit() or not parts[1].isdigit() {
        return -1;
    }
    return int(parts[0]) * 60 + int(parts[1]);
}

"""Minutes -> 'HH:MM'. 1440 prints as '24:00'; later times wrap past midnight."""
def _fmt_min(m: int) -> str {
    if m != 1440 {
        m = m % 1440;
    }
    return f"{m // 60:02d}:{m % 60:02d}";
}

def _valid_time(hhmm: str) -> bool {
    m = _to_min(hhmm);
    return m >= 0 and m < 1440;
}

"""Bedtimes before noon belong to the night after: 00:30 -> 24:30."""
def _night_min(hhmm: str) -> int {
    m = _to_min(hhmm);
    return m + 1440 if 0 <= m and m < 720 else m;
}


# ================================================================ iCal parsing

obj IcsProp {
    has name: str,
        params: str,
        value: str;
}

obj IcsEvent {
    has props: list[IcsProp] = [];

    def get(name: str) -> IcsProp | None {
        for p in self.props {
            if p.name == name {
                return p;
            }
        }
        return None;
    }

    def text(name: str) -> str {
        p = self.get(name);
        if p is None {
            return "";
        }
        return p.value.replace("\\n", " ").replace("\\N", " ").replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\").strip();
    }

    def all(name: str) -> list[IcsProp] {
        return [p for p in self.props if p.name == name];
    }
}

"""One occurrence, already in local time."""
obj Occurrence {
    has uid: str,
        title: str,
        start: datetime,
        end: datetime,
        all_day: bool,
        busy: bool,
        location: str;
}

"""iCal wraps long lines by starting the continuation with a space or tab."""
def _unfold(text: str) -> list[str] {
    lines: list[str] = [];
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n") {
        if (raw.startswith(" ") or raw.startswith("\t")) and lines {
            lines[-1] = lines[-1] + raw[1:];
        } else {
            lines.append(raw);
        }
    }
    return lines;
}

def _read_events(text: str) -> list[IcsEvent] {
    events: list[IcsEvent] = [];
    cur = IcsEvent(props=[]);
    inside = False;
    depth = 0;    # skip nested blocks such as VALARM
    for line in _unfold(text) {
        if line == "BEGIN:VEVENT" {
            cur = IcsEvent(props=[]);
            inside = True;
            depth = 0;
        } elif line == "END:VEVENT" {
            if inside {
                events.append(cur);
            }
            inside = False;
        } elif inside {
            if line.startswith("BEGIN:") {
                depth += 1;
            } elif line.startswith("END:") {
                depth -= 1;
            } elif depth == 0 and ":" in line {
                (head, value) = line.split(":", 1);
                name = head.split(";", 1)[0].upper();
                params = head.split(";", 1)[1] if ";" in head else "";
                cur.props.append(IcsProp(name=name, params=params, value=value.strip()));
            }
        }
    }
    return events;
}

def _param(params: str, key: str) -> str {
    for part in params.split(";") {
        if part.upper().startswith(key + "=") {
            return part.split("=", 1)[1].strip('"');
        }
    }
    return "";
}

def _zone(params: str, value: str) -> tzinfo | None {
    if value.endswith("Z") {
        return timezone.utc;
    }
    tzid = _param(params, "TZID");
    if tzid {
        try {
            return ZoneInfo(tzid);
        } except Exception {
            return None;
        }
    }
    return None;    # "floating" time: already local
}

"""A DTSTART-style value: wall-clock time in `tz` (None = local)."""
obj When {
    has wall: datetime,
        tz: tzinfo | None,
        all_day: bool;
}

def _parse_when(params: str, value: str) -> When | None {
    digits = "".join([c for c in value if c.isdigit()]);
    if len(digits) < 8 {
        return None;
    }
    y = int(digits[0:4]);
    mo = int(digits[4:6]);
    d = int(digits[6:8]);
    if "VALUE=DATE" in params.upper() or len(digits) < 12 {
        return When(wall=datetime(y, mo, d), tz=None, all_day=True);
    }
    hh = int(digits[8:10]);
    mm = int(digits[10:12]);
    ss = int(digits[12:14]) if len(digits) >= 14 else 0;
    return When(wall=datetime(y, mo, d, hh, mm, ss), tz=_zone(params, value), all_day=False);
}

"""Wall-clock time in `tz` -> naive local time on this machine."""
def _localize(wall: datetime, tz: tzinfo | None) -> datetime {
    if tz is None {
        return wall;
    }
    return wall.replace(tzinfo=tz).astimezone().replace(tzinfo=None);
}

def _key(dt: datetime) -> str {
    return dt.strftime("%Y%m%dT%H%M");
}

"""'PT1H30M', 'P1D', ... -> timedelta."""
def _parse_duration(value: str) -> timedelta {
    total = 0;
    num = "";
    in_time = False;
    for c in value.upper() {
        if c.isdigit() {
            num += c;
        } elif c == "T" {
            in_time = True;
        } elif num {
            n = int(num);
            num = "";
            if c == "W" {
                total += n * 7 * 86400;
            } elif c == "D" {
                total += n * 86400;
            } elif c == "H" {
                total += n * 3600;
            } elif c == "M" and in_time {
                total += n * 60;
            } elif c == "S" {
                total += n;
            }
        }
    }
    return timedelta(seconds=total);
}

def _nth_weekday(y: int, m: int, wd: int, n: int) -> date | None {
    if n > 0 {
        first = date(y, m, 1);
        d = first + timedelta(days=(wd - first.weekday()) % 7 + 7 * (n - 1));
    } else {
        nxt = date(y + 1, 1, 1) if m == 12 else date(y, m + 1, 1);
        last = nxt - timedelta(days=1);
        d = last - timedelta(days=(last.weekday() - wd) % 7 + 7 * (-n - 1));
    }
    return d if d.month == m else None;
}

"""Start dates (wall clock, in the event's own zone) of a repeating event.

Supports FREQ=DAILY/WEEKLY/MONTHLY/YEARLY with INTERVAL, COUNT, UNTIL,
BYDAY (incl. '2TU' / '-1FR' for monthly) and BYMONTHDAY - what Google
Calendar's repeat options produce.
"""
def _expand(first: datetime, rule: str, until: datetime | None, horizon: datetime) -> list[datetime] {
    parts: dict[str, str] = {};
    for kv in rule.split(";") {
        if "=" in kv {
            parts[kv.split("=", 1)[0].upper()] = kv.split("=", 1)[1];
        }
    }
    freq = parts.get("FREQ", "").upper();
    interval = max(1, int(parts.get("INTERVAL", "1") or "1"));
    count = int(parts.get("COUNT", "0") or "0");
    byday = [x.strip().upper() for x in parts.get("BYDAY", "").split(",") if x.strip()];
    bymonthday = [int(x) for x in parts.get("BYMONTHDAY", "").split(",") if x.strip().lstrip("-").isdigit()];
    t = first.time();
    out: list[datetime] = [];

    def accept(dt: datetime) -> bool {
        # False = stop expanding
        if until is not None and dt > until {
            return False;
        }
        if count and len(out) >= count {
            return False;
        }
        if dt > horizon {
            return False;
        }
        if dt >= first {
            out.append(dt);
        }
        return True;
    }

    if freq == "DAILY" {
        days = [WEEKDAYS[b[-2:]] for b in byday if b[-2:] in WEEKDAYS];
        k = 0;
        while k < 20000 {
            d = first.date() + timedelta(days=k * interval);
            k += 1;
            if days and d.weekday() not in days {
                continue;
            }
            if not accept(datetime.combine(d, t)) {
                break;
            }
        }
    } elif freq == "WEEKLY" {
        days = sorted([WEEKDAYS[b[-2:]] for b in byday if b[-2:] in WEEKDAYS]) or [first.weekday()];
        week0 = first.date() - timedelta(days=first.weekday());
        k = 0;
        going = True;
        while going and k < 5000 {
            week = week0 + timedelta(days=7 * interval * k);
            k += 1;
            for wd in days {
                d = week + timedelta(days=wd);
                if d < first.date() {
                    continue;
                }
                if not accept(datetime.combine(d, t)) {
                    going = False;
                    break;
                }
            }
        }
    } elif freq == "MONTHLY" {
        k = 0;
        going = True;
        while going and k < 1200 {
            idx = first.year * 12 + (first.month - 1) + interval * k;
            k += 1;
            (y, m) = (idx // 12, idx % 12 + 1);
            dates: list[date] = [];
            if byday {
                for b in byday {
                    wd = WEEKDAYS.get(b[-2:], -1);
                    n = int(b[:-2]) if b[:-2].lstrip("+-").isdigit() else 1;
                    found = _nth_weekday(y, m, wd, n) if wd >= 0 else None;
                    if found is not None {
                        dates.append(found);
                    }
                }
            } else {
                for md in (bymonthday or [first.day]) {
                    try {
                        dates.append(date(y, m, md));
                    } except ValueError {
                        continue;    # e.g. the 31st in a 30-day month
                    }
                }
            }
            for d in sorted(dates) {
                if not accept(datetime.combine(d, t)) {
                    going = False;
                    break;
                }
            }
        }
    } elif freq == "YEARLY" {
        k = 0;
        while k < 200 {
            y = first.year + interval * k;
            k += 1;
            try {
                d = date(y, first.month, first.day);
            } except ValueError {
                continue;    # Feb 29
            }
            if not accept(datetime.combine(d, t)) {
                break;
            }
        }
    } else {
        out.append(first);
    }
    return out;
}

"""Every occurrence (local time) that overlaps [win_start, win_end)."""
def parse_calendar(text: str, win_start: datetime, win_end: datetime) -> list[Occurrence] {
    raw = _read_events(text);

    # Edited single occurrences of a repeating event carry RECURRENCE-ID:
    # they replace (or, if cancelled, remove) that occurrence of the series.
    moved: dict[str, list[str]] = {};
    for ev in raw {
        rid = ev.get("RECURRENCE-ID");
        if rid is not None {
            when = _parse_when(rid.params, rid.value);
            if when is not None {
                moved.setdefault(ev.text("UID"), []).append(_key(_localize(when.wall, when.tz)));
            }
        }
    }

    out: list[Occurrence] = [];
    for ev in raw {
        start_p = ev.get("DTSTART");
        if start_p is None or ev.text("STATUS").upper() == "CANCELLED" {
            continue;
        }
        parsed = _parse_when(start_p.params, start_p.value);
        if parsed is None {
            continue;
        }
        wall = parsed.wall;
        tz = parsed.tz;
        all_day = parsed.all_day;
        local_start = _localize(wall, tz);

        end_p = ev.get("DTEND");
        dur_p = ev.get("DURATION");
        length = timedelta(days=1) if all_day else timedelta(hours=1);
        if end_p is not None {
            ended = _parse_when(end_p.params, end_p.value);
            if ended is not None {
                length = _localize(ended.wall, ended.tz) - local_start;
            }
        } elif dur_p is not None {
            length = _parse_duration(dur_p.value);
        }
        if length < timedelta(0) {
            length = timedelta(0);
        }

        uid = ev.text("UID") or ev.text("SUMMARY");
        starts: list[datetime] = [local_start];
        rule_p = ev.get("RRULE");
        if rule_p is not None and ev.get("RECURRENCE-ID") is None {
            until: datetime | None = None;
            for kv in rule_p.value.split(";") {
                if kv.upper().startswith("UNTIL=") {
                    u = _parse_when("", kv.split("=", 1)[1]);
                    # compared against the series' own wall-clock times
                    if u is not None and u.all_day {
                        until = u.wall + timedelta(days=1, seconds=-1);   # whole last day
                    } elif u is not None and u.tz is not None and tz is not None {
                        until = u.wall.replace(tzinfo=u.tz).astimezone(tz).replace(tzinfo=None);
                    } elif u is not None {
                        until = _localize(u.wall, u.tz);
                    }
                }
            }
            horizon = win_end + timedelta(days=1);
            if tz is not None {
                horizon = horizon.astimezone(tz).replace(tzinfo=None);
            }
            walls = _expand(wall, rule_p.value, until, horizon);
            skip_keys: list[str] = list(moved.get(uid, []));
            for ex in ev.all("EXDATE") {
                for v in ex.value.split(",") {
                    exw = _parse_when(ex.params, v);
                    if exw is not None {
                        skip_keys.append(_key(_localize(exw.wall, exw.tz if exw.tz is not None else tz)));
                    }
                }
            }
            starts = [
                _localize(w, tz) for w in walls
                if _key(_localize(w, tz)) not in skip_keys
            ];
        }

        for s in starts {
            e = s + length;
            if e <= win_start or s >= win_end {
                if not (length == timedelta(0) and win_start <= s and s < win_end) {
                    continue;
                }
            }
            out.append(
                Occurrence(
                    uid=uid,
                    title=ev.text("SUMMARY") or "(busy)",
                    start=s,
                    end=e,
                    all_day=all_day,
                    busy=ev.text("TRANSP").upper() != "TRANSPARENT",
                    location=ev.text("LOCATION")
                )
            );
        }
    }
    return out;
}

"""Split occurrences into per-day CalEvent rows (multi-day events span days)."""
def _to_rows(occs: list[Occurrence], source: str, first_day: date, last_day: date) -> list[CalEvent] {
    rows: list[CalEvent] = [];
    for o in occs {
        if o.all_day {
            d = o.start.date();
            stop = max(o.end.date(), d + timedelta(days=1));
            while d < stop {
                if first_day <= d and d <= last_day {
                    rows.append(CalEvent(
                        uid=f"{o.uid}@{d.isoformat()}", title=o.title, day=d.isoformat(),
                        all_day=True, busy=False, location=o.location, source=source
                    ));
                }
                d = d + timedelta(days=1);
            }
            continue;
        }
        cur = o.start;
        while True {
            midnight = datetime.combine(cur.date() + timedelta(days=1), datetime.min.time());
            seg_end = min(o.end, midnight);
            d = cur.date();
            if first_day <= d and d <= last_day {
                end_txt = "24:00" if seg_end == midnight else seg_end.strftime("%H:%M");
                rows.append(CalEvent(
                    uid=f"{o.uid}@{_key(cur)}", title=o.title, day=d.isoformat(),
                    start=cur.strftime("%H:%M"), end=end_txt,
                    busy=o.busy, location=o.location, source=source
                ));
            }
            if seg_end >= o.end {
                break;
            }
            cur = seg_end;
        }
    }
    return rows;
}


# ================================================================ mock calendar

"""A student's week as an iCal feed (relative to `today`), so the mock goes
through exactly the same parser as a real Google Calendar."""
def _mock_ics(today: str) -> str {
    d = date.fromisoformat(today);
    mon = d - timedelta(days=d.weekday() + 7);     # last week's Monday
    def at(offset: int, hhmm: str) -> str {
        return (mon + timedelta(days=offset)).strftime("%Y%m%d") + "T" + hhmm.replace(":", "") + "00";
    }
    def day_of(offset: int) -> str {
        return (mon + timedelta(days=offset)).strftime("%Y%m%d");
    }
    rows = [
        ("lec449", "EECS 449 Lecture", at(0, "10:30"), at(0, "12:00"), "FREQ=WEEKLY;BYDAY=MO,WE", "1010 DOW"),
        ("lec482", "EECS 482 Lecture", at(1, "13:30"), at(1, "15:00"), "FREQ=WEEKLY;BYDAY=TU,TH", "1670 BBB"),
        ("lab250", "STATS 250 Lab", at(4, "09:30"), at(4, "10:30"), "FREQ=WEEKLY", "B844 East Hall"),
        ("oh482", "EECS 482 Office hours", at(2, "16:00"), at(2, "17:00"), "FREQ=WEEKLY", "BBB Learning Center"),
        ("gym", "Gym", at(0, "07:30"), at(0, "08:15"), "FREQ=WEEKLY;BYDAY=MO,WE,FR", "IM Building"),
        ("club", "Robotics club", at(3, "18:30"), at(3, "20:00"), "FREQ=WEEKLY", "FXB"),
        ("work", "Library shift", at(5, "11:00"), at(5, "14:00"), "FREQ=WEEKLY", "Shapiro Library"),
        ("call", "Call home", at(6, "15:00"), at(6, "15:30"), "FREQ=WEEKLY", ""),
        ("dent", "Dentist", at(9, "14:00"), at(9, "15:00"), "", "Downtown"),
        ("game", "Football game", at(12, "15:30"), at(12, "19:00"), "", "Michigan Stadium"),
        ("intv", "Internship interview (video)", at(10, "11:00"), at(10, "11:45"), "", "Zoom"),
    ];
    lines: list[str] = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Planner//mock//EN"];
    for (uid, title, s, e, rule, loc) in rows {
        lines += ["BEGIN:VEVENT", f"UID:mock-{uid}", f"SUMMARY:{title}", f"DTSTART:{s}", f"DTEND:{e}"];
        if rule {
            lines.append(f"RRULE:{rule}");
        }
        if loc {
            lines.append(f"LOCATION:{loc}");
        }
        lines.append("END:VEVENT");
    }
    lines += [
        "BEGIN:VEVENT", "UID:mock-fair", "SUMMARY:Career fair",
        f"DTSTART;VALUE=DATE:{day_of(11)}", f"DTEND;VALUE=DATE:{day_of(12)}", "TRANSP:TRANSPARENT", "END:VEVENT",
        "END:VCALENDAR"
    ];
    return "\n".join(lines);
}


# ================================================================ settings

def _settings() -> CalSettings {
    for s in [root-->[?:CalSettings]] {
        return s;
    }
    return (root ++> CalSettings())[0];
}

def _feed_url(s: CalSettings) -> str {
    return s.gcal_ics_url or os.environ.get("GOOGLE_CALENDAR_ICS_URL", "");
}

def _settings_view(s: CalSettings) -> CalSettingsView {
    return CalSettingsView(
        connected=_feed_url(s) != "",
        from_env=(not s.gcal_ics_url) and os.environ.get("GOOGLE_CALENDAR_ICS_URL", "") != "",
        breakfast=s.breakfast,
        breakfast_minutes=s.breakfast_minutes,
        lunch=s.lunch,
        lunch_minutes=s.lunch_minutes,
        dinner=s.dinner,
        dinner_minutes=s.dinner_minutes,
        sleep_need_hours=s.sleep_need_hours,
        last_synced=s.last_synced
    );
}

walker:pub GetCalendarSettings {
    """Meal times, sleep need and whether Google Calendar is connected.
    The private calendar link itself is never sent back."""
    has reports: list[CalSettingsView] = [];

    can read with Root entry {
        report _settings_view(_settings());
    }
}

walker:pub SaveCalendarSettings {
    """Partial update. `gcal_ics_url: ""` disconnects Google Calendar.
    Meal minutes of 0 mean "skip that meal"."""
    has gcal_ics_url: str = KEEP_TEXT,
        breakfast: str = KEEP_TEXT,
        breakfast_minutes: int = -1,
        lunch: str = KEEP_TEXT,
        lunch_minutes: int = -1,
        dinner: str = KEEP_TEXT,
        dinner_minutes: int = -1,
        sleep_need_hours: float = -1.0,
        reports: list[CalSettingsView] = [];

    can apply with Root entry {
        s = _settings();
        if self.gcal_ics_url != KEEP_TEXT {
            url = self.gcal_ics_url.strip();
            if url.startswith("webcal://") {
                url = "https://" + url[len("webcal://"):];
            }
            if url and not url.startswith("https://") {
                raise ValueError("Paste the calendar's https:// iCal link (it ends in .ics)");
            }
            s.gcal_ics_url = url;
        }
        for (name, val) in [("breakfast", self.breakfast), ("lunch", self.lunch), ("dinner", self.dinner)] {
            if val != KEEP_TEXT and not _valid_time(val) {
                raise ValueError(f"{name} must be a time like 08:00");
            }
        }
        if self.breakfast != KEEP_TEXT { s.breakfast = self.breakfast; }
        if self.lunch != KEEP_TEXT { s.lunch = self.lunch; }
        if self.dinner != KEEP_TEXT { s.dinner = self.dinner; }
        if self.breakfast_minutes >= 0 { s.breakfast_minutes = min(240, self.breakfast_minutes); }
        if self.lunch_minutes >= 0 { s.lunch_minutes = min(240, self.lunch_minutes); }
        if self.dinner_minutes >= 0 { s.dinner_minutes = min(240, self.dinner_minutes); }
        if self.sleep_need_hours >= 0 {
            s.sleep_need_hours = max(4.0, min(12.0, self.sleep_need_hours));
        }
        report _settings_view(s);
    }
}


# ================================================================ sync

def _fetch_text(url: str) -> str {
    req = Request(url, headers={"User-Agent": "Planner/1.0"});
    try {
        resp = urlopen(req, timeout=20);
        text = str(resp.read().decode("utf-8", "replace"));
        resp.close();
    } except Exception as e {
        raise ValueError(f"Couldn't download your calendar ({str(e)[:120]}). Check the iCal link.");
    }
    if "BEGIN:VCALENDAR" not in text {
        raise ValueError("That link didn't return a calendar. Use the 'Secret address in iCal format'.");
    }
    return text;
}

walker:pub SyncCalendar {
    """Import calendar events from a week ago to 8 weeks ahead.

    Uses the saved Google Calendar link (or GOOGLE_CALENDAR_ICS_URL);
    otherwise (or with `mock: true`) a mock week. Events in that window are
    replaced on every sync, so re-syncing never duplicates and picks up
    edits and deletions.
    """
    has mock: bool = False,
        today: str = "",
        reports: list[SyncResult] = [];

    can sync with Root entry {
        day = date.fromisoformat(_day_or_today(self.today));
        first_day = day - timedelta(days=SYNC_DAYS_BACK);
        last_day = day + timedelta(days=SYNC_DAYS_AHEAD);
        s = _settings();
        url = _feed_url(s);
        use_mock = self.mock or not url;
        text = _mock_ics(day.isoformat()) if use_mock else _fetch_text(url);
        src = "mock" if use_mock else "google";
        occs = parse_calendar(
            text,
            datetime.combine(first_day, datetime.min.time()),
            datetime.combine(last_day + timedelta(days=1), datetime.min.time())
        );
        rows = _to_rows(occs, src, first_day, last_day);

        lo = first_day.isoformat();
        hi = last_day.isoformat();
        old: dict[str, CalEvent] = {};
        for e in [root-->[?:CalEvent]] {
            if lo <= e.day and e.day <= hi {
                old[e.uid] = e;
            }
        }
        created = 0;
        updated = 0;
        keep: list[str] = [];
        for r in rows {
            if r.uid in keep {
                continue;    # duplicate occurrence in the feed
            }
            keep.append(r.uid);
            if r.uid in old {
                e = old[r.uid];
                if (e.title, e.start, e.end, e.busy, e.location, e.source) != (r.title, r.start, r.end, r.busy, r.location, r.source) {
                    e.title = r.title;
                    e.start = r.start;
                    e.end = r.end;
                    e.busy = r.busy;
                    e.location = r.location;
                    e.source = r.source;
                    updated += 1;
                }
            } else {
                root ++> r;
                created += 1;
            }
        }
        removed = 0;
        for (uid, e) in old.items() {
            if uid not in keep {
                del e;
                removed += 1;
            }
        }
        s.last_synced = _now();
        label = "Google Calendar" if src == "google" else "Calendar (mock)";
        report SyncResult(
            source=src,
            created=created,
            updated=updated + removed,
            message=f"{label}: {created} new, {updated} changed, {removed} removed."
        );
    }
}


# ================================================================ time budget

obj BudgetContext {
    has settings: CalSettings,
        health: dict[str, HealthSnapshot],
        events: dict[str, list[CalEvent]],
        tasks: list[Task];
}

def budget_context() -> BudgetContext {
    health: dict[str, HealthSnapshot] = {};
    for h in [root-->[?:HealthSnapshot]] {
        health[h.day] = h;
    }
    events: dict[str, list[CalEvent]] = {};
    for e in [root-->[?:CalEvent]] {
        events.setdefault(e.day, []).append(e);
    }
    return BudgetContext(
        settings=_settings(),
        health=health,
        events=events,
        tasks=[t for t in [root-->[?:Task]] if not t.archived]
    );
}

"""Tonight's target bedtime (minutes, may pass 24:00) and where it came from.

Oura's optimal bedtime for that night, else the latest one Oura gave, else
your average actual bedtime over the last week, else 23:00.
"""
def _bedtime_for(day: str, ctx: BudgetContext) -> tuple[int, str] {
    h = ctx.health.get(day);
    if h is not None and _to_min(h.optimal_bedtime) >= 0 {
        return (_night_min(h.optimal_bedtime), "oura");
    }
    past = sorted([k for k in ctx.health.keys() if k <= day], reverse=True);
    for k in past {
        if _to_min(ctx.health[k].optimal_bedtime) >= 0 {
            return (_night_min(ctx.health[k].optimal_bedtime), "oura");
        }
    }
    actual = [_night_min(ctx.health[k].bedtime) for k in past[:7] if _to_min(ctx.health[k].bedtime) >= 0];
    if actual {
        return (sum(actual) // len(actual), "average");
    }
    return (_night_min(DEFAULT_BEDTIME), "default");
}

"""When you get up: Oura's wake time for days that have happened, otherwise
last night's target bedtime plus your sleep need."""
def _wake_for(day: str, today: str, ctx: BudgetContext) -> int {
    h = ctx.health.get(day);
    if day <= today and h is not None and _to_min(h.wake) >= 0 {
        return _to_min(h.wake);
    }
    prev = (date.fromisoformat(day) - timedelta(days=1)).isoformat();
    (bed, _src) = _bedtime_for(prev, ctx);
    return bed - 1440 + int(ctx.settings.sleep_need_hours * 60);
}

def day_budget(day: str, today: str, now: str, ctx: BudgetContext) -> DayBudget {
    (bed, bed_src) = _bedtime_for(day, ctx);
    wake = _wake_for(day, today, ctx);
    timed = [e for e in ctx.events.get(day, []) if not e.all_day];
    busy = [e for e in timed if e.busy and _to_min(e.start) >= 0];

    # Something on the calendar before you'd normally be up? You'll be up.
    for e in busy {
        wake = min(wake, _to_min(e.start));
    }
    wake = max(0, wake);
    bed = max(bed, wake + 60);

    # Minute-by-minute map of the waking day: 0 free, 1 event, 2 meal.
    span = bed - wake;
    marks = [0] * span;
    def paint(a: int, b: int, kind: int) {
        lo = max(a, wake) - wake;
        hi = min(b, bed) - wake;
        for i in range(lo, hi) {
            if marks[i] == 0 or kind == 1 {
                marks[i] = kind;
            }
        }
    }
    s = ctx.settings;
    # Meals are flexible: one that clashes with an event moves to right after
    # it (up to 2h later); if there's no room it stays put, under the event.
    def clashes(a: int, b: int) -> int {
        # end of the latest event overlapping [a, b), or -1
        found = -1;
        for e in busy {
            ea = _to_min(e.start);
            eb = _to_min(e.end) if _to_min(e.end) >= 0 else 1440;
            if ea < b and a < eb {
                found = max(found, eb);
            }
        }
        return found;
    }
    meals: list[tuple[str, int, int]] = [];
    for (label, at, mins) in [
        ("Breakfast", s.breakfast, s.breakfast_minutes),
        ("Lunch", s.lunch, s.lunch_minutes),
        ("Dinner", s.dinner, s.dinner_minutes)
    ] {
        start = _to_min(at);
        if mins <= 0 or start < 0 {
            continue;
        }
        moved = start;
        hit = clashes(moved, moved + mins);
        while hit >= 0 and hit - start <= 120 and hit + mins <= bed {
            moved = hit;
            hit = clashes(moved, moved + mins);
        }
        meals.append((label, moved if hit < 0 else start, mins));
    }
    for (_label, a, mins) in meals {
        paint(a, a + mins, 2);
    }
    for e in busy {
        paint(_to_min(e.start), _to_min(e.end) if _to_min(e.end) >= 0 else 1440, 1);
    }

    blocks: list[TimeBlock] = [];
    event_minutes = len([m for m in marks if m == 1]);
    meal_minutes = len([m for m in marks if m == 2]);
    free_minutes = 0;
    free_left = 0;
    now_m = _to_min(now) if day == today else -1;
    i = 0;
    while i < span {
        j = i;
        while j < span and marks[j] == marks[i] {
            j += 1;
        }
        a = wake + i;
        b = wake + j;
        if marks[i] == 0 and j - i >= MIN_FREE_BLOCK {
            free_minutes += j - i;
            if day > today or (day == today and now_m < 0) {
                free_left += j - i;
            } elif day == today {
                free_left += max(0, b - max(a, now_m));
            }
            blocks.append(TimeBlock(start=_fmt_min(a), end=_fmt_min(b), minutes=j - i, kind="free", label="Free"));
        }
        i = j;
    }
    for (label, a, mins) in meals {
        if a + mins > wake and a < bed {
            blocks.append(TimeBlock(start=_fmt_min(max(a, wake)), end=_fmt_min(min(a + mins, bed)), minutes=mins, kind="meal", label=label));
        }
    }
    for e in timed {
        a = _to_min(e.start);
        b = _to_min(e.end) if _to_min(e.end) >= 0 else 1440;
        blocks.append(TimeBlock(start=e.start, end=_fmt_min(b), minutes=max(0, b - a), kind="event" if e.busy else "tentative", label=e.title));
    }
    blocks.sort(key=lambda b: TimeBlock : (_to_min(b.start), b.kind));

    on_day = [
        t for t in ctx.tasks
        if t.scheduled == day or (not t.scheduled and t.due == day)
    ];
    views = [task_view(t, today) for t in on_day];
    views.sort(key=lambda v: TaskView : (v.status != "todo", v.priority, v.title.lower()));
    return DayBudget(
        day=day,
        weekday=date.fromisoformat(day).strftime("%a"),
        wake=_fmt_min(wake),
        bedtime=_fmt_min(bed),
        bedtime_source=bed_src,
        awake_minutes=span,
        event_minutes=event_minutes,
        meal_minutes=meal_minutes,
        free_minutes=free_minutes,
        free_left_minutes=free_left if day >= today else 0,
        task_minutes=sum([v.est_minutes for v in views if v.status == "todo"]),
        blocks=blocks,
        all_day=[event_view(e) for e in ctx.events.get(day, []) if e.all_day],
        tasks=views
    );
}

walker:pub CalendarWeekView {
    """Seven day budgets starting at `start` (default: this week's Monday).
    `now` ("HH:MM", the client's clock) gives today's free time still ahead."""
    has start: str = "",
        today: str = "",
        now: str = "",
        reports: list[CalendarWeek] = [];

    can build with Root entry {
        day = _day_or_today(self.today);
        if self.start {
            first = date.fromisoformat(self.start);
        } else {
            d = date.fromisoformat(day);
            first = d - timedelta(days=d.weekday());
        }
        ctx = budget_context();
        days = [day_budget((first + timedelta(days=i)).isoformat(), day, self.now, ctx) for i in range(7)];
        sources = [e.source for evs in ctx.events.values() for e in evs];
        url = _feed_url(ctx.settings);
        report CalendarWeek(
            start=first.isoformat(),
            days=days,
            connected=url != "",
            source=("google" if "google" in sources else ("mock" if sources else "")),
            last_synced=ctx.settings.last_synced
        );
    }
}
