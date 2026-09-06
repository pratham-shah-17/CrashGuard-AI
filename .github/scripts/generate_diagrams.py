import json
from pathlib import Path

def generate_mermaid_architecture(analysis):
    app_name = analysis.get("pubspec_data", {}).get("name", "Flutter App").capitalize()

    diagram = "```mermaid\ngraph TD\n"
    diagram += f"    Client[{app_name} Mobile/Web] \n"

    # Add Edge Functions
    for func in analysis.get("edge_functions", []):
        diagram += f"    Client --> Function_{func.replace('-', '_')}[Supabase Edge: {func}]\n"
        diagram += f"    Function_{func.replace('-', '_')} --> SupabaseDB[(Supabase PostgreSQL)]\n"

    # Add Config/Env
    if analysis.get("environment_variables"):
        diagram += f"    Client --> EnvVars{{Environment Config}}\n"

    # Map high-level Modules
    modules = analysis.get("dart_modules", {})
    if modules.get("ui"):
        diagram += f"    Client --> UI[User Interface Layer]\n"
    if modules.get("services"):
        diagram += f"    Client --> Services[Business Logic & Services]\n"
    if modules.get("models"):
        diagram += f"    Client --> Models[Data Models]\n"

    diagram += "```"
    return diagram

def generate_mermaid_dependencies(analysis):
    deps = analysis.get("pubspec_data", {}).get("dependencies", [])[:12]

    diagram = "```mermaid\ngraph LR\n    App[Core App] --> CoreDeps{Core Dependencies}\n"
    for dep in deps:
        diagram += f"    CoreDeps --> {dep}\n"
    diagram += "```"
    return diagram

def main():
    analysis_path = Path("docs/architecture/analysis.json")
    if not analysis_path.exists():
        print("Analysis file not found. Run analyze_codebase.py first.")
        return

    with open(analysis_path, "r") as f:
        analysis = json.load(f)

    out_dir = Path("docs/architecture")

    arch_diagram = generate_mermaid_architecture(analysis)
    deps_diagram = generate_mermaid_dependencies(analysis)

    with open(out_dir / "architecture.md", "w") as f:
        f.write("# System Architecture\n\n")
        f.write("## Dynamic High-Level Architecture\n\n")
        f.write(arch_diagram + "\n\n")
        f.write("## Core Dependencies\n\n")
        f.write(deps_diagram + "\n")

    print("Dynamic diagrams generated successfully in docs/architecture/architecture.md")

if __name__ == "__main__":
    main()
