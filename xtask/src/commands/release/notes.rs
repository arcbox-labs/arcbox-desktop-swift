//! Extract the curated `### Highlights` block for a release.

use anyhow::{Context, Result, bail};

use crate::ReleaseNotesArgs;

fn changelog_version(line: &str) -> Option<&str> {
    let rest = line.trim().strip_prefix("## [")?;
    Some(&rest[..rest.find(']')?])
}

fn extract_highlights(changelog: &str, version: &str) -> Result<String> {
    let wanted = version.trim_start_matches('v');
    let mut found_release = false;
    let mut in_release = false;
    let mut in_highlights = false;
    let mut lines = Vec::new();

    for line in changelog.lines() {
        if let Some(candidate) = changelog_version(line) {
            if in_release {
                break;
            }
            in_release = candidate == wanted;
            found_release |= in_release;
            continue;
        }
        if !in_release {
            continue;
        }

        let trimmed = line.trim();
        if trimmed == "### Highlights" {
            in_highlights = true;
        } else if trimmed.starts_with("### ") && in_highlights {
            break;
        } else if in_highlights {
            lines.push(line);
        }
    }

    if !found_release {
        bail!("release {wanted} is missing from the changelog");
    }
    let highlights = lines.join("\n").trim().to_string();
    if highlights.is_empty() {
        bail!("release {wanted} has no non-empty ### Highlights section");
    }
    Ok(highlights)
}

pub fn run(args: ReleaseNotesArgs) -> Result<()> {
    let changelog = std::fs::read_to_string(&args.changelog)
        .with_context(|| format!("reading {}", args.changelog.display()))?;
    let highlights = extract_highlights(&changelog, &args.version)?;

    if let Some(parent) = args
        .output
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating {}", parent.display()))?;
    }
    std::fs::write(&args.output, format!("{highlights}\n"))
        .with_context(|| format!("writing {}", args.output.display()))?;
    println!("Release notes: {}", args.output.display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_only_the_requested_releases_highlights() {
        let changelog = r#"
# Changelog

## [1.2.0](https://example.com) (2026-08-10)

### Highlights

**Faster startup.** ArcBox now reports each startup phase.

### Bug Fixes

* internal fallback

## [1.1.0](https://example.com) (2026-08-01)

### Highlights

Older notes.
"#;

        assert_eq!(
            extract_highlights(changelog, "v1.2.0").unwrap(),
            "**Faster startup.** ArcBox now reports each startup phase."
        );
    }

    #[test]
    fn rejects_missing_or_empty_highlights() {
        let changelog = r#"
## [1.2.0] (2026-08-10)

### Bug Fixes

* fixed a crash
"#;

        assert!(
            extract_highlights(changelog, "1.2.0")
                .unwrap_err()
                .to_string()
                .contains("no non-empty ### Highlights")
        );
        assert!(extract_highlights(changelog, "1.1.0").is_err());
    }
}
