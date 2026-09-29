"""Planner - entry point.

`jac start main.jac` serves every walker below as `POST /walker/<Name>`
(Swagger docs at /docs) AND the web/mobile client at `/`.
"""

import from services.planner {
    AddTask, UpdateTask, CompleteTask, ScheduleTask, DeleteTask, ListTasks,
    LinkDependency, NextActions, PlanDay, WeekView,
    AddProject, ListProjects, AddGoal, ListGoals
}
import from services.integrations { SyncCanvas, SyncOura, GetHealth }

# Global styles for the web + mobile client.
cl import ".styles/global.css";

# One route table for both clients:
#   /, /today, /projects   -> web app (plan the week at a desk)
#   /m, /m/add, /m/upcoming, /m/me -> mobile app (check off + quick add on your phone;
#                              also what the native Capacitor build opens)
cl {
    import from "@jac/runtime" { Router, Routes, Route, Navigate }
    import from .components.api { forget_login }
    import from .routes.WebShell { WebShell }
    import from .routes.WeekPage { WeekPage }
    import from .routes.TodayPage { TodayPage }
    import from .routes.ProjectsPage { ProjectsPage }
    import from .routes.MobileShell { MobileShell }
    import from .routes.MobileToday { MobileToday }
    import from .routes.MobileAdd { MobileAdd }
    import from .routes.MobileUpcoming { MobileUpcoming }
    import from .routes.MobileMe { MobileMe }

    def:pub app -> JsxElement {
        # No accounts: everyone uses the shared plan. Drop any token left
        # over from an older version so requests hit the shared graph.
        forget_login();
        return
            <Router>
                <Routes>
                    <Route path="/" element={<WebShell/>}>
                        <Route index={True} element={<WeekPage/>}/>
                        <Route path="today" element={<TodayPage/>}/>
                        <Route path="projects" element={<ProjectsPage/>}/>
                    </Route>
                    <Route path="/m" element={<MobileShell/>}>
                        <Route index={True} element={<MobileToday/>}/>
                        <Route path="add" element={<MobileAdd/>}/>
                        <Route path="upcoming" element={<MobileUpcoming/>}/>
                        <Route path="me" element={<MobileMe/>}/>
                    </Route>
                    <Route path="*" element={<Navigate to="/" replace={True}/>}/>
                </Routes>
            </Router>;
    }
}
