import json
from pathlib import Path

def generate_dynamic_knowledge(analysis):
    nodes = []
    edges = []

    # App core node
    nodes.append({"id": "flutter_app", "label": analysis.get("pubspec_data", {}).get("name", "Flutter App").capitalize(), "type": "client"})

    # Environment variables
    for env in analysis.get("environment_variables", []):
        node_id = f"env_{env.lower()}"
        nodes.append({"id": node_id, "label": env, "type": "config"})
        edges.append({"source": "flutter_app", "target": node_id, "relation": "requires env var"})

    # Edge Functions
    for func in analysis.get("edge_functions", []):
        node_id = f"edge_{func}"
        nodes.append({"id": node_id, "label": f"Function: {func}", "type": "backend"})
        edges.append({"source": "flutter_app", "target": node_id, "relation": "calls API"})

    # Dart Modules
    modules = analysis.get("dart_modules", {})
    for mod_type, files in modules.items():
        type_node_id = f"module_{mod_type}"
        nodes.append({"id": type_node_id, "label": f"Library: {mod_type}", "type": "module"})
        edges.append({"source": "flutter_app", "target": type_node_id, "relation": "contains"})

        # Add up to 5 individual files per module type to avoid graph clutter
        for file in files[:5]:
            file_node_id = f"file_{file}"
            nodes.append({"id": file_node_id, "label": file, "type": "file"})
            edges.append({"source": type_node_id, "target": file_node_id, "relation": "implements"})

    # External Dependencies
    deps = analysis.get("pubspec_data", {}).get("dependencies", [])
    for dep in deps[:10]: # Top 10 for clarity
        dep_node_id = f"dep_{dep}"
        nodes.append({"id": dep_node_id, "label": f"Pkg: {dep}", "type": "dependency"})
        edges.append({"source": "flutter_app", "target": dep_node_id, "relation": "depends on"})

    return {"nodes": nodes, "edges": edges}

def main():
    analysis_path = Path("docs/architecture/analysis.json")
    if not analysis_path.exists():
        print("Analysis file not found. Run analyze_codebase.py first.")
        return

    with open(analysis_path, "r") as f:
        analysis = json.load(f)

    knowledge_graph = generate_dynamic_knowledge(analysis)

    out_dir = Path("docs/knowledge_graph")
    out_dir.mkdir(parents=True, exist_ok=True)

    out_path = out_dir / "graph.json"
    with open(out_path, "w") as f:
        json.dump(knowledge_graph, f, indent=2)

    print(f"Dynamic Knowledge graph built and saved to {out_path}")

if __name__ == "__main__":
    main()
