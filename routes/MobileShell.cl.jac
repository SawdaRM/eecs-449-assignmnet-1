"""Mobile shell: full-height screen with a bottom tab bar.

This is what phones get by default, and what the native Capacitor app opens.
"""

import from "@jac/runtime" { Outlet, Link, useLocation }

def:pub MobileShell -> JsxElement {
    loc = useLocation();
    path = str((loc as any).pathname).rstrip("/") or "/m";

    def tab(href: str, icon: str, label: str, extra: str = "") -> JsxElement {
        cls = extra + (" active" if path == href else "");
        return
            <Link to={href} className={cls.strip()} aria-label={label}>
                <span className="icon">{icon}</span>
                <span>{label}</span>
            </Link>;
    }

    return
        <div className="m-app">
            <Outlet/>
            <nav className="m-tabs">
                {tab("/m", "◉", "Today")}
                {tab("/m/upcoming", "☰", "Upcoming")}
                {tab("/m/add", "+", "Add", "add")}
                {tab("/m/me", "♡", "Me")}
            </nav>
        </div>;
}
