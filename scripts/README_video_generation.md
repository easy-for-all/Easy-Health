# POC: Exercise Video Generation with Google Veo

Generates a short demonstration video (4–6s) from a static exercise image using Google Veo 2 via the Gemini API.

**This is an isolated POC — does not affect the main app.**

---

## Requirements

- Python 3.10+
- A Google API key with Veo access (see setup below)

---

## Setup

### 1. Install dependencies

```bash
pip install -r scripts/requirements_video.txt
```

### 2. Get a Google API key

1. Go to [https://aistudio.google.com/apikey](https://aistudio.google.com/apikey)
2. Create or select a project
3. Generate an API key

> **Note:** Veo 2 image-to-video may require a paid Gemini API tier or explicit model access. If you get a 403 or model-not-found error, check your billing and model availability at [https://ai.google.dev/gemini-api/docs/models](https://ai.google.dev/gemini-api/docs/models).

### 3. Configure the API key

```bash
export GOOGLE_API_KEY=your_key_here
```

Or add it to your `.env` file (never commit this):

```
GOOGLE_API_KEY=your_key_here
```

---

## Usage

```bash
python3 scripts/generate_exercise_video.py \
  --image path/to/exercise_image.jpg \
  --exercise "Barbell Squat" \
  --output public/generated-exercise-videos/barbell_squat_demo.mp4
```

### Arguments

| Argument | Required | Description |
|---|---|---|
| `--image` | Yes | Path to the input image (JPG, PNG) |
| `--exercise` | Yes | Exercise name, used in the default prompt |
| `--output` | No | Output MP4 path. Defaults to `public/generated-exercise-videos/<exercise>_demo.mp4` |
| `--prompt` | No | Custom generation prompt. Overrides the default prompt |

### Custom prompt example

```bash
python3 scripts/generate_exercise_video.py \
  --image path/to/squat.jpg \
  --exercise "Barbell Squat" \
  --prompt "Animate this image as a controlled barbell squat repetition. The person lowers into a squat and returns to standing with proper posture. Keep the same camera angle, same body, same barbell, same gym environment. Smooth, realistic movement. No extra objects, no text, no logos."
```

---

## Output

The generated MP4 is saved to `public/generated-exercise-videos/`. The directory is created automatically if it does not exist.

The file can be opened directly in a browser or media player.

---

## Troubleshooting

| Error | Fix |
|---|---|
| `GOOGLE_API_KEY not set` | `export GOOGLE_API_KEY=your_key` |
| `google-genai package not installed` | `pip install -r scripts/requirements_video.txt` |
| `403 / model not found` | Check billing and Veo model access in Google AI Studio |
| `Image not found` | Verify the `--image` path exists |
| Generation times out | Veo can take 1–3 min per video; the script polls automatically |

---

## Vertex AI (alternative)

If you prefer Vertex AI instead of the Gemini API:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service_account.json
export GOOGLE_CLOUD_PROJECT=your-project-id
export GOOGLE_CLOUD_LOCATION=us-central1  # optional, defaults to us-central1
```

> The Vertex AI path is scaffolded but not yet fully implemented in this POC. Open an issue or extend `generate_with_vertex()` in the script.

---

## Notes

- `public/exercise-assets/` does not exist yet in the repo. You can use any local image file for testing.
- This script does not modify the Rails API, Next.js frontend, or any database.
- Do not commit your `.env` or any file containing your API key.
