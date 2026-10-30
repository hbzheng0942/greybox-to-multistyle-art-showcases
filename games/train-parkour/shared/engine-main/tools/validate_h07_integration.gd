extends "res://../tools/theme_pipeline/runtime.gd"
## One complete assembly, then six headless synthetic-input route branches.
## Rendering, frame rate, visual quality and human acceptance are separate.
var branch_reports: Array = []

func save_report(report: Dictionary) -> void:
    branch_reports.append({
        "branch": report.get("branch", options.get("branch", "main")),
        "passed": report.get("passed", false),
        "finished": report.get("finished", false),
        "simulation_seconds": report.get("simulation_seconds", 0.0),
        "recoveries": report.get("recoveries", -1),
        "camera_contract_errors": report.get("camera_contract_errors", -1),
        "visited_tracks": report.get("visited_tracks", []),
        "route_coverage": report.get("route_coverage", {}),
        "branch_choices_satisfied": report.get("branch_choices_satisfied", false),
        "assembly_checks": report.get("checks", {}),
    })

func run() -> void:
    options["mode"] = "replay"
    options["branch"] = "main"
    options["video-fps"] = "0"
    await super.run()
    if main == null or branch_reports.is_empty() or not branch_reports[0].passed:
        _finish()
        return
    for branch: String in ["fast", "high", "high-short", "safe", "rescue"]:
        options["branch"] = branch
        main.restart_run()
        seen = -1.0
        previous_us = 0
        await replay("replay")
    _finish()

func _finish() -> void:
    var visited := {}
    for report: Dictionary in branch_reports:
        for track: String in report.visited_tracks: visited[track] = true
    var continuity: Dictionary = host.presentation.get_meta("h07_continuity", {}) if host != null and host.presentation != null else {}
    var construction: Dictionary = host.presentation.get_meta("construction_report", {}) if host != null and host.presentation != null else {}
    var declared: int = main.lab.route.tracks.size() if main != null else 0
    var regions: Array = continuity.get("regions", [])
    var errors: Array = construction.get("errors", [])
    var result := {
        "schema": 1,
        "scope": "Headless assembly and six synthetic-input gameplay branches; no rendering/performance/visual/human acceptance claim.",
        "passed": branch_reports.size() == 6 and branch_reports.all(func(row): return row.passed) and visited.size() == 37 and declared == 37 and regions.size() == 9 and errors.is_empty(),
        "declared_tracks": declared,
        "visited_track_union": visited.keys(),
        "visited_track_count": visited.size(),
        "declared_regions": regions.size(),
        "region_records": regions,
        "construction_errors": errors,
        "continuity_technical_coverage": continuity.get("technical_coverage", {}),
        "branches": branch_reports,
        "visual_acceptance": false,
        "human_acceptance": false,
    }
    var file := FileAccess.open(options.output, FileAccess.WRITE)
    file.store_string(JSON.stringify(result, "  ", true, true) + "\n")
    print("H07_INTEGRATION_CONTRACT passed=", result.passed, " tracks=", visited.size(), "/", declared, " regions=", regions.size())
    quit(0 if result.passed else 1)
