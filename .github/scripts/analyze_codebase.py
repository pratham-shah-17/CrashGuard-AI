import os
import json
import yaml
import re
from pathlib import Path

def analyze_pubspec():
    pubspec_path = Path("pubspec.yaml")
    if not pubspec_path.exists():
        return {}

    with open(pubspec_path, "r") as f:
        try:
            data = yaml.safe_load(f)
            return {
                "name": data.get("name", "Unknown"),
                "description": data.get("description", ""),
                "version": data.get("version", "1.0.0"),
                "dependencies": list(data.get("dependencies", {}).keys()) if data.get("dependencies") else [],
                "dev_dependencies": list(data.get("dev_dependencies", {}).keys()) if data.get("dev_dependencies") else []
            }
        except Exception as e:
            print(f"Error parsing pubspec: {e}")
            return {}

def scan_directory(directory):
    file_types = {}
    for root, _, files in os.walk(directory):
        if ".git" in root or "build" in root:
            continue
        for file in files:
            ext = os.path.splitext(file)[1]
            if ext:
                file_types[ext] = file_types.get(ext, 0) + 1
    return file_types

def detect_env_vars():
    env_vars = []
    env_template_path = Path("assets/env.template")
    if env_template_path.exists():
        with open(env_template_path, "r") as f:
            for line in f:
                if "=" in line and not line.strip().startswith("#"):
                    env_vars.append(line.split("=")[0].strip())
    return env_vars

def detect_edge_functions():
    functions = []
    supabase_functions_path = Path("supabase/functions")
    if supabase_functions_path.exists():
        for item in supabase_functions_path.iterdir():
            if item.is_dir():
                functions.append(item.name)
    return functions

def detect_dart_modules():
    modules = {"services": [], "ui": [], "models": []}
    lib_path = Path("lib")
    if lib_path.exists():
        for root, _, files in os.walk(lib_path):
            dir_name = os.path.basename(root)
            if dir_name in modules:
                for file in files:
                    if file.endswith(".dart"):
                        modules[dir_name].append(file.replace(".dart", ""))
    return modules

def main():
    print("Starting deep codebase analysis...")

    analysis = {
        "frameworks": ["Flutter", "Dart"],
        "pubspec_data": analyze_pubspec(),
        "file_statistics": scan_directory("."),
        "environment_variables": detect_env_vars(),
        "edge_functions": detect_edge_functions(),
        "dart_modules": detect_dart_modules(),
        "key_directories": {
            "lib": os.path.isdir("lib"),
            "supabase": os.path.isdir("supabase"),
            "test": os.path.isdir("test"),
            "docs": os.path.isdir("docs")
        }
    }

    # Infer additional frameworks based on contents
    if analysis["edge_functions"]:
        analysis["frameworks"].extend(["Supabase Edge Functions", "Deno/TypeScript"])

    out_dir = Path("docs/architecture")
    out_dir.mkdir(parents=True, exist_ok=True)

    out_path = out_dir / "analysis.json"
    with open(out_path, "w") as f:
        json.dump(analysis, f, indent=2)

    print(f"Deep Analysis saved to {out_path}")

if __name__ == "__main__":
    main()
