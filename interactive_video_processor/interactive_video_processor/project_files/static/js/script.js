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
                uploadStatus.textContent = `Error: ${result.error || 'Upload failed.'} ${result.details ? '('+result.details+')' : ''}`;
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
            uploadStatus.textContent = `Video player error: ${error ? error.message : 'Unknown error'}`;
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
                        console.log(`Added ${label} subtitles.`);
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
        { time: 5, triggered: false, content: `<h2>Checkpoint 1!</h2><p>First stop. Video uploaded and playing via HLS!</p>` },
        { time: 12, triggered: false, content: `<h2>Quiz Time!</h2><p>What format are the subtitles?</p><button onclick="alert('Correct! VTT is used.')">VTT</button> <button onclick="alert('Nope!')">SRT</button>`},
        { time: 20, triggered: false, content: `<h2>Section End</h2><p>Nice work making it this far.</p>`}
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
