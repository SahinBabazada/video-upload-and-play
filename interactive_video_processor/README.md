# Interactive Video Player with Upload and Backend HLS Conversion

This project allows users to upload a video, which is then converted to HLS format on the backend by Flask and FFmpeg. The Video.js player streams the processed video, supports subtitle uploads, and timed interactions.

## Project Structure

```
project_files/
├── app.py                 # Flask application (handles upload, conversion, serving)
├── requirements.txt       # Python dependencies
├── templates/
│   └── index.html         # Main HTML page with upload form
├── static/
│   ├── css/
│   │   └── style.css      # Custom CSS
│   └── js/
│       └── script.js      # Custom JavaScript (handles upload, player logic)
└── media/
    ├── uploads/           # Temporary storage for uploaded raw videos
    └── hls_outputs/       # Stores HLS segments (e.g., media/hls_outputs/UUID/stream.m3u8)
```

## Setup and Running

1.  **Install FFmpeg:**
    If you don't have FFmpeg, install it. (e.g., `sudo apt-get install ffmpeg` on Debian/Ubuntu, or `brew install ffmpeg` on macOS). Ensure it's in your system's PATH.

2.  **Set up Python Virtual Environment (Recommended):**
    Navigate to the `interactive_video_processor/project_files` directory:
    ```bash
    cd interactive_video_processor/project_files
    python3 -m venv venv
    source venv/bin/activate  # On Windows: venv\Scripts\activate
    ```

3.  **Install Python Dependencies:**
    ```bash
    pip install -r requirements.txt
    ```

4.  **Run the Flask Application:**
    ```bash
    python app.py
    ```
    The application will typically be available at `http://127.0.0.1:5000`.
    *Note: The first video processing might be slow as FFmpeg runs. Subsequent requests for the same processed video (if caching were implemented, which it isn't in this basic version) would be faster. For production, use asynchronous task queues like Celery for FFmpeg processing.*

5.  **Open in Browser:**
    Open `http://127.0.0.1:5000` in your web browser.

6.  **Upload Video:**
    Use the "Upload Video" form to select and upload an MP4 video.
    Wait for processing to complete. The player will then load the HLS stream.

7.  **Upload Subtitles:**
    Use the file input fields to upload your `.vtt` subtitle files.

## Sample Video and Subtitles

*   **Sample Video (Sintel Trailer - ~1 minute):**
    *   Download: `http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4`
    *   Save it and upload it through the web interface.

*   **Sample Subtitles (sintel_en.vtt):**
    Create a file named `sintel_en.vtt` with the following content:
    ```vtt
    WEBVTT

    00:00:02.000 --> 00:00:05.000
    (Wind howling)

    00:00:07.000 --> 00:00:10.000
    A lone figure walks through a snowy landscape.

    00:00:12.500 --> 00:00:15.000
    She is Sintel, searching for her lost dragon.
    ```
    Upload this via the "English (EN)" subtitle input.

## Important Notes
- **FFmpeg Processing:** Video conversion is done **synchronously** in this example for simplicity. For real applications, this task MUST be offloaded to a background worker (e.g., Celery) to prevent HTTP requests from timing out and to keep the web server responsive.
- **Error Handling:** Basic error handling is included. More robust error reporting can be added.
- **Storage:** Processed HLS files are stored in `media/hls_outputs/<video_id>/`. Consider a cleanup strategy for old files in a production environment.
- **Security:** Basic filename sanitization is used. For production, implement stricter validation for uploads (file types, size limits, content scanning if possible).
