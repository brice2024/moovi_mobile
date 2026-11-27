## [t1] Establish migration constitution and cross-cutting constraints
- Codebase/domain discoveries: The project profile classifies this as a cross-system rewrite but explicitly preserves the existing Flutter UI; the Flask API documents JWT-authenticated REST and Socket.IO contracts and a non-success OTP delivery response on WAHA failure.
- Wrong assumptions and corrections: No prior constitution, context, decisions, teamlead log, or inbox existed; do not infer an original ratification date from the task start date.
- Debugging dead-ends and what actually worked: The installed task-breakdown template path was absent; the plan and feature-spec templates were available and aligned with the constitution.
- Techniques/patterns worth reusing for future tasks: Keep provider REST credentials server-side, record endpoint and behavior gaps explicitly, and map existing journeys to observed API contracts before implementation.
- Learnings consumed: [none]
