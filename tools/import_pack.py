#!/usr/bin/env python3
"""Copy the purchased Low Poly Racing Pack out of a Unity project into this
Godot project and record which material each part of each model uses.

The models carry no usable materials of their own: in Unity the prefabs assign
them. This script reads every prefab and material file and writes that mapping
to manifest.json, which scripts/car/car_library.gd reads at runtime.

The output folder is in .gitignore. The pack's licence does not allow the model
files to be redistributed, so never commit them.

Usage:
    python3 tools/import_pack.py "/path/to/Assets/Low Poly Racing Pack"
"""

import collections
import json
import os
import re
import shutil
import sys

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "vendor", "low_poly_racing_pack")

# Unity folder name -> our category name.
CATEGORIES = {
    "Hatchback": "hatchback", "Luxury": "luxury", "Muscule": "muscle",
    "Pickup": "pickup", "Sedan": "sedan", "Sports": "sports", "Suv": "suv",
    "Wheels": "wheels", "Props": "props", "Race track": "track",
}
CAR_CATEGORIES = ["hatchback", "luxury", "muscle", "pickup", "sedan", "sports", "suv"]


def read(path):
    with open(path, errors="ignore") as handle:
        return handle.read()


def guid_table(pack):
    """Unity refers to files by GUID; each file's .meta holds its GUID."""
    table = {}
    for root, _, files in os.walk(pack):
        for name in files:
            if name.endswith(".meta"):
                match = re.search(r"^guid: (\w+)", read(os.path.join(root, name)), re.M)
                if match:
                    table[match.group(1)] = os.path.relpath(os.path.join(root, name[:-5]), pack)
    return table


def vec(text, key, fields):
    match = re.search(key + r": \{([^}]*)\}", text)
    if not match:
        return None
    values = dict(part.strip().split(": ") for part in match.group(1).split(","))
    return [round(float(values[f]), 5) for f in fields]


def number(text, key, default):
    match = re.search(r"- " + key + r": ([-\d.e]+)", text)
    return float(match.group(1)) if match else default


def parse_material(path, guids):
    text = read(path)
    texture = None
    match = re.search(r"- _MainTex:\s*\n\s*m_Texture: \{fileID: \d+, guid: (\w+)", text)
    if match and match.group(1) in guids:
        texture = guids[match.group(1)]
    emission = vec(text, r"- _EmissionColor", "rgb") if "_EMISSION" in text else None
    return {
        "color": vec(text, r"- _Color", "rgba") or [1, 1, 1, 1],
        "texture": texture,
        "emission": emission,
        "transparent": number(text, "_Mode", 0) >= 2,
        "metallic": number(text, "_Metallic", 0.0),
        "smoothness": number(text, "_Glossiness", 0.5),
    }


def parse_prefab(path, guids):
    """Returns (fbx path, [[object name, material name or None, shown by default], ...])."""
    docs = re.split(r"^--- ", read(path), flags=re.M)[1:]
    names, active, renderers, fbx = {}, {}, [], None
    for doc in docs:
        head = re.match(r"!u!(\d+) &(-?\d+)", doc)
        kind, ident = head.group(1), head.group(2)
        if kind == "1":
            names[ident] = re.search(r"^  m_Name: (.*)$", doc, re.M).group(1).strip()
            # Cars with tuning parts ship both sets in one model and switch one set off.
            active[ident] = re.search(r"^  m_IsActive: (\d)", doc, re.M).group(1) == "1"
        elif kind == "23":
            owner = re.search(r"m_GameObject: \{fileID: (-?\d+)", doc).group(1)
            block = doc.split("m_Materials:")[1].split("m_StaticBatchInfo")[0]
            found = re.findall(r"guid: (\w+)", block)
            renderers.append((owner, found[0] if found else None))
        elif kind == "33":
            match = re.search(r"m_Mesh: \{fileID: -?\d+, guid: (\w+)", doc)
            if match and match.group(1) in guids:
                fbx = guids[match.group(1)]
    parts = []
    for owner, material_guid in renderers:
        source = guids.get(material_guid, "")
        # A few parts point at a material embedded in an .fbx; leave those to the model.
        material = os.path.splitext(os.path.basename(source))[0] if source.endswith(".mat") else None
        parts.append([names.get(owner, ""), material, active.get(owner, True)])
    return fbx, parts


