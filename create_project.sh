#!/bin/bash

# Exit on error
set -e

PROJECT_DIR="interactive_video_processor" # Renamed for clarity
PROJECT_FILES_DIR="${PROJECT_DIR}/project_files"

# Create base project directory
mkdir -p "${PROJECT_DIR}"
cd "${PROJECT_DIR}" || exit

# Create README.md
cat <<EOF > README.md
# Interactive Video Player with Upload and Backend HLS Conversion

This project allows users to upload a video, which is then converted to HLS format on the backend by Flask and FFmpeg. The Video.js player streams the processed video, supports subtitle uploads, and timed interactions.

## Project Structure

\`\`\`
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
\`\`\`

## Setup and Running

1.  **Install FFmpeg:**
    If you don't have FFmpeg, install it. (e.g., \`sudo apt-get install ffmpeg\` on Debian/Ubuntu, or \`brew install ffmpeg\` on macOS). Ensure it's in your system's PATH.

2.  **Set up Python Virtual Environment (Recommended):**
    Navigate to the \`${PROJECT_FILES_DIR}\` directory:
    \`\`\`bash
    cd ${PROJECT_FILES_DIR}
    python3 -m venv venv
    source venv/bin/activate  # On Windows: venv\\Scripts\\activate
    \`\`\`

3.  **Install Python Dependencies:**
    \`\`\`bash
    pip install -r requirements.txt
    \`\`\`

4.  **Run the Flask Application:**
    \`\`\`bash
    python app.py
    \`\`\`
    The application will typically be available at \`http://127.0.0.1:5000\`.
    *Note: The first video processing might be slow as FFmpeg runs. Subsequent requests for the same processed video (if caching were implemented, which it isn't in this basic version) would be faster. For production, use asynchronous task queues like Celery for FFmpeg processing.*

5.  **Open in Browser:**
    Open \`http://127.0.0.1:5000\` in your web browser.

6.  **Upload Video:**
    Use the "Upload Video" form to select and upload an MP4 video.
    Wait for processing to complete. The player will then load the HLS stream.

7.  **Upload Subtitles:**
    Use the file input fields to upload your \`.vtt\` subtitle files.

## Sample Video and Subtitles

*   **Sample Video (Sintel Trailer - ~1 minute):**
    *   Download: \`http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4\`
    *   Save it and upload it through the web interface.

*   **Sample Subtitles (sintel_en.vtt):**
    Create a file named \`sintel_en.vtt\` with the following content:
    \`\`\`vtt
    WEBVTT

    00:00:02.000 --> 00:00:05.000
    (Wind howling)

    00:00:07.000 --> 00:00:10.000
    A lone figure walks through a snowy landscape.

    00:00:12.500 --> 00:00:15.000
    She is Sintel, searching for her lost dragon.
    \`\`\`
    Upload this via the "English (EN)" subtitle input.

## Important Notes
- **FFmpeg Processing:** Video conversion is done **synchronously** in this example for simplicity. For real applications, this task MUST be offloaded to a background worker (e.g., Celery) to prevent HTTP requests from timing out and to keep the web server responsive.
- **Error Handling:** Basic error handling is included. More robust error reporting can be added.
- **Storage:** Processed HLS files are stored in \`media/hls_outputs/<video_id>/\`. Consider a cleanup strategy for old files in a production environment.
- **Security:** Basic filename sanitization is used. For production, implement stricter validation for uploads (file types, size limits, content scanning if possible).
EOF

# Create project files directory and subdirectories
mkdir -p "${PROJECT_FILES_DIR}/templates"
mkdir -p "${PROJECT_FILES_DIR}/static/css"
mkdir -p "${PROJECT_FILES_DIR}/static/js"
mkdir -p "${PROJECT_FILES_DIR}/media/uploads"
mkdir -p "${PROJECT_FILES_DIR}/media/hls_outputs"

# Create requirements.txt
cat <<EOF > "${PROJECT_FILES_DIR}/requirements.txt"
Flask
Flask-CORS
Werkzeug
EOF

# Create app.py (Flask Backend)
cat <<EOF > "${PROJECT_FILES_DIR}/app.py"
from flask import Flask, render_template, request, jsonify, send_from_directory
from flask_cors import CORS
import os
import subprocess
import uuid
from werkzeug.utils import secure_filename

app = Flask(__name__)
CORS(app) # Enable CORS for all routes

# Configuration
# Ensure these paths are correct relative to where app.py is run
APP_ROOT = os.path.dirname(os.path.abspath(__file__))
UPLOAD_FOLDER = os.path.join(APP_ROOT, 'media', 'uploads')
HLS_OUTPUT_FOLDER = os.path.join(APP_ROOT, 'media', 'hls_outputs')
ALLOWED_EXTENSIONS = {'mp4', 'mov', 'avi', 'mkv', 'webm'} # Add more as needed

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['HLS_OUTPUT_FOLDER'] = HLS_OUTPUT_FOLDER

# Ensure directories exist
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(HLS_OUTPUT_FOLDER, exist_ok=True)

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/upload_video', methods=['POST'])
def upload_video():
    if 'videoFile' not in request.files:
        return jsonify({'error': 'No video file part'}), 400
    file = request.files['videoFile']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400

    if file and allowed_file(file.filename):
        original_filename = secure_filename(file.filename)
        video_id = str(uuid.uuid4())
        
        # Save uploaded file temporarily
        temp_upload_path = os.path.join(app.config['UPLOAD_FOLDER'], f"{video_id}_{original_filename}")
        file.save(temp_upload_path)

        # HLS output directory for this specific video
        specific_hls_folder = os.path.join(app.config['HLS_OUTPUT_FOLDER'], video_id)
        os.makedirs(specific_hls_folder, exist_ok=True)
        
        hls_master_playlist_name = 'stream.m3u8'
        hls_master_playlist_path = os.path.join(specific_hls_folder, hls_master_playlist_name)

        # FFmpeg command - synchronous for this example
        # WARNING: For production, use a task queue (Celery, RQ) for FFmpeg processing!
        # This basic command creates a single bitrate HLS stream.
        # You can add more complex FFmpeg options for multiple bitrates, etc.
        ffmpeg_command = [
            'ffmpeg',
            '-i', temp_upload_path,
            '-profile:v', 'baseline',  # Or main, high
            '-level', '3.0',
            '-start_number', '0',
            '-hls_time', '10',         # Segment duration in seconds
            '-hls_list_size', '0',     # Keep all segments in playlist (0 means all)
            '-f', 'hls',
            hls_master_playlist_path
        ]
        
        try:
            print(f"Executing FFmpeg: {' '.join(ffmpeg_command)}")
            process = subprocess.Popen(ffmpeg_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            stdout, stderr = process.communicate()

            if process.returncode != 0:
                print(f"FFmpeg Error STDOUT: {stdout.decode('utf-8', 'ignore')}")
                print(f"FFmpeg Error STDERR: {stderr.decode('utf-8', 'ignore')}")
                # Clean up partial HLS files if ffmpeg fails? For now, no.
                os.remove(temp_upload_path) # Clean up uploaded raw file
                return jsonify({'error': 'FFmpeg processing failed.', 'details': stderr.decode('utf-8', 'ignore')}), 500
            
            print(f"FFmpeg STDOUT: {stdout.decode('utf-8', 'ignore')}")
            if stderr:
                 print(f"FFmpeg STDERR (warnings/info): {stderr.decode('utf-8', 'ignore')}")


            # Clean up the original uploaded file after successful processing
            os.remove(temp_upload_path)

            # Construct the URL for the HLS master playlist
            hls_stream_url = f'/video_stream/{video_id}/{hls_master_playlist_name}'
            return jsonify({
                'message': 'Video processed successfully!',
                'hls_url': hls_stream_url,
                'video_id': video_id
            }), 200

        except Exception as e:
            print(f"Error during FFmpeg processing or file handling: {e}")
            if os.path.exists(temp_upload_path):
                os.remove(temp_upload_path) # Clean up uploaded raw file
            return jsonify({'error': f'An server error occurred: {str(e)}'}), 500
    else:
        return jsonify({'error': 'File type not allowed'}), 400


@app.route('/video_stream/<video_id>/<path:filename>')
def serve_hls_stream(video_id, filename):
    """Serves HLS manifest (m3u8) and segment (ts) files for a specific video_id."""
    # Sanitize video_id to prevent directory traversal, though UUIDs are generally safe
    safe_video_id = secure_filename(video_id) # Basic sanitization
    if not safe_video_id == video_id: # check if sanitization changed it (e.g. removed ../)
        return "Invalid video ID", 400

    hls_dir = os.path.join(app.config['HLS_OUTPUT_FOLDER'], safe_video_id)
    return send_from_directory(hls_dir, filename)

if __name__ == '__main__':
    print(f"Uploads will be stored in: {app.config['UPLOAD_FOLDER']}")
    print(f"HLS outputs will be in subfolders of: {app.config['HLS_OUTPUT_FOLDER']}")
    print("WARNING: FFmpeg processing is SYNCHRONOUS. This is not suitable for production.")
    print("For production, use a task queue like Celery.")
    app.run(debug=True, host='0.0.0.0', port=5000)
EOF

# Create templates/index.html
cat <<EOF > "${PROJECT_FILES_DIR}/templates/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Interactive Video Processor (Flask)</title>
    <link href="https://vjs.zencdn.net/8.10.0/video-js.css" rel="stylesheet" />
    <link href="{{ url_for('static', filename='css/style.css') }}" rel="stylesheet" />
</head>
<body>
    <div class="container">
        <h1>Interactive HLS Video Player</h1>

        <div class="upload-section">
            <h2>Upload Your Video (e.g., MP4)</h2>
            <form id="videoUploadForm">
                <input type="file" id="videoFile" name="videoFile" accept="video/mp4,video/quicktime,video/x-matroska,video/webm,video/x-msvideo" required>
                <button type="submit">Upload and Process</button>
            </form>
            <div id="uploadStatus" class="status-message"></div>
        </div>

        <div id="playerArea" class="hidden">
            <div class="player-container">
                <video
                    id="my-video"
                    class="video-js vjs-default-skin vjs-big-play-centered"
                    controls
                    preload="auto"
                    width="720"
                    height="405"
                    data-setup='{}'>
                    <!-- HLS Source will be set by JavaScript -->
                </video>

                <div class="subtitle-controls">
                    <h3>Upload Subtitles (VTT format)</h3>
                    <div>
                        <label for="sub-az">Azerbaijani (AZ):</label>
                        <input type="file" id="sub-az" accept=".vtt" data-lang="az" data-label="Azerbaijani" disabled>
                    </div>
                    <div>
                        <label for="sub-en">English (EN):</label>
                        <input type="file" id="sub-en" accept=".vtt" data-lang="en" data-label="English" disabled>
                    </div>
                    <div>
                        <label for="sub-ru">Russian (RU):</label>
                        <input type="file" id="sub-ru" accept=".vtt" data-lang="ru" data-label="Russian" disabled>
                    </div>
                </div>
            </div>
        </div>
        <div id="initialMessage">
            <p>Please upload a video to start.</p>
            <p>For testing, you can download the Sintel trailer (<a href="http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4" target="_blank" rel="noopener noreferrer">Sintel.mp4</a>) and upload it.</p>
        </div>


        <div id="interaction-overlay" class="hidden">
            <div id="interaction-content">
                <!-- Content will be injected here -->
            </div>
            <button id="continue-button">Continue Video</button>
        </div>
    </div>

    <script src="https://vjs.zencdn.net/8.10.0/video.min.js"></script>
    <script src="{{ url_for('static', filename='js/script.js') }}"></script>
</body>
</html>
EOF

# Create static/css/style.css
# (Using a slightly modified version of the previous style.css)
cat <<EOF > "${PROJECT_FILES_DIR}/static/css/style.css"
body {
    font-family: Arial, sans-serif;
    margin: 0;
    padding: 0;
    background-color: #f0f2f5;
    color: #333;
    display: flex;
    justify-content: center; /* Center the main container */
    min-height: 100vh;
}

.container {
    width: 100%;
    max-width: 900px; /* Max width for the whole content area */
    padding: 20px;
    box-sizing: border-box;
}

h1, h2 {
    color: #1c1e21;
    text-align: center;
}
h1 { margin-bottom: 30px; }
h2 { margin-bottom: 15px; font-size: 1.5em; }

.upload-section {
    background: #fff;
    padding: 20px;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    margin-bottom: 30px;
    text-align: center;
}

#videoUploadForm input[type="file"] {
    margin-bottom: 15px;
    display: block;
    margin-left: auto;
    margin-right: auto;
}

#videoUploadForm button {
    background-color: #007bff;
    color: white;
    border: none;
    padding: 10px 20px;
    border-radius: 5px;
    cursor: pointer;
    font-size: 1em;
}
#videoUploadForm button:hover {
    background-color: #0056b3;
}

.status-message {
    margin-top: 15px;
    font-weight: bold;
}
.status-message.error { color: red; }
.status-message.success { color: green; }

#playerArea.hidden, #initialMessage.hidden {
    display: none;
}

#initialMessage {
    text-align: center;
    padding: 20px;
    background: #e9ecef;
    border-radius: 8px;
    margin-bottom: 20px;
}

.player-container {
    background: #fff;
    padding: 20px;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    margin-bottom: 20px;
    display: flex; /* For centering player if smaller than container */
    flex-direction: column;
    align-items: center;
}

.video-js {
    border-radius: 6px;
    width: 100%; /* Make player responsive */
    max-width: 720px; /* Control max player width */
    height: auto;
}

.subtitle-controls {
    margin-top: 20px;
    padding: 15px;
    border: 1px solid #dddfe2;
    border-radius: 6px;
    background-color: #f7f8fa;
    width: 100%;
    max-width: 720px; /* Match player width */
    box-sizing: border-box;
}

.subtitle-controls h3 {
    margin-top: 0;
    font-size: 1.1em;
    color: #333;
    text-align: left;
}

.subtitle-controls div {
    margin-bottom: 10px;
    display: flex;
    align-items: center;
}

.subtitle-controls label {
    margin-right: 10px;
    min-width: 130px;
    font-weight: bold;
    font-size: 0.9em;
}

.subtitle-controls input[type="file"]:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

#interaction-overlay {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background-color: rgba(0, 0, 0, 0.75);
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    z-index: 10000;
    opacity: 0;
    visibility: hidden;
    transition: opacity 0.3s ease, visibility 0.3s ease;
}

#interaction-overlay.visible {
    opacity: 1;
    visibility: visible;
}

#interaction-content {
    background-color: white;
    padding: 30px 40px;
    border-radius: 8px;
    min-width: 320px;
    max-width: 600px;
    max-height: 80vh;
    overflow-y: auto;
    text-align: center;
    box-shadow: 0 5px 15px rgba(0,0,0,0.3);
}
#interaction-content h2 { margin-top: 0; color: #1c1e21; }
#interaction-content p { font-size: 1.1em; line-height: 1.6; }
#interaction-content img { max-width: 100%; height: auto; border-radius: 4px; margin-top: 15px; }
#interaction-content button {
    background-color: #007bff; color: white; border: none;
    padding: 10px 15px; margin: 5px; border-radius: 5px; cursor: pointer; font-size: 1em;
}
#interaction-content button:hover { background-color: #0056b3; }

#continue-button {
    margin-top: 25px; padding: 12px 25px; font-size: 1.1em; font-weight: bold;
    cursor: pointer; background-color: #4CAF50; color: white; border: none;
    border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);
    transition: background-color 0.2s ease;
}
#continue-button:hover { background-color: #45a049; }

.video-js .vjs-control-bar { z-index: 1; }
EOF

# Create static/js/script.js
cat <<EOF > "${PROJECT_FILES_DIR}/static/js/script.js"
document.addEventListener('DOMContentLoaded', () => {
    const videoUploadForm = document.getElementById('videoUploadForm');
    const videoFileInput = document.getElementById('videoFile');
    const uploadStatus = document.getElementById('uploadStatus');
    const playerArea = document.getElementById('playerArea');
    const initialMessage = document.getElementById('initialMessage');
    
    let player; // Player instance, will be initialized after video processing

    const interactionOverlay = document.getElementById('interaction-overlay');
    const interactionContent = document.getElementById('interaction-content');
    const continueButton = document.getElementById('continue-button');
    const subtitleInputs = document.querySelectorAll('.subtitle-controls input[type="file"]');

    // --- Video Upload Handling ---
    videoUploadForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        if (!videoFileInput.files || videoFileInput.files.length === 0) {
            uploadStatus.textContent = 'Please select a video file.';
            uploadStatus.className = 'status-message error';
            return;
        }

        const formData = new FormData();
        formData.append('videoFile', videoFileInput.files[0]);

        uploadStatus.textContent = 'Uploading and processing video... This may take a moment.';
        uploadStatus.className = 'status-message'; // Neutral style

        try {
            const response = await fetch('/upload_video', {
                method: 'POST',
                body: formData,
            });

            const result = await response.json();

            if (!response.ok) {
                uploadStatus.textContent = \`Error: \${result.error || 'Upload failed.'} \${result.details ? '('+result.details+')' : ''}\`;
                uploadStatus.className = 'status-message error';
                return;
            }

            uploadStatus.textContent = 'Video processed! Loading player...';
            uploadStatus.className = 'status-message success';
            initialMessage.classList.add('hidden');
            playerArea.classList.remove('hidden');
            
            // Initialize or update player
            initializePlayer(result.hls_url);
            enableSubtitleUploads();

        } catch (error) {
            console.error('Upload error:', error);
            uploadStatus.textContent = 'An unexpected error occurred during upload.';
            uploadStatus.className = 'status-message error';
        }
    });

    function enableSubtitleUploads() {
        subtitleInputs.forEach(input => input.disabled = false);
    }

    function initializePlayer(hlsUrl) {
        if (player) {
            player.dispose(); // Dispose existing player if any
        }
        const videoElement = document.getElementById('my-video');
        // Ensure video element is fresh if dynamically re-adding or changing significantly
        // For src change, Video.js handles it, but if attributes changed:
        // videoElement.setAttribute('data-setup', '{}'); // Re-init if needed

        player = videojs(videoElement, {
            html5: {
              vhs: { overrideNative: true }
            }
        });

        player.src({
            src: hlsUrl,
            type: 'application/x-mpegURL'
        });

        player.ready(() => {
            console.log('Player is ready with HLS stream:', hlsUrl);
            // Re-attach event listeners for interactions if needed, or ensure they target 'player'
            setupPlayerInteractions();
            setupSubtitleHandling(); // Re-initialize subtitle logic for the new player instance
        });

        player.on('error', () => {
            const error = player.error();
            console.error('Video.js Error:', error);
            uploadStatus.textContent = \`Video player error: \${error ? error.message : 'Unknown error'}\`;
            uploadStatus.className = 'status-message error';
            if (error && error.code === 4) { // MEDIA_ERR_SRC_NOT_SUPPORTED
                 uploadStatus.textContent += " (Could not load HLS stream. Check server logs and FFmpeg output.)";
            }
        });
    }

    // --- Subtitle Handling (needs to be re-callable if player re-initialized) ---
    let loadedTracks = {};
    function setupSubtitleHandling() {
        loadedTracks = {}; // Reset for new player instance
        subtitleInputs.forEach(input => {
            // Clone and replace to remove old event listeners if any
            const newInput = input.cloneNode(true);
            input.parentNode.replaceChild(newInput, input);

            newInput.addEventListener('change', function(event) {
                if (!player) return; // Player not ready
                const file = event.target.files[0];
                if (file) {
                    const lang = this.dataset.lang;
                    const label = this.dataset.label;
                    const reader = new FileReader();

                    reader.onload = function(e) {
                        if (loadedTracks[lang] && loadedTracks[lang].track) {
                            try {
                                player.removeRemoteTextTrack(loadedTracks[lang].track);
                            } catch (removeError) {
                                console.warn("Could not remove old track for", lang, removeError);
                            }
                            if (loadedTracks[lang].blobUrl) {
                                URL.revokeObjectURL(loadedTracks[lang].blobUrl);
                            }
                        }
                        
                        const blobUrl = URL.createObjectURL(file);
                        const trackData = {
                            kind: 'subtitles', src: blobUrl, srclang: lang, label: label,
                            default: lang === 'en'
                        };
                        
                        const newTrackElement = player.addRemoteTextTrack(trackData, false);
                        // The object returned by addRemoteTextTrack is what you need for removeRemoteTextTrack
                        loadedTracks[lang] = { track: newTrackElement, blobUrl: blobUrl }; 
                        console.log(\`Added \${label} subtitles.\`);
                    };
                    reader.readAsText(file);
                }
            });
        });

        if (player) {
             player.on('dispose', () => {
                Object.values(loadedTracks).forEach(trackInfo => {
                    if (trackInfo.blobUrl) {
                        URL.revokeObjectURL(trackInfo.blobUrl);
                    }
                });
                loadedTracks = {};
            });
        }
    }
    

    // --- Timed Stops and Interaction (needs to be re-callable) ---
    const stopPoints = [
        { time: 5, triggered: false, content: \`<h2>Checkpoint 1!</h2><p>First stop. Video uploaded and playing via HLS!</p>\` },
        { time: 12, triggered: false, content: \`<h2>Quiz Time!</h2><p>What format are the subtitles?</p><button onclick="alert('Correct! VTT is used.')">VTT</button> <button onclick="alert('Nope!')">SRT</button>\`},
        { time: 20, triggered: false, content: \`<h2>Section End</h2><p>Nice work making it this far.</p>\`}
    ];

    function setupPlayerInteractions() {
        if (!player) return;

        player.on('timeupdate', () => {
            if (!player || player.seeking() || !player.duration()) return; // Player not ready or seeking

            const currentTime = player.currentTime();
            for (let i = 0; i < stopPoints.length; i++) {
                const stop = stopPoints[i];
                if (!stop.triggered && currentTime >= stop.time && currentTime < stop.time + 0.7 && !interactionOverlay.classList.contains('visible')) {
                    player.pause();
                    interactionContent.innerHTML = stop.content;
                    interactionOverlay.classList.remove('hidden');
                    interactionOverlay.classList.add('visible');
                    stop.triggered = true;
                    break;
                }
            }
        });

        continueButton.onclick = () => { // Use .onclick to ensure it's fresh or remove old listener
            interactionOverlay.classList.remove('visible');
            interactionOverlay.classList.add('hidden');
            if (player) player.play();
        };

        player.on('seeking', () => {
            if(!player || !player.duration()) return;
            const currentTime = player.currentTime();
            stopPoints.forEach(stop => {
                if (currentTime < stop.time) stop.triggered = false;
            });
        });
        
        player.on('play', () => {
            if (player && player.currentTime() < 1) { // Reset if played from beginning
                 stopPoints.forEach(stop => stop.triggered = false);
            }
        });

        player.on('ended', () => {
            stopPoints.forEach(stop => stop.triggered = false);
        });
    }
});
EOF

# Placeholder files for git to track empty directories initially
touch "${PROJECT_FILES_DIR}/media/uploads/.gitkeep"
touch "${PROJECT_FILES_DIR}/media/hls_outputs/.gitkeep"

# Go back to the directory where the script was initially run
cd ..

echo ""
echo "Project '${PROJECT_DIR}' created successfully!"
echo "--------------------------------------------------"
echo "To get started:"
echo "1. cd ${PROJECT_DIR}"
echo "2. Review the README.md for setup instructions."
echo "   (Especially: install FFmpeg, set up venv, install requirements, run Flask)"
echo "--------------------------------------------------"
echo "Then, from inside '${PROJECT_FILES_DIR}':"
echo "   python3 -m venv venv"
echo "   source venv/bin/activate  # or venv\\Scripts\\activate on Windows"
echo "   pip install -r requirements.txt"
echo "   python app.py"
echo "--------------------------------------------------"
echo "Open http://127.0.0.1:5000 in your browser."
echo "Download Sintel trailer (http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4) to test the upload."

exit 0