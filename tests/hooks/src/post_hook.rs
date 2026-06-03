// Executable post-hook — same shape as `pre_hook.rs`, invoked in the
// Bazel action's shell AFTER Vivado exits. See that file for the
// argv / env contract.

use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

fn parse_flag(args: &[String], flag: &str) -> Option<PathBuf> {
    let mut i = 0;
    while i < args.len() {
        if args[i] == flag && i + 1 < args.len() {
            return Some(PathBuf::from(&args[i + 1]));
        }
        i += 1;
    }
    None
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();

    let project_dir = parse_flag(&args, "--project-dir")
        .expect("missing --project-dir");
    let export_dir = parse_flag(&args, "--export-dir")
        .expect("missing --export-dir");

    let env_project = env::var("VIVADO_PROJECT_DIR")
        .expect("missing VIVADO_PROJECT_DIR env var");
    let env_export = env::var("VIVADO_EXPORT_DIR")
        .expect("missing VIVADO_EXPORT_DIR env var");

    assert_eq!(env_project, project_dir.to_string_lossy());
    assert_eq!(env_export, export_dir.to_string_lossy());

    fs::create_dir_all(&export_dir).expect("mkdir -p export_dir");
    fs::write(
        export_dir.join("post_hook.marker"),
        format!(
            "post_hook ran\nproject_dir={}\nexport_dir={}\n",
            project_dir.display(),
            export_dir.display(),
        ),
    )
    .expect("write post_hook.marker");

    println!(
        "post_hook: project_dir={} export_dir={}",
        project_dir.display(),
        export_dir.display(),
    );
    ExitCode::SUCCESS
}
