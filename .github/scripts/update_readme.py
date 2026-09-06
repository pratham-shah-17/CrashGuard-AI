import json
from pathlib import Path
import re

def update_readme():
    readme_path = Path("README.md")
    if not readme_path.exists():
        print("README.md not found!")
        return

    analysis_path = Path("docs/architecture/analysis.json")
    if not analysis_path.exists():
        print("Analysis JSON not found!")
        return

    with open(analysis_path, "r") as f:
        analysis = json.load(f)

    with open(readme_path, "r") as f:
        content = f.read()

    # Dynamic replacement blocks using regex markers
    # Marker pattern: <!-- AUTO-GEN: [NAME] --> ... <!-- /AUTO-GEN: [NAME] -->

    # 1. Update Technology Stack
    tech_stack = "\n".join([f"- {fw}" for fw in analysis.get("frameworks", [])])
    content = re.sub(
        r"(<!-- AUTO-GEN: TECH-STACK -->).*?(<!-- /AUTO-GEN: TECH-STACK -->)",
        f"\\1\n{tech_stack}\n\\2",
        content,
        flags=re.DOTALL
    )

    # 2. Update Architecture Links/Details
    arch_info = "[View Detailed Architecture Diagrams](docs/architecture/architecture.md)"
    content = re.sub(
        r"(<!-- AUTO-GEN: ARCHITECTURE -->).*?(<!-- /AUTO-GEN: ARCHITECTURE -->)",
        f"\\1\n{arch_info}\n\\2",
        content,
        flags=re.DOTALL
    )

    # 3. Insert Badges (Mockup of dynamic badges based on analysis)
    badges = "[![CI/CD Automation](https://github.com/pratham-shah-17/CrashGuard-AI/actions/workflows/ci_cd.yml/badge.svg)](https://github.com/pratham-shah-17/CrashGuard-AI/actions/workflows/ci_cd.yml)"
    content = re.sub(
        r"(<!-- AUTO-GEN: BADGES -->).*?(<!-- /AUTO-GEN: BADGES -->)",
        f"\\1\n{badges}\n\\2",
        content,
        flags=re.DOTALL
    )

    with open(readme_path, "w") as f:
        f.write(content)

    print("README.md successfully updated.")

if __name__ == "__main__":
    update_readme()
