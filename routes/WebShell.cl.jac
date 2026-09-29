"""Desktop shell: top navigation around the web pages."""

import from "@jac/runtime" { Outlet, Link, Navigate, useLocation, useNavigate }
import from ..components.api { prefers_mobile, remember_view }

def:pub WebShell -> JsxElement {
    loc = useLocation();
    nav = useNavigate();
    path = str((loc as any).pathname);

    def to_mobile(e: MouseEvent) {
        remember_view("mobile");
        nav("/m");
    }

    def tab(href: str, label: str) -> JsxElement {
        return <Link to={href} className={"tab active" if path == href else "tab"}>{label}</Link>;
    }

    if prefers_mobile() {
        return <Navigate to="/m" replace={True}/>;
    }

    return
        <>
            <nav className="web-nav">
                <span className="brand">◆ Planner</span>
                {tab("/", "Week")}
                {tab("/today", "Today")}
                {tab("/projects", "Projects & goals")}
                <span className="spacer"/>
                <button className="ghost small" onClick={to_mobile}>Mobile view</button>
            </nav>
            <main className="web-main">
                <Outlet/>
            </main>
        </>;
}
