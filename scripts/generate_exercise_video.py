#!/usr/bin/env python3
"""
POC: Generate a short exercise demonstration video from a static image using Google Veo.

Usage:
    python3 scripts/generate_exercise_video.py \\
        --image public/exercise-assets/Barbell_Squat/0.jpg \\
        --exercise "Barbell Squat" \\
        --output public/generated-exercise-videos/barbell_squat_demo.mp4

Requirements:
    pip install -r scripts/requirements_video.txt

Environment variables (set one):
    GOOGLE_API_KEY               — Gemini API key (preferred)
    GOOGLE_APPLICATION_CREDENTIALS + GOOGLE_CLOUD_PROJECT  — Vertex AI
"""

import argparse
import mimetypes
import os
import sys
import time
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

BASE_PROMPT = (
    "Animate this fitness exercise image into a short realistic demonstration video. "
    "Keep the same person, same equipment, same camera angle and same background. "
    "Add only natural exercise movement. Do not change clothing, face, body type, "
    "lighting, gym equipment, or scene composition. Make it look like a clean fitness "
    "app demo video. Smooth motion, realistic biomechanics, no camera shake, no text, "
    "no logos, no extra people."
)


def build_prompt(exercise_name: str, custom_prompt: str | None) -> str:
    if custom_prompt:
        return custom_prompt
    return f"{BASE_PROMPT} Exercise: {exercise_name}."


def detect_mime_type(image_path: str) -> str:
    mime, _ = mimetypes.guess_type(image_path)
    return mime or "image/jpeg"


def generate_with_gemini(image_path: str, prompt: str, output_path: str) -> None:
    try:
        from google import genai
        from google.genai import types
    except ImportError:
        print("ERROR: google-genai package not installed.")
        print("Run: pip install -r scripts/requirements_video.txt")
        sys.exit(1)

    api_key = os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        print("ERROR: GOOGLE_API_KEY not set.")
        print("  export GOOGLE_API_KEY=your_key_here")
        print("  Get a key at: https://aistudio.google.com/apikey")
        sys.exit(1)

    client = genai.Client(api_key=api_key)

    image_bytes = Path(image_path).read_bytes()
    mime_type = detect_mime_type(image_path)

    print(f"[gemini] Sending image ({len(image_bytes) // 1024} KB) to Veo 2...")

    try:
        operation = client.models.generate_videos(
            model="veo-2.0-generate-001",
            source=types.GenerateVideosSource(
                prompt=prompt,
                image=types.Image(
                    image_bytes=image_bytes,
                    mime_type=mime_type,
                ),
            ),
            config=types.GenerateVideosConfig(
                number_of_videos=1,
                duration_seconds=5,
                enhance_prompt=True,
            ),
        )
    except Exception as e:
        print(f"ERROR: API request failed — {e}")
        print("Check that your API key has access to the Veo model.")
        print("See: scripts/README_video_generation.md")
        sys.exit(1)

    print("[gemini] Waiting for video generation (may take 1–3 minutes)...")
    poll_interval = 10
    elapsed = 0

    while not operation.done:
        time.sleep(poll_interval)
        elapsed += poll_interval
        operation = client.operations.get(operation)
        print(f"[gemini] Still processing... ({elapsed}s elapsed)")

    if not operation.result or not operation.result.generated_videos:
        print("ERROR: Video generation completed but returned no videos.")
        sys.exit(1)

    generated_video = operation.result.generated_videos[0]

    print("[gemini] Downloading video...")
    try:
        video_bytes = client.files.download(file=generated_video)
    except Exception as e:
        print(f"ERROR: Failed to download video — {e}")
        sys.exit(1)

    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(video_bytes)
    print(f"[gemini] Video saved to: {output_path}")


def generate_with_vertex(image_path: str, prompt: str, output_path: str) -> None:
    """Vertex AI Veo placeholder — structure ready for future implementation."""
    try:
        import vertexai  # noqa: F401
    except ImportError:
        print("ERROR: google-cloud-vertexai package not installed.")
        print("Run: pip install google-cloud-vertexai")
        sys.exit(1)

    project = os.environ.get("GOOGLE_CLOUD_PROJECT")
    location = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")

    if not project:
        print("ERROR: GOOGLE_CLOUD_PROJECT not set.")
        print("  export GOOGLE_CLOUD_PROJECT=your-project-id")
        sys.exit(1)

    print(f"[vertex] Project: {project}, Location: {location}")
    print("ERROR: Vertex AI Veo is not yet implemented in this POC.")
    print("Use GOOGLE_API_KEY with the Gemini API instead.")
    print("See: scripts/README_video_generation.md")
    sys.exit(1)


def detect_provider() -> str:
    if os.environ.get("GOOGLE_API_KEY"):
        return "gemini"
    if os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or os.environ.get("GOOGLE_CLOUD_PROJECT"):
        return "vertex"
    return "none"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate an exercise demo video from a static image using Google Veo."
    )
    parser.add_argument("--image", required=True, help="Path to the input exercise image")
    parser.add_argument("--exercise", required=True, help="Exercise name (e.g. 'Barbell Squat')")
    parser.add_argument("--output", help="Output MP4 path (default: public/generated-exercise-videos/<name>_demo.mp4)")
    parser.add_argument("--prompt", help="Custom video generation prompt (overrides default)")
    args = parser.parse_args()

    if not os.path.isfile(args.image):
        print(f"ERROR: Image not found: {args.image}")
        sys.exit(1)

    slug = args.exercise.lower().replace(" ", "_")
    output = args.output or f"public/generated-exercise-videos/{slug}_demo.mp4"
    prompt = build_prompt(args.exercise, args.prompt)
    provider = detect_provider()

    print(f"Provider : {provider}")
    print(f"Exercise : {args.exercise}")
    print(f"Image    : {args.image}")
    print(f"Output   : {output}")
    print(f"Prompt   : {prompt[:100]}...")
    print()

    if provider == "gemini":
        generate_with_gemini(args.image, prompt, output)
    elif provider == "vertex":
        generate_with_vertex(args.image, prompt, output)
    else:
        print("ERROR: No Google API credentials found.")
        print()
        print("Option 1 — Gemini API (recommended):")
        print("  export GOOGLE_API_KEY=your_key_here")
        print("  Get a key at: https://aistudio.google.com/apikey")
        print()
        print("Option 2 — Vertex AI:")
        print("  export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service_account.json")
        print("  export GOOGLE_CLOUD_PROJECT=your-project-id")
        print()
        print("Then re-run this script.")
        print("See scripts/README_video_generation.md for full setup instructions.")
        sys.exit(1)


if __name__ == "__main__":
    main()
