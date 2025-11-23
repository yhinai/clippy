import os
import sys

def verify_clippy_refactor():
    print("🔍 Starting Clippy Refactor Verification...")
    
    root_dir = "."
    errors = []
    warnings = []
    
    # 1. Check File/Directory Names
    print("\n📂 Checking File and Directory Names...")
    for dirpath, dirnames, filenames in os.walk(root_dir):
        if ".git" in dirpath: continue
        if "build" in dirpath: continue
        
        for dirname in dirnames:
            if "PastePup" in dirname:
                errors.append(f"❌ Found directory with old name: {os.path.join(dirpath, dirname)}")
        
        for filename in filenames:
            if "PastePup" in filename and filename != "TECHNICAL_REPORT.md": # Allow report to mention it
                errors.append(f"❌ Found file with old name: {os.path.join(dirpath, filename)}")

    # 2. Check File Content
    print("\n📄 Checking File Content...")
    extensions_to_scan = ['.swift', '.plist', '.pbxproj', '.entitlements']
    
    for dirpath, dirnames, filenames in os.walk(root_dir):
        if ".git" in dirpath: continue
        if "build" in dirpath: continue
        
        for filename in filenames:
            if not any(filename.endswith(ext) for ext in extensions_to_scan): continue
            
            path = os.path.join(dirpath, filename)
            try:
                with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    if "PastePup" in content:
                        # Context check: allowed in comments if explaining migration, but not in code
                        lines = content.splitlines()
                        for i, line in enumerate(lines):
                            if "PastePup" in line:
                                errors.append(f"❌ Found 'PastePup' in {path}:{i+1} -> {line.strip()}")
            except Exception as e:
                warnings.append(f"⚠️ Could not read {path}: {e}")

    # 3. Specific Checks
    print("\n🧠 Performing Logic Checks...")
    
    # Check App Struct
    try:
        with open("Clippy/ClippyApp.swift", "r") as f:
            if "struct ClippyApp: App" not in f.read():
                errors.append("❌ ClippyApp.swift does not contain 'struct ClippyApp: App'")
    except FileNotFoundError:
        errors.append("❌ Clippy/ClippyApp.swift not found")

    # Check Project File
    try:
        with open("Clippy.xcodeproj/project.pbxproj", "r") as f:
            proj_content = f.read()
            if "productName = Clippy" not in proj_content:
                errors.append("❌ project.pbxproj does not contain 'productName = Clippy'")
            if "altic.Clippy" not in proj_content:
                errors.append("❌ project.pbxproj does not contain bundle ID 'altic.Clippy'")
    except FileNotFoundError:
        errors.append("❌ Clippy.xcodeproj/project.pbxproj not found")

    # Report
    print("\n" + "="*40)
    if not errors:
        print("✅ VERIFICATION SUCCESSFUL! No 'PastePup' remnants found.")
    else:
        print(f"❌ VERIFICATION FAILED with {len(errors)} errors:")
        for error in errors:
            print(error)
        sys.exit(1)
            
    if warnings:
        print(f"\n⚠️ {len(warnings)} Warnings:")
        for warning in warnings:
            print(warning)

if __name__ == "__main__":
    verify_clippy_refactor()