def main():
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        sys.exit(__doc__)
    pack = sys.argv[1]
    guids = guid_table(pack)

    materials = {}
    for path in guids.values():
        if path.endswith(".mat"):
            materials[os.path.splitext(os.path.basename(path))[0]] = parse_material(os.path.join(pack, path), guids)

    models, seen_fbx = [], set()
    prefab_root = os.path.join(pack, "Prefabs")
    for root, _, files in sorted(os.walk(prefab_root)):
        for name in sorted(files):
            if not name.endswith(".prefab"):
                continue
            folder = os.path.relpath(root, prefab_root).split(os.sep)[0]
            fbx, parts = parse_prefab(os.path.join(root, name), guids)
            if fbx is None:
                continue
            seen_fbx.add(fbx)
            models.append({"name": name[:-7], "category": CATEGORIES.get(folder, folder.lower()),
                           "source": fbx, "parts": parts})

    # Models that ship without a prefab still get imported, with default materials.
    for path in sorted(guids.values()):
        if path.lower().endswith(".fbx") and path not in seen_fbx:
            folder = path.split("/")[1]
            models.append({"name": os.path.splitext(os.path.basename(path))[0],
                           "category": CATEGORIES.get(folder, folder.lower()),
                           "source": path, "parts": []})

    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    # Keep every material, not only the ones the prefabs use: cars with tuning
    # kits ship a second paint material that no prefab refers to.
    used_materials = set(materials)
    copied = {}

    def copy(source, subfolder):
        if source not in copied:
            target = os.path.join(subfolder, os.path.basename(source).replace(" ", "_"))
            os.makedirs(os.path.join(OUT, subfolder), exist_ok=True)
            if os.path.exists(os.path.join(OUT, target)):
                sys.exit("name clash: " + target)
            shutil.copy2(os.path.join(pack, source), os.path.join(OUT, target))
            copied[source] = target
        return copied[source]

    taken = set()
    for model in models:
        model["file"] = copy(model.pop("source"), os.path.join("models", model["category"]))
        ident = re.sub(r"[^a-z0-9]+", "_", model["name"].lower().replace("lp_veh_", "").replace("lp_", "")).strip("_")
        if ident in taken:  # the same prefab name exists in two folders
            ident = model["category"] + "_" + ident
        taken.add(ident)
        model["id"] = ident
    for name in sorted(used_materials):
        material = materials.get(name)
        if material and material["texture"]:
            material["texture"] = copy(material["texture"], "textures")

    ids = collections.Counter(model["id"] for model in models)
    clashes = [i for i, n in ids.items() if n > 1]
    if clashes:
        sys.exit("duplicate model ids: %s" % clashes)

    manifest = {
        "materials": {name: materials[name] for name in sorted(used_materials) if name in materials},
        "models": sorted(models, key=lambda m: (m["category"], m["id"])),
    }
    with open(os.path.join(OUT, "manifest.json"), "w") as handle:
        json.dump(manifest, handle, indent=1)

    counts = collections.Counter(model["category"] for model in models)
    print("wrote", os.path.relpath(OUT))
    for category in sorted(counts):
        print("  %-10s %3d models" % (category, counts[category]))
    print("  %d cars, %d materials, %d textures" % (
        sum(counts[c] for c in CAR_CATEGORIES), len(manifest["materials"]),
        sum(1 for m in manifest["materials"].values() if m["texture"])))


if __name__ == "__main__":
    main()
