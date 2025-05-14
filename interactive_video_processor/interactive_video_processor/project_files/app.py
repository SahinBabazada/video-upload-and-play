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
    return '.' in filename and            filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

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
    app.run(debug=True, host='0.0.0.0', port=8000)
