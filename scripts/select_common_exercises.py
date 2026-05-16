import os
import shutil

SOURCE_DIR = "external/free-exercise-db/exercises"
TARGET_DIR = "data/exercises_selected"

KEYWORDS = [
    "bench", "squat", "deadlift", "curl", "press",
    "push", "pull", "row", "dip", "raise",
    "extension", "fly", "plank", "crunch", "sit",
    "lunge", "leg", "bike", "tricep", "bicep",
    "shoulder", "chest", "back", "lat"
]

os.makedirs(TARGET_DIR, exist_ok=True)

copied = []

for item in os.listdir(SOURCE_DIR):
    source_path = os.path.join(SOURCE_DIR, item)

    # ignora arquivos .json e qualquer coisa que não seja pasta
    if not os.path.isdir(source_path):
        continue

    lower = item.lower()

    if any(keyword in lower for keyword in KEYWORDS):
        target_path = os.path.join(TARGET_DIR, item)

        if os.path.exists(target_path):
            shutil.rmtree(target_path)

        shutil.copytree(source_path, target_path)
        copied.append(item)

print(f"Copiados: {len(copied)}")
